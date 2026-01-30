import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:bluey/bluey.dart';

class ServiceScreen extends StatelessWidget {
  final Connection connection;
  final RemoteService service;

  const ServiceScreen({
    super.key,
    required this.connection,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_getServiceName(service.uuid) ?? 'Service'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service info
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UUID',
                    style: theme.textTheme.labelSmall,
                  ),
                  SelectableText(
                    service.uuid.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Chip(
                        label:
                            Text(service.isPrimary ? 'Primary' : 'Secondary'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Characteristics header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Characteristics (${service.characteristics.length})',
              style: theme.textTheme.titleMedium,
            ),
          ),

          // Characteristics list
          Expanded(
            child: service.characteristics.isEmpty
                ? Center(
                    child: Text(
                      'No characteristics',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: service.characteristics.length,
                    itemBuilder: (context, index) {
                      final characteristic = service.characteristics[index];
                      return _CharacteristicCard(
                        characteristic: characteristic,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String? _getServiceName(UUID uuid) {
    if (uuid == Services.genericAccess) return 'Generic Access';
    if (uuid == Services.genericAttribute) return 'Generic Attribute';
    if (uuid == Services.deviceInformation) return 'Device Information';
    if (uuid == Services.battery) return 'Battery';
    if (uuid == Services.heartRate) return 'Heart Rate';
    return null;
  }
}

class _CharacteristicCard extends StatefulWidget {
  final RemoteCharacteristic characteristic;

  const _CharacteristicCard({required this.characteristic});

  @override
  State<_CharacteristicCard> createState() => _CharacteristicCardState();
}

class _CharacteristicCardState extends State<_CharacteristicCard> {
  Uint8List? _value;
  bool _isReading = false;
  bool _isWriting = false;
  bool _isSubscribed = false;
  StreamSubscription<Uint8List>? _notificationSubscription;
  final List<_LogEntry> _log = [];

  RemoteCharacteristic get char => widget.characteristic;
  CharacteristicProperties get props => char.properties;

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() => _isReading = true);
    try {
      final value = await char.read();
      setState(() {
        _value = value;
        _log.insert(0, _LogEntry('Read', value));
      });
    } catch (e) {
      _showError('Read failed: $e');
    } finally {
      setState(() => _isReading = false);
    }
  }

  Future<void> _write() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Write Value'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Hex bytes (e.g., 01 02 03)',
            hintText: '00 FF',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Write'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    setState(() => _isWriting = true);
    try {
      final bytes = _parseHexString(result);
      await char.write(bytes, withResponse: props.canWrite);
      setState(() {
        _log.insert(0, _LogEntry('Write', bytes));
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Write successful')),
        );
      }
    } catch (e) {
      _showError('Write failed: $e');
    } finally {
      setState(() => _isWriting = false);
    }
  }

  void _toggleNotifications() {
    if (_isSubscribed) {
      _notificationSubscription?.cancel();
      _notificationSubscription = null;
      setState(() => _isSubscribed = false);
    } else {
      _notificationSubscription = char.notifications.listen(
        (value) {
          setState(() {
            _value = value;
            _log.insert(0, _LogEntry('Notify', value));
          });
        },
        onError: (e) {
          _showError('Notification error: $e');
          setState(() => _isSubscribed = false);
        },
      );
      setState(() => _isSubscribed = true);
    }
  }

  Uint8List _parseHexString(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.length % 2 != 0) {
      throw const FormatException('Invalid hex string');
    }
    final bytes = <int>[];
    for (var i = 0; i < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  void _showError(String message) {
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
    final charName = _getCharacteristicName(char.uuid);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(
            Icons.tune,
            color: theme.colorScheme.onSecondaryContainer,
            size: 20,
          ),
        ),
        title: Text(
          charName ?? 'Characteristic',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          char.uuid.toString(),
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            fontSize: 10,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Properties
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (props.canRead) _PropertyChip('Read', Icons.visibility),
                    if (props.canWrite) _PropertyChip('Write', Icons.edit),
                    if (props.canWriteWithoutResponse)
                      _PropertyChip('Write No Response', Icons.edit_off),
                    if (props.canNotify)
                      _PropertyChip('Notify', Icons.notifications),
                    if (props.canIndicate)
                      _PropertyChip('Indicate', Icons.notifications_active),
                  ],
                ),

                const SizedBox(height: 16),

                // Action buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (props.canRead)
                      FilledButton.icon(
                        onPressed: _isReading ? null : _read,
                        icon: _isReading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download, size: 18),
                        label: const Text('Read'),
                      ),
                    if (props.canWrite || props.canWriteWithoutResponse)
                      FilledButton.tonalIcon(
                        onPressed: _isWriting ? null : _write,
                        icon: _isWriting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload, size: 18),
                        label: const Text('Write'),
                      ),
                    if (props.canNotify || props.canIndicate)
                      FilledButton.tonalIcon(
                        onPressed: _toggleNotifications,
                        icon: Icon(
                          _isSubscribed
                              ? Icons.notifications_off
                              : Icons.notifications,
                          size: 18,
                        ),
                        label:
                            Text(_isSubscribed ? 'Unsubscribe' : 'Subscribe'),
                        style: _isSubscribed
                            ? FilledButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.errorContainer,
                                foregroundColor:
                                    theme.colorScheme.onErrorContainer,
                              )
                            : null,
                      ),
                  ],
                ),

                // Current value
                if (_value != null) ...[
                  const SizedBox(height: 16),
                  Text('Value:', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hex: ${_formatHex(_value!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          'ASCII: ${_formatAscii(_value!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          'Bytes: ${_value!.length}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],

                // Log
                if (_log.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Log:', style: theme.textTheme.labelMedium),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _log.clear()),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _log.length,
                      itemBuilder: (context, index) {
                        final entry = _log[index];
                        return Text(
                          '${entry.operation}: ${_formatHex(entry.value)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ),
                ],

                // Descriptors
                if (char.descriptors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Descriptors (${char.descriptors.length})',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  ...char.descriptors
                      .map((desc) => _DescriptorTile(descriptor: desc)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatHex(Uint8List bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  String _formatAscii(Uint8List bytes) {
    return String.fromCharCodes(
      bytes.map(
          (b) => b >= 32 && b < 127 ? b : 46), // Replace non-printable with '.'
    );
  }

  String? _getCharacteristicName(UUID uuid) {
    if (uuid == Characteristics.deviceName) return 'Device Name';
    if (uuid == Characteristics.appearance) return 'Appearance';
    if (uuid == Characteristics.batteryLevel) return 'Battery Level';
    if (uuid == Characteristics.heartRateMeasurement) {
      return 'Heart Rate Measurement';
    }
    if (uuid == Characteristics.bodySensorLocation) {
      return 'Body Sensor Location';
    }
    if (uuid == Characteristics.manufacturerName) return 'Manufacturer Name';
    if (uuid == Characteristics.modelNumber) return 'Model Number';
    if (uuid == Characteristics.serialNumber) return 'Serial Number';
    if (uuid == Characteristics.firmwareRevision) return 'Firmware Revision';
    if (uuid == Characteristics.hardwareRevision) return 'Hardware Revision';
    if (uuid == Characteristics.softwareRevision) return 'Software Revision';
    return null;
  }
}

class _PropertyChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _PropertyChip(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

class _DescriptorTile extends StatefulWidget {
  final RemoteDescriptor descriptor;

  const _DescriptorTile({required this.descriptor});

  @override
  State<_DescriptorTile> createState() => _DescriptorTileState();
}

class _DescriptorTileState extends State<_DescriptorTile> {
  Uint8List? _value;
  bool _isReading = false;

  Future<void> _read() async {
    setState(() => _isReading = true);
    try {
      final value = await widget.descriptor.read();
      setState(() => _value = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Read failed: $e')),
        );
      }
    } finally {
      setState(() => _isReading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading:
          Icon(Icons.description, size: 20, color: theme.colorScheme.outline),
      title: Text(
        widget.descriptor.uuid.toString(),
        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
      ),
      subtitle: _value != null
          ? Text(
              _value!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '),
              style: theme.textTheme.bodySmall,
            )
          : null,
      trailing: IconButton(
        icon: _isReading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download, size: 18),
        onPressed: _isReading ? null : _read,
        tooltip: 'Read',
      ),
    );
  }
}

class _LogEntry {
  final String operation;
  final Uint8List value;
  final DateTime timestamp;

  _LogEntry(this.operation, this.value) : timestamp = DateTime.now();
}
