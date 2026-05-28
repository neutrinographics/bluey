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
      bluey.ConnectionState.invalidated => (Colors.red, 'Invalidated'),
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
  final bluey.AdvertisingState advertisingState;

  const AdvertisingStateChip({super.key, required this.advertisingState});

  @override
  Widget build(BuildContext context) {
    final (color, avatar, label) = switch (advertisingState) {
      bluey.AdvertisingState.idle => (
        Colors.grey,
        const Icon(Icons.cell_tower_outlined, color: Colors.white, size: 16),
        'Idle',
      ),
      bluey.AdvertisingState.starting => (
        Colors.orange,
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        'Starting',
      ),
      bluey.AdvertisingState.advertising => (
        Colors.green,
        const Icon(Icons.cell_tower, color: Colors.white, size: 16),
        'Advertising',
      ),
      bluey.AdvertisingState.stopping => (
        Colors.orange,
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        'Stopping',
      ),
      bluey.AdvertisingState.invalidated => (
        Colors.red,
        const Icon(Icons.error_outline, color: Colors.white, size: 16),
        'Invalidated',
      ),
    };

    return Chip(
      avatar: avatar,
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
