import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'ble_page.dart';
import 'mqtt_page.dart';
import 'wifi_provision_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile IoT Lab - Kelompok 3',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mobile IoT Lab - Kelompok 3',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: AppColors.butterDeep,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        // IndexedStack menjaga koneksi BLE dan MQTT tetap hidup saat pindah tab
        child: IndexedStack(
          index: _i,
          children: const [
            BlePage(),
            MqttPage(),
            WifiProvisionPage(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        backgroundColor: AppColors.cream,
        indicatorColor: AppColors.gold,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bluetooth), label: 'BLE'),
          NavigationDestination(icon: Icon(Icons.cloud), label: 'MQTT'),
          NavigationDestination(
            icon: Icon(Icons.wifi_tethering),
            label: 'Setup WiFi',
          ),
        ],
      ),
    );
  }
}