import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_ui.dart';

// UUID harus SAMA PERSIS dengan firmware ESP32.
const _svc = '12345678-1234-5678-1234-56789abcdef0';
const _ssidUuid = '12345678-1234-5678-1234-56789abcdef3'; // Write
const _passUuid = '12345678-1234-5678-1234-56789abcdef4'; // Write
const _cmdUuid = '12345678-1234-5678-1234-56789abcdef5'; // Write: 1=apply, 0=hapus
const _statusUuid = '12345678-1234-5678-1234-56789abcdef6'; // Read + Notify

class WifiProvisionPage extends StatefulWidget {
  const WifiProvisionPage({super.key});

  @override
  State<WifiProvisionPage> createState() => _WifiProvisionPageState();
}

class _WifiProvisionPageState extends State<WifiProvisionPage> {
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  List<ScanResult> _results = [];
  BluetoothDevice? _device;
  BluetoothCharacteristic? _ssidChar, _passChar, _cmdChar, _statusChar;
  StreamSubscription? _scanSub, _notifySub, _connSub;

  bool _scanning = false;
  bool _busy = false;
  bool _hidePass = true;

  // status koneksi BLE
  String _status = 'Belum terhubung';
  ConnState _state = ConnState.idle;

  // status provisioning dari ESP32
  String _provText = '-';
  ConnState _provState = ConnState.idle;
  bool _wifiOk = false, _mqttOk = false, _wifiFail = false, _mqttFail = false;

