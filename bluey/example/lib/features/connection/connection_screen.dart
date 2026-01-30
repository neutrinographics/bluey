import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bluey/bluey.dart' as bluey;
import 'package:bluey/bluey.dart' hide ConnectionState;

import '../../main.dart';
import 'service_screen.dart';

class ConnectionScreen extends StatefulWidget {
  final Device device;

  const ConnectionScreen({super.key, required this.device});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  Connection? _connection;
  bluey.ConnectionState _connectionState = bluey.ConnectionState.disconnected;
  StreamSubscription<bluey.ConnectionState>? _stateSubscription;
  List<RemoteService>? _services;
  bool _isDiscovering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _connection?.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connectionState = bluey.ConnectionState.connecting;
      _error = null;
    });

    try {
      final blueyInstance = BlueyProvider.of(context);
      _connection = await blueyInstance.connect(widget.device);

      _stateSubscription = _connection!.stateChanges.listen((state) {
        setState(() {
          _connectionState = state;
        });

        if (state == bluey.ConnectionState.disconnected) {
          // Connection lost
          _showDisconnectedDialog();
        }
      });

      setState(() {
        _connectionState = _connection!.state;
      });

      // Auto-discover services
      await _discoverServices();
    } on BlueyException catch (e) {
      setState(() {
        _connectionState = bluey.ConnectionState.disconnected;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _connectionState = bluey.ConnectionState.disconnected;
        _error = e.toString();
      });
    }
  }

  Future<void> _discoverServices() async {
    if (_connection == null) return;

    setState(() {
      _isDiscovering = true;
    });

    try {
      final services = await _connection!.services;
      setState(() {
        _services = services;
        _isDiscovering = false;
      });
    } catch (e) {
      setState(() {
        _isDiscovering = false;
        _error = 'Failed to discover services: $e';
      });
    }
  }

  Future<void> _disconnect() async {
    await _connection?.disconnect();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showDisconnectedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('Disconnected'),
            content: const Text('The device has been disconnected.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Go back to scanner
                },
                child: const Text('OK'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  _connect(); // Reconnect
                },
                child: const Text('Reconnect'),
              ),
            ],
          ),
    );
  }

  void _openService(RemoteService service) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) =>
                ServiceScreen(connection: _connection!, service: service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name ?? 'Unknown Device'),
        actions: [
          _ConnectionStateChip(state: _connectionState),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(theme),
      floatingActionButton:
          _connectionState.isConnected
              ? FloatingActionButton.extended(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              )
              : null,
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_connectionState == bluey.ConnectionState.connecting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text('Connection Failed', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_connectionState.isConnected) {
      return const Center(child: Text('Not connected'));
    }

    return Column(
      children: [
        // Device info card
        _DeviceInfoCard(device: widget.device, connection: _connection!),

        // Services header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('Services', style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              if (_isDiscovering)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_services != null)
                Text(
                  '(${_services!.length})',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              const Spacer(),
              if (!_isDiscovering)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _discoverServices,
                  tooltip: 'Refresh services',
                ),
            ],
          ),
        ),

        // Services list
        Expanded(
          child:
              _services == null || _services!.isEmpty
                  ? Center(
                    child: Text(
                      _isDiscovering
                          ? 'Discovering services...'
                          : 'No services found',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _services!.length,
                    itemBuilder: (context, index) {
                      final service = _services![index];
                      return _ServiceCard(
                        service: service,
                        onTap: () => _openService(service),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

class _ConnectionStateChip extends StatelessWidget {
  final bluey.ConnectionState state;

  const _ConnectionStateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      bluey.ConnectionState.connected => (Colors.green, 'Connected'),
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

class _DeviceInfoCard extends StatelessWidget {
  final Device device;
  final Connection connection;

  const _DeviceInfoCard({required this.device, required this.connection});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  radius: 24,
                  child: Icon(
                    Icons.bluetooth_connected,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name ?? 'Unknown Device',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        device.id.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _InfoItem(
                  icon: Icons.signal_cellular_alt,
                  label: 'RSSI',
                  value: '${device.rssi} dBm',
                ),
                _InfoItem(
                  icon: Icons.data_usage,
                  label: 'MTU',
                  value: '${connection.mtu}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.labelSmall),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final RemoteService service;
  final VoidCallback onTap;

  const _ServiceCard({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serviceName = _getServiceName(service.uuid);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              service.isPrimary
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.secondaryContainer,
          child: Icon(
            Icons.widgets,
            color:
                service.isPrimary
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(
          serviceName ?? 'Unknown Service',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service.uuid.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            Text(
              '${service.characteristics.length} characteristics',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline),
        onTap: onTap,
        isThreeLine: true,
      ),
    );
  }

  String? _getServiceName(UUID uuid) {
    // Well-known services
    if (uuid == Services.genericAccess) return 'Generic Access';
    if (uuid == Services.genericAttribute) return 'Generic Attribute';
    if (uuid == Services.deviceInformation) return 'Device Information';
    if (uuid == Services.battery) return 'Battery';
    if (uuid == Services.heartRate) return 'Heart Rate';
    if (uuid == Services.healthThermometer) return 'Health Thermometer';
    if (uuid == Services.bloodPressure) return 'Blood Pressure';
    if (uuid == Services.runningSpeedAndCadence) {
      return 'Running Speed & Cadence';
    }
    if (uuid == Services.cyclingSpeedAndCadence) {
      return 'Cycling Speed & Cadence';
    }
    if (uuid == Services.cyclingPower) return 'Cycling Power';
    if (uuid == Services.locationAndNavigation) return 'Location & Navigation';
    if (uuid == Services.environmentalSensing) return 'Environmental Sensing';
    return null;
  }
}
