import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:bluey/bluey.dart';

import '../../main.dart';

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  Server? _server;
  bool _isAdvertising = false;
  final List<Central> _connectedCentrals = [];
  StreamSubscription<Central>? _connectionSubscription;
  final List<_LogEntry> _log = [];
  int _notificationCount = 0;

  // Demo service UUIDs
  static final _demoServiceUuid = UUID('12345678-1234-1234-1234-123456789abc');
  static final _demoCharUuid = UUID('12345678-1234-1234-1234-123456789abd');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initServer();
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _server?.dispose();
    super.dispose();
  }

  void _initServer() {
    final bluey = BlueyProvider.of(context);
    _server = bluey.server();

    if (_server == null) {
      _addLog('Server', 'Peripheral role not supported on this platform');
      return;
    }

    // Add demo service
    _server!.addService(
      LocalService(
        uuid: _demoServiceUuid,
        isPrimary: true,
        characteristics: [
          LocalCharacteristic(
            uuid: _demoCharUuid,
            properties: const CharacteristicProperties(
              canRead: true,
              canWrite: true,
              canNotify: true,
            ),
            permissions: const [GattPermission.read, GattPermission.write],
          ),
        ],
      ),
    );

    // Listen for central connections
    _connectionSubscription = _server!.connections.listen((central) {
      setState(() {
        _connectedCentrals.add(central);
      });
      _addLog('Connection', 'Central connected: ${central.id}');
    });

    _addLog('Server', 'Initialized with demo service');
  }

  Future<void> _startAdvertising() async {
    if (_server == null) return;

    try {
      await _server!.startAdvertising(
        name: 'Bluey Demo',
        services: [_demoServiceUuid],
      );
      setState(() => _isAdvertising = true);
      _addLog('Advertising', 'Started advertising');
    } catch (e) {
      _showError('Failed to start advertising: $e');
    }
  }

  Future<void> _stopAdvertising() async {
    if (_server == null) return;

    try {
      await _server!.stopAdvertising();
      setState(() => _isAdvertising = false);
      _addLog('Advertising', 'Stopped advertising');
    } catch (e) {
      _showError('Failed to stop advertising: $e');
    }
  }

  Future<void> _sendNotification() async {
    if (_server == null || _connectedCentrals.isEmpty) {
      _showError('No centrals connected');
      return;
    }

    try {
      _notificationCount++;
      final data = Uint8List.fromList([_notificationCount & 0xFF]);
      await _server!.notify(_demoCharUuid, data: data);
      _addLog(
        'Notify',
        'Sent notification #$_notificationCount to all centrals',
      );
    } catch (e) {
      _showError('Failed to send notification: $e');
    }
  }

  Future<void> _disconnectCentral(Central central) async {
    try {
      await central.disconnect();
      setState(() {
        _connectedCentrals.remove(central);
      });
      _addLog('Connection', 'Disconnected central: ${central.id}');
    } catch (e) {
      _showError('Failed to disconnect: $e');
    }
  }

  void _addLog(String tag, String message) {
    setState(() {
      _log.insert(0, _LogEntry(tag, message));
      if (_log.length > 100) {
        _log.removeLast();
      }
    });
  }

  void _showError(String message) {
    // Log to console for debugging
    // ignore: avoid_print
    print('[ServerScreen] Error: $message');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Server')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Peripheral role not supported',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'This platform does not support BLE advertising',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server'),
        actions: [
          _AdvertisingChip(isAdvertising: _isAdvertising),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Service info card
          Card(
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
                        child: Icon(
                          Icons.cell_tower,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bluey Demo Service',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _demoServiceUuid.toString(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _isAdvertising
                                ? _stopAdvertising
                                : _startAdvertising,
                        icon: Icon(
                          _isAdvertising ? Icons.stop : Icons.play_arrow,
                        ),
                        label: Text(
                          _isAdvertising
                              ? 'Stop Advertising'
                              : 'Start Advertising',
                        ),
                        style:
                            _isAdvertising
                                ? FilledButton.styleFrom(
                                  backgroundColor: theme.colorScheme.error,
                                  foregroundColor: theme.colorScheme.onError,
                                )
                                : null,
                      ),
                      FilledButton.tonalIcon(
                        onPressed:
                            _connectedCentrals.isNotEmpty
                                ? _sendNotification
                                : null,
                        icon: const Icon(Icons.send),
                        label: const Text('Send Notification'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Connected centrals
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Connected Centrals', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    '${_connectedCentrals.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_connectedCentrals.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No centrals connected',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            )
          else
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: _connectedCentrals.length,
                itemBuilder: (context, index) {
                  final central = _connectedCentrals[index];
                  return _CentralChip(
                    central: central,
                    onDisconnect: () => _disconnectCentral(central),
                  );
                },
              ),
            ),

          const Divider(),

          // Log
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Log', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _log.clear()),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),

          Expanded(
            child:
                _log.isEmpty
                    ? Center(
                      child: Text(
                        'No log entries',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _log.length,
                      itemBuilder: (context, index) {
                        final entry = _log[index];
                        return _LogTile(entry: entry);
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _AdvertisingChip extends StatelessWidget {
  final bool isAdvertising;

  const _AdvertisingChip({required this.isAdvertising});

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

class _CentralChip extends StatelessWidget {
  final Central central;
  final VoidCallback onDisconnect;

  const _CentralChip({required this.central, required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(right: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phone_android,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  central.id.toString().substring(0, 8),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                Text('MTU: ${central.mtu}', style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDisconnect,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Disconnect',
            ),
          ],
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final _LogEntry entry;

  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final color = switch (entry.tag) {
      'Advertising' => Colors.blue,
      'Connection' => Colors.green,
      'Notify' => Colors.purple,
      'Error' => Colors.red,
      _ => theme.colorScheme.outline,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatTime(entry.timestamp),
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              entry.tag,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(entry.message, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}

class _LogEntry {
  final String tag;
  final String message;
  final DateTime timestamp;

  _LogEntry(this.tag, this.message) : timestamp = DateTime.now();
}