  void _set(String text, ConnState s) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _state = s;
    });
  }

  // Menerjemahkan kode status dari ESP32. Hanya mengisi variabel,
  // pemanggil yang bertanggung jawab memanggil setState.
  void _applyProv(String raw) {
    final r = raw.trim();
    _wifiOk = _mqttOk = _wifiFail = _mqttFail = false;
    _provText = _label(r);

    switch (r) {
      case 'connecting':
        _provState = ConnState.busy;
        break;
      case 'wifi_ok':
        _provState = ConnState.busy;
        _wifiOk = true;
        break;
      case 'mqtt_ok':
        _provState = ConnState.ok;
        _wifiOk = true;
        _mqttOk = true;
        break;
      case 'wifi_fail':
        _provState = ConnState.error;
        _wifiFail = true;
        break;
      case 'mqtt_fail':
        _provState = ConnState.error;
        _wifiOk = true;
        _mqttFail = true;
        break;
      default:
        _provState = ConnState.idle;
    }
  }

  String _label(String raw) {
    switch (raw) {
      case 'idle':
        return 'Belum ada kredensial WiFi di ESP32';
      case 'saved':
        return 'Kredensial tersimpan di ESP32';
      case 'connecting':
        return 'ESP32 sedang menyambung ke WiFi...';
      case 'wifi_ok':
        return 'WiFi tersambung, menyambung ke MQTT...';
      case 'mqtt_ok':
        return 'Berhasil! ESP32 terhubung ke WiFi dan MQTT';
      case 'wifi_fail':
        return 'Gagal WiFi: SSID/password salah atau hotspot 5 GHz';
      case 'mqtt_fail':
        return 'WiFi OK, tetapi broker MQTT tidak terjangkau';
      case 'cleared':
        return 'Kredensial di ESP32 sudah dihapus';
      default:
        return raw;
    }
  }

  // ---------- SCAN ----------
  Future<void> _scan() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final adapter = await FlutterBluePlus.adapterState.first;
    if (adapter != BluetoothAdapterState.on) {
      _set('Aktifkan Bluetooth terlebih dahulu', ConnState.error);
      return;
    }

    setState(() {
      _results = [];
      _scanning = true;
    });
    _set('Memindai...', ConnState.busy);

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((r) {
      if (mounted) setState(() => _results = r);
    });

    await FlutterBluePlus.startScan(
      withServices: [Guid(_svc)],
      timeout: const Duration(seconds: 6),
    );
    if (mounted) {
      setState(() => _scanning = false);
      _set(
        _results.isEmpty
            ? 'Pemindaian selesai, perangkat tidak ditemukan'
            : 'Pemindaian selesai, pilih perangkat',
        ConnState.idle,
      );
    }
  }

  // ---------- CONNECT ----------
  Future<void> _connect(BluetoothDevice d) async {
    await FlutterBluePlus.stopScan();
    _set('Menghubungkan...', ConnState.busy);

    try {
      await d.connect(timeout: const Duration(seconds: 10));
      // MTU besar supaya SSID/password panjang tidak terpotong
      if (!kIsWeb && Platform.isAndroid) await d.requestMtu(247);

      final services = await d.discoverServices();
      for (final s in services) {
        if (s.uuid != Guid(_svc)) continue;
        for (final c in s.characteristics) {
          if (c.uuid == Guid(_ssidUuid)) _ssidChar = c;
          if (c.uuid == Guid(_passUuid)) _passChar = c;
          if (c.uuid == Guid(_cmdUuid)) _cmdChar = c;
          if (c.uuid == Guid(_statusUuid)) _statusChar = c;
        }
      }

      if (_ssidChar == null ||
          _passChar == null ||
          _cmdChar == null ||
          _statusChar == null) {
        throw 'Characteristic provisioning tidak ditemukan. '
            'Cek firmware dan UUID.';
      }

      await _statusChar!.setNotifyValue(true);
      _notifySub = _statusChar!.onValueReceived.listen((v) {
        if (mounted) setState(() => _applyProv(utf8.decode(v)));
      });

      final first = await _statusChar!.read();
      _applyProv(utf8.decode(first));
    } catch (e) {
      try {
        await d.disconnect();
      } catch (_) {}
      _set('Gagal: $e', ConnState.error);
      return;
    }

    _connSub = d.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && mounted) {
        setState(() {
          _device = null;
          _ssidChar = _passChar = _cmdChar = _statusChar = null;
        });
        _set('Terputus', ConnState.idle);
      }
    });

    if (mounted) {
      setState(() => _device = d);
      _set('Terhubung ke ${d.platformName}', ConnState.ok);
    }
  }

  // ---------- KIRIM KREDENSIAL ----------
  Future<void> _send() async {
    final ssid = _ssidCtrl.text;
    final pass = _passCtrl.text;

    if (ssid.trim().isEmpty) {
      _toast('SSID tidak boleh kosong');
      return;
    }
    if (utf8.encode(ssid).length > 32) {
      _toast('SSID maksimal 32 byte');
      return;
    }
    if (pass.isNotEmpty && (pass.length < 8 || pass.length > 63)) {
      _toast('Password WiFi harus 8-63 karakter (kosongkan jika WiFi terbuka)');
      return;
    }

    setState(() {
      _busy = true;
      _wifiOk = _mqttOk = _wifiFail = _mqttFail = false;
      _provText = 'Mengirim kredensial ke ESP32...';
      _provState = ConnState.busy;
    });

    try {
      await _ssidChar!.write(utf8.encode(ssid), allowLongWrite: true);
      await _passChar!.write(utf8.encode(pass), allowLongWrite: true);
      await _cmdChar!.write([1]); // perintah: simpan + sambungkan
      // Status selanjutnya datang lewat notify dari ESP32
    } catch (e) {
      if (mounted) {
        setState(() {
          _provText = 'Gagal mengirim: $e';
          _provState = ConnState.error;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    try {
      await _cmdChar!.write([0]); // perintah: hapus kredensial tersimpan
    } catch (e) {
      if (mounted) {
        setState(() {
          _provText = 'Gagal: $e';
          _provState = ConnState.error;
        });
      }
    }
  }

  Future<void> _disconnect() async => _device?.disconnect();

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _notifySub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _device != null ? _buildForm() : _buildScan(),
    );
  }

  Widget _buildScan() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusBanner(text: _status, state: _state),
        const SizedBox(height: 12),
        AppCard(
          title: 'Hubungkan ke ESP32',
          icon: Icons.bluetooth_searching,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Putuskan dulu koneksi di tab BLE agar ESP32 bisa ditemukan.',
                style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: const Icon(Icons.search),
                  label: Text(_scanning ? 'Memindai...' : 'Scan perangkat'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _results.isEmpty
              ? const EmptyHint(
                  icon: Icons.wifi_tethering_off,
                  text: 'Belum ada perangkat.\nTekan Scan untuk mencari ESP32.',
                )
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final r = _results[i];
                    final name = r.device.platformName.isEmpty
                        ? r.device.remoteId.str
                        : r.device.platformName;
                    return AppCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(
                          Icons.memory,
                          color: AppColors.goldDark,
                          size: 30,
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('RSSI ${r.rssi} dBm'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _connect(r.device),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return ListView(
      children: [
        StatusBanner(text: _status, state: _state),
        const SizedBox(height: 12),
        AppCard(
          title: 'Langkah 1 · Isi kredensial WiFi',
          icon: Icons.wifi,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _ssidCtrl,
                decoration: appInput(
                  label: 'SSID WiFi (2.4 GHz)',
                  icon: Icons.router,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: _hidePass,
                decoration: appInput(
                  label: 'Password WiFi',
                  icon: Icons.lock,
                  suffix: IconButton(
                    icon: Icon(
                      _hidePass ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _hidePass = !_hidePass),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'ESP32 hanya mendukung WiFi 2.4 GHz.',
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Langkah 2 · Kirim ke ESP32',
          icon: Icons.send,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Kirim & simpan ke ESP32'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _clear,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Hapus kredensial di ESP32'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Langkah 3 · Pantau status',
          icon: Icons.monitor_heart,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusBanner(text: _provText, state: _provState),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PillBadge(
                    text: 'WiFi',
                    state: _wifiFail
                        ? ConnState.error
                        : (_wifiOk ? ConnState.ok : ConnState.idle),
                  ),
                  PillBadge(
                    text: 'MQTT',
                    state: _mqttFail
                        ? ConnState.error
                        : (_mqttOk ? ConnState.ok : ConnState.idle),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _disconnect,
          icon: const Icon(Icons.link_off),
          label: const Text('Putuskan'),
        ),
      ],
    );
  }
}