import 'package:flutter/material.dart';
import 'package:bluey_android/bluey_android.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

void main() {
  // Register Android platform implementation
  BlueyAndroid.registerWith();

  runApp(const BlueyExampleApp());
}

class BlueyExampleApp extends StatelessWidget {
  const BlueyExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluey Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ScannerScreen(),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final BlueyPlatform _bluey = BlueyPlatform.instance;
  final List<PlatformDevice> _devices = [];
  bool _isScanning = false;
  BluetoothState _bluetoothState = BluetoothState.unknown;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    // Get initial state
    final state = await _bluey.getState();
    setState(() {
      _bluetoothState = state;
    });

    // Listen to state changes
    _bluey.stateStream.listen((state) {
      setState(() {
        _bluetoothState = state;
      });
    });
  }

  Future<void> _startScan() async {
    setState(() {
      _devices.clear();
      _isScanning = true;
    });

    final config = PlatformScanConfig(
      serviceUuids: const [],
      timeoutMs: 10000, // 10 second timeout
    );

    _bluey.scan(config).listen(
      (device) {
        setState(() {
          // Update existing device or add new one
          final index = _devices.indexWhere((d) => d.id == device.id);
          if (index >= 0) {
            _devices[index] = device;
          } else {
            _devices.add(device);
          }
        });
      },
      onDone: () {
        setState(() {
          _isScanning = false;
        });
      },
      onError: (error) {
        setState(() {
          _isScanning = false;
        });
        _showError('Scan error: $error');
      },
    );
  }

  Future<void> _stopScan() async {
    await _bluey.stopScan();
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _connectToDevice(PlatformDevice device) async {
    try {
      final config = PlatformConnectConfig(
        timeoutMs: 10000,
        mtu: null,
      );

      final connectionId = await _bluey.connect(device.id, config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to ${device.name ?? device.id}')),
        );

        // Listen to connection state
        _bluey.connectionStateStream(connectionId).listen(
          (state) {
            debugPrint('Connection state: $state');
          },
          onError: (error) {
            debugPrint('Connection error: $error');
          },
        );
      }
    } catch (e) {
      _showError('Connection failed: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluey Scanner'),
        actions: [
          // Bluetooth state indicator
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: _buildStateChip(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Control buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: const Icon(Icons.search),
                  label: const Text('Start Scan'),
                ),
                ElevatedButton.icon(
                  onPressed: _isScanning ? _stopScan : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Scan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Scanning indicator
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),

          // Device list
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Text(
                      _isScanning
                          ? 'Scanning for devices...'
                          : 'No devices found. Tap "Start Scan" to begin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return _buildDeviceCard(device);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateChip() {
    Color color;
    IconData icon;
    String label;

    switch (_bluetoothState) {
      case BluetoothState.on:
        color = Colors.green;
        icon = Icons.bluetooth;
        label = 'ON';
        break;
      case BluetoothState.off:
        color = Colors.orange;
        icon = Icons.bluetooth_disabled;
        label = 'OFF';
        break;
      case BluetoothState.unauthorized:
        color = Colors.red;
        icon = Icons.lock;
        label = 'NO PERMISSION';
        break;
      case BluetoothState.unsupported:
        color = Colors.grey;
        icon = Icons.error;
        label = 'UNSUPPORTED';
        break;
      case BluetoothState.unknown:
        color = Colors.grey;
        icon = Icons.help;
        label = 'UNKNOWN';
        break;
    }

    return Chip(
      avatar: Icon(icon, color: Colors.white, size: 16),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
    );
  }

  Widget _buildDeviceCard(PlatformDevice device) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue,
          child: const Icon(Icons.bluetooth, color: Colors.white),
        ),
        title: Text(
          device.name ?? 'Unknown Device',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Address: ${device.id}'),
            Text('RSSI: ${device.rssi} dBm'),
            if (device.serviceUuids.isNotEmpty)
              Text('Services: ${device.serviceUuids.length}'),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.connect_without_contact),
          onPressed: () => _connectToDevice(device),
          tooltip: 'Connect',
        ),
        isThreeLine: true,
      ),
    );
  }
}
