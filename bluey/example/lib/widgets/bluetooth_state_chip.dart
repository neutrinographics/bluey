import 'package:flutter/material.dart';
import 'package:bluey/bluey.dart';

class BluetoothStateChip extends StatelessWidget {
  final BluetoothState state;

  const BluetoothStateChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (state) {
      BluetoothState.on => (Colors.green, Icons.bluetooth, 'ON'),
      BluetoothState.off => (Colors.orange, Icons.bluetooth_disabled, 'OFF'),
      BluetoothState.unauthorized => (Colors.red, Icons.lock, 'NO PERMISSION'),
      BluetoothState.unsupported => (Colors.grey, Icons.error, 'UNSUPPORTED'),
      BluetoothState.unknown => (Colors.grey, Icons.help_outline, 'UNKNOWN'),
    };

    return Chip(
      avatar: Icon(icon, color: Colors.white, size: 16),
      label: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
