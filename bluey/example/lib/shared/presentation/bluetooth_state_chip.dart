import 'package:flutter/material.dart';
import 'package:bluey/bluey.dart' as bluey;

/// A chip widget that displays the current Bluetooth state.
class BluetoothStateChip extends StatelessWidget {
  final bluey.BluetoothState state;

  const BluetoothStateChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (state) {
      bluey.BluetoothState.on => (Colors.green, Icons.bluetooth, 'ON'),
      bluey.BluetoothState.off => (
        Colors.orange,
        Icons.bluetooth_disabled,
        'OFF',
      ),
      bluey.BluetoothState.unauthorized => (
        Colors.red,
        Icons.lock,
        'NO PERMISSION',
      ),
      bluey.BluetoothState.unsupported => (
        Colors.grey,
        Icons.error,
        'UNSUPPORTED',
      ),
      bluey.BluetoothState.unknown => (
        Colors.grey,
        Icons.help_outline,
        'UNKNOWN',
      ),
    };

    return Chip(
      avatar: Icon(icon, color: Colors.white, size: 16),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// A chip widget that displays the connection state.
class ConnectionStateChip extends StatelessWidget {
  final bluey.ConnectionState state;

  const ConnectionStateChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      bluey.ConnectionState.ready => (Colors.green, 'Connected'),
      bluey.ConnectionState.linked => (Colors.lightGreen, 'Linked'),
      bluey.ConnectionState.connecting => (Colors.orange, 'Connecting'),
      bluey.ConnectionState.disconnecting => (Colors.orange, 'Disconnecting'),
      bluey.ConnectionState.disconnected => (Colors.grey, 'Disconnected'),
    };

    return Chip(
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// A chip widget that displays the advertising state.
class AdvertisingStateChip extends StatelessWidget {
  final bool isAdvertising;

  const AdvertisingStateChip({super.key, required this.isAdvertising});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        isAdvertising ? Icons.cell_tower : Icons.cell_tower_outlined,
        color: Colors.white,
        size: 16,
      ),
      label: Text(
        isAdvertising ? 'Advertising' : 'Idle',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: isAdvertising ? Colors.green : Colors.grey,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
