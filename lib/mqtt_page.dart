import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'app_ui.dart';

const kelompok = 'kel3';
const host = 'broker.emqx.io';
const tSensor = 'polnes/oit/$kelompok/sensor';
const tLed = 'polnes/oit/$kelompok/led';
const tLedState = 'polnes/oit/$kelompok/led/state';
const tStatus = 'polnes/oit/$kelompok/status';

class MqttPage extends StatefulWidget {
  const MqttPage({super.key});

  @override
  State<MqttPage> createState() => _MqttPageState();
}

class _MqttPageState extends State<MqttPage> {
  MqttServerClient? _client;
  bool _connected = false;
  bool _ledOn = false;
  String _suhu = '-', _hum = '-', _device = 'tidak diketahui';
  String _status = 'Belum terhubung';
  ConnState _state = ConnState.idle;

  void _set(String text, ConnState s) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _state = s;
    });
  }

  Future<void> _connect() async {
    final id = 'flutter-$kelompok-${DateTime.now().millisecondsSinceEpoch}';
    final c = MqttServerClient(host, id);
    c.port = 1883;
    c.keepAlivePeriod = 30;
    c.logging(on: false);
    c.onDisconnected = _onDisconnected;
    c.connectionMessage =
        MqttConnectMessage().withClientIdentifier(id).startClean();

    _set('Menghubungkan...', ConnState.busy);
    try {
      await c.connect();
    } catch (e) {
      c.disconnect();
      _set('Gagal: $e', ConnState.error);
      return;
    }

    c.updates!.listen(_onMessage);
    c.subscribe(tSensor, MqttQos.atMostOnce);
    c.subscribe(tLedState, MqttQos.atLeastOnce);
    c.subscribe(tStatus, MqttQos.atLeastOnce);

    setState(() {
      _client = c;
      _connected = true;
    });
    _set('Terhubung ke $host', ConnState.ok);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    final msg = events[0].payload as MqttPublishMessage;
    final text =
        MqttPublishPayload.bytesToStringAsString(msg.payload.message);
    final topic = events[0].topic;
    if (!mounted) return;
    setState(() {
      if (topic == tSensor) {
        try {
          final j = jsonDecode(text);
          _suhu = j['suhu'].toString();
          _hum = j['hum'].toString();
        } catch (_) {
          // format JSON tidak valid, abaikan
        }
      } else if (topic == tLedState) {
        _ledOn = text == 'ON';
      } else if (topic == tStatus) {
        _device = text;
      }
    });
  }

  void _onDisconnected() {
    if (!mounted) return;
    setState(() => _connected = false);
    _set('Terputus dari broker', ConnState.idle);
  }

  void _publish(String topic, String text) {
    final b = MqttClientPayloadBuilder()..addString(text);
    _client?.publishMessage(topic, MqttQos.atLeastOnce, b.payload!);
  }

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          StatusBanner(text: _status, state: _state),
          const SizedBox(height: 12),
          if (!_connected) _buildDisconnected() else ..._buildConnected(),
        ],
      ),
    );
  }

  Widget _buildDisconnected() {
    return AppCard(
      title: 'Broker MQTT',
      icon: Icons.cloud_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Broker', style: TextStyle(color: AppColors.inkSoft)),
          const Text(
            '$host:1883',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('Topik', style: TextStyle(color: AppColors.inkSoft)),
          const Text(
            'polnes/oit/$kelompok/#',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _state == ConnState.busy ? null : _connect,
              icon: const Icon(Icons.power_settings_new),
              label: const Text('Hubungkan'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildConnected() {
    final ConnState devState;
    if (_device == 'online') {
      devState = ConnState.ok;
    } else if (_device == 'offline') {
      devState = ConnState.error;
    } else {
      devState = ConnState.idle;
    }

    return [
      AppCard(
        title: 'Perangkat ESP32',
        icon: Icons.memory,
        child: Row(
          children: [
            const Expanded(child: Text('Status perangkat')),
            PillBadge(text: _device, state: devState),
          ],
        ),
      ),
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
            const Expanded(
              child: Text(
                'Kondisi nyata dari ESP32',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: _ledOn,
              onChanged: (v) => _publish(tLed, v ? 'ON' : 'OFF'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AppCard(
        title: 'Data sensor (MQTT)',
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
        onPressed: () => _client?.disconnect(),
        icon: const Icon(Icons.link_off),
        label: const Text('Putuskan'),
      ),
    ];
  }
}