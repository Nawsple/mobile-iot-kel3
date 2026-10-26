import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_ui.dart';

const serviceUuid = '12345678-1234-5678-1234-56789abcdef0';
const ledUuid = '12345678-1234-5678-1234-56789abcdef1';
const sensorUuid = '12345678-1234-5678-1234-56789abcdef2';

class BlePage extends StatefulWidget {
  const BlePage({super.key});

  @override
  State<BlePage> createState() => _BlePageState();
}

class _BlePageState extends State<BlePage> {
  List<ScanResult> _results = [];
  BluetoothDevice? _device;
  BluetoothCharacteristic? _ledChar;
  StreamSubscription? _scanSub, _notifySub, _connSub;
  bool _scanning = false;
  bool _ledOn = false;
  String _suhu = '-', _hum = '-';
  String _status = 'Belum terhubung';
  ConnState _state = ConnState.idle;

  void _set(String text, ConnState s) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _state = s;
    });
  }

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
      withServices: [Guid(serviceUuid)],
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

  Future<void> _connect(BluetoothDevice d) async {
    await FlutterBluePlus.stopScan();
    _set('Menghubungkan...', ConnState.busy);
    try {
      await d.connect(timeout: const Duration(seconds: 10));
    } catch (e) {
      _set('Gagal terhubung: $e', ConnState.error);
      return;
    }

    _connSub = d.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && mounted) {
        setState(() {
          _device = null;
          _ledChar = null;
        });
        _set('Terputus', ConnState.idle);
      }
    });

    final services = await d.discoverServices();
    for (final s in services) {
      if (s.uuid != Guid(serviceUuid)) continue;
      for (final c in s.characteristics) {
        if (c.uuid == Guid(ledUuid)) _ledChar = c;
        if (c.uuid == Guid(sensorUuid)) {
          await c.setNotifyValue(true);
          _notifySub = c.onValueReceived.listen((v) {
            final p = utf8.decode(v).split(';');
            if (p.length == 2 && mounted) {
              setState(() {
                _suhu = p[0];
                _hum = p[1];
              });
            }
          });
        }
      }
    }

    setState(() => _device = d);
    _set('Terhubung ke ${d.platformName}', ConnState.ok);
  }

  Future<void> _setLed(bool on) async {
    await _ledChar?.write([on ? 1 : 0]);
    setState(() => _ledOn = on);
  }

  Future<void> _disconnect() async {
    await _device?.disconnect();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _notifySub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  IconData _signalIcon(int rssi) {
    if (rssi >= -60) return Icons.signal_cellular_alt;
    if (rssi >= -80) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }

  Color _signalColor(int rssi) {
    if (rssi >= -60) return AppColors.okFg;
    if (rssi >= -80) return AppColors.busyFg;
    return AppColors.errFg;
  }

  @override
  Widget build(BuildContext context) {
    final connected = _device != null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: connected ? _buildConnected() : _buildScan(),
    );
  }

  Widget _buildScan() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusBanner(text: _status, state: _state),
        const SizedBox(height: 12),
        AppCard(
          title: 'Cari perangkat',
          icon: Icons.bluetooth_searching,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: const Icon(Icons.search),
              label: Text(_scanning ? 'Memindai...' : 'Scan perangkat'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _results.isEmpty
              ? const EmptyHint(
                  icon: Icons.bluetooth_disabled,
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
                        leading: Icon(
                          _signalIcon(r.rssi),
                          color: _signalColor(r.rssi),
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

  Widget _buildConnected() {
    return ListView(
      children: [
        StatusBanner(text: _status, state: _state),
        const SizedBox(height: 12),
        AppCard(
          title: 'Kontrol LED',
          icon: Icons.tune,
          child: Row(
            children: [
              Icon(
                _ledOn ? Icons.lightbulb : Icons.lightbulb_outline,
                size: 38,
                color: _ledOn ? Colors.amber.shade700 : AppColors.idleFg,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _ledOn ? 'LED menyala' : 'LED mati',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(value: _ledOn, onChanged: _setLed),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Data sensor (BLE notify)',
          icon: Icons.sensors,
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.thermostat,
                  label: 'Suhu',
                  value: _suhu,
                  unit: '°C',
                  color: AppColors.errFg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  icon: Icons.water_drop,
                  label: 'Kelembapan',
                  value: _hum,
                  unit: '%',
                  color: Colors.blue.shade600,
                ),
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