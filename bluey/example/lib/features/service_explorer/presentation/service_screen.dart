import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../../../shared/di/service_locator.dart';
import '../../../shared/domain/uuid_names.dart';
import '../../../shared/domain/value_formatters.dart';
import '../../../shared/presentation/error_snackbar.dart';
import '../application/read_characteristic.dart';
import '../application/write_characteristic.dart';
import '../application/subscribe_to_characteristic.dart';
import '../application/read_descriptor.dart';
import 'service_cubit.dart';
import 'service_state.dart';

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
        title: Text(UuidNames.getServiceName(service.uuid) ?? 'Service'),
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
                  Text('UUID', style: theme.textTheme.labelSmall),
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
                        label: Text(
                          service.isPrimary ? 'Primary' : 'Secondary',
                        ),
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
            child:
                service.characteristics.isEmpty
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
}

class _CharacteristicCard extends StatelessWidget {
  final RemoteCharacteristic characteristic;

  const _CharacteristicCard({required this.characteristic});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (context) => CharacteristicCubit(
            characteristic: characteristic,
            readCharacteristic: getIt<ReadCharacteristic>(),
            writeCharacteristic: getIt<WriteCharacteristic>(),
            subscribeToCharacteristic: getIt<SubscribeToCharacteristic>(),
            readDescriptor: getIt<ReadDescriptor>(),
          ),
      child: const _CharacteristicCardContent(),
    );
  }
}

class _CharacteristicCardContent extends StatelessWidget {
  const _CharacteristicCardContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocConsumer<CharacteristicCubit, CharacteristicState>(
      listenWhen:
          (previous, current) =>
              previous.error != current.error && current.error != null,
      listener: (context, state) {
        if (state.error != null) {
          ErrorSnackbar.show(context, state.error!);
          context.read<CharacteristicCubit>().clearError();
        }
      },
      builder: (context, state) {
        final char = state.characteristic;
        final props = char.properties;
        final charName = UuidNames.getCharacteristicName(char.uuid);

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
                    _PropertiesWrap(properties: props),
                    const SizedBox(height: 16),

                    // Action buttons
                    _ActionButtons(state: state),

                    // Current value
                    if (state.value != null) ...[
                      const SizedBox(height: 16),
                      _ValueDisplay(value: state.value!),
                    ],

                    // Log
                    if (state.log.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _LogDisplay(log: state.log),
                    ],

                    // Descriptors
                    if (char.descriptors.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _DescriptorsList(descriptors: char.descriptors),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PropertiesWrap extends StatelessWidget {
  final CharacteristicProperties properties;

  const _PropertiesWrap({required this.properties});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (properties.canRead) _PropertyChip('Read', Icons.visibility),
        if (properties.canWrite) _PropertyChip('Write', Icons.edit),
        if (properties.canWriteWithoutResponse)
          _PropertyChip('Write No Response', Icons.edit_off),
        if (properties.canNotify) _PropertyChip('Notify', Icons.notifications),
        if (properties.canIndicate)
          _PropertyChip('Indicate', Icons.notifications_active),
      ],
    );
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

class _ActionButtons extends StatelessWidget {
  final CharacteristicState state;

  const _ActionButtons({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<CharacteristicCubit>();
    final props = state.characteristic.properties;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (props.canRead)
          FilledButton.icon(
            onPressed: state.isReading ? null : cubit.read,
            icon:
                state.isReading
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.download, size: 18),
            label: const Text('Read'),
          ),
        if (props.canWrite || props.canWriteWithoutResponse)
          FilledButton.tonalIcon(
            onPressed:
                state.isWriting ? null : () => _showWriteDialog(context, cubit),
            icon:
                state.isWriting
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.upload, size: 18),
            label: const Text('Write'),
          ),
        if (props.canNotify || props.canIndicate)
          FilledButton.tonalIcon(
            onPressed: cubit.toggleNotifications,
            icon: Icon(
              state.isSubscribed
                  ? Icons.notifications_off
                  : Icons.notifications,
              size: 18,
            ),
            label: Text(state.isSubscribed ? 'Unsubscribe' : 'Subscribe'),
            style:
                state.isSubscribed
                    ? FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.errorContainer,
                      foregroundColor: theme.colorScheme.onErrorContainer,
                    )
                    : null,
          ),
      ],
    );
  }

  Future<void> _showWriteDialog(
    BuildContext context,
    CharacteristicCubit cubit,
  ) async {
    final result = await showDialog<Uint8List>(
      context: context,
      builder: (context) => const _WriteValueDialog(),
    );

    if (result != null && result.isNotEmpty) {
      await cubit.write(result);
      if (context.mounted) {
        ErrorSnackbar.showSuccess(context, 'Write successful');
      }
    }
  }
}

class _ValueDisplay extends StatelessWidget {
  final Uint8List value;

  const _ValueDisplay({required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                'Hex: ${ValueFormatters.formatHex(value)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                'ASCII: ${ValueFormatters.formatAscii(value)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
              Text('Bytes: ${value.length}', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _LogDisplay extends StatelessWidget {
  final List<LogEntry> log;

  const _LogDisplay({required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<CharacteristicCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Log:', style: theme.textTheme.labelMedium),
            const Spacer(),
            TextButton(onPressed: cubit.clearLog, child: const Text('Clear')),
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
            itemCount: log.length,
            itemBuilder: (context, index) {
              final entry = log[index];
              return Text(
                '${entry.operation}: ${ValueFormatters.formatHex(entry.value)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DescriptorsList extends StatelessWidget {
  final List<RemoteDescriptor> descriptors;

  const _DescriptorsList({required this.descriptors});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Descriptors (${descriptors.length})',
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        ...descriptors.map((desc) => _DescriptorTile(descriptor: desc)),
      ],
    );
  }
}

class _DescriptorTile extends StatelessWidget {
  final RemoteDescriptor descriptor;

  const _DescriptorTile({required this.descriptor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<CharacteristicCubit>();
    final key = descriptor.uuid.toString();

    return BlocSelector<
      CharacteristicCubit,
      CharacteristicState,
      ({Uint8List? value, bool isReading, bool hasError})
    >(
      selector:
          (state) => (
            value: state.descriptorValues[key],
            isReading: state.readingDescriptors.contains(key),
            hasError: state.failedDescriptors.contains(key),
          ),
      builder: (context, desc) {
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.description,
            size: 20,
            color:
                desc.hasError
                    ? theme.colorScheme.error
                    : theme.colorScheme.outline,
          ),
          title: Text(
            key,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          subtitle:
              desc.hasError
                  ? Text(
                    'Read failed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  )
                  : desc.value != null
                  ? Text(
                    ValueFormatters.formatHex(desc.value!),
                    style: theme.textTheme.bodySmall,
                  )
                  : null,
          trailing: IconButton(
            icon:
                desc.isReading
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Icon(
                      Icons.download,
                      size: 18,
                      color: desc.hasError ? theme.colorScheme.error : null,
                    ),
            onPressed:
                desc.isReading ? null : () => cubit.readDescriptor(descriptor),
            tooltip: 'Read',
          ),
        );
      },
    );
  }
}

class _WriteValueDialog extends StatefulWidget {
  const _WriteValueDialog();

  @override
  State<_WriteValueDialog> createState() => _WriteValueDialogState();
}

class _WriteValueDialogState extends State<_WriteValueDialog> {
  final _controller = TextEditingController();
  bool _isHexMode = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Uint8List? _parseInput() {
    final text = _controller.text;
    if (text.isEmpty) return null;

    try {
      if (_isHexMode) {
        return ValueFormatters.parseHex(text);
      } else {
        return Uint8List.fromList(text.codeUnits);
      }
    } catch (e) {
      return null;
    }
  }

  void _validate() {
    final text = _controller.text;
    if (text.isEmpty) {
      setState(() => _error = null);
      return;
    }

    if (_isHexMode) {
      setState(() => _error = ValueFormatters.validateHex(text));
    } else {
      setState(() => _error = null);
    }
  }

  void _submit() {
    final bytes = _parseInput();
    if (bytes != null && bytes.isNotEmpty) {
      Navigator.pop(context, bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Write Value'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Hex')),
                ButtonSegment(value: false, label: Text('String')),
              ],
              selected: {_isHexMode},
              onSelectionChanged: (selected) {
                setState(() {
                  _isHexMode = selected.first;
                  _error = null;
                });
                _validate();
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: _isHexMode ? 'Hex bytes' : 'Text string',
                hintText: _isHexMode ? '01 02 03' : 'Hello World',
                errorText: _error,
              ),
              autofocus: true,
              onChanged: (_) => _validate(),
              onSubmitted: (_) => _submit(),
            ),
            if (_controller.text.isNotEmpty && _error == null) ...[
              const SizedBox(height: 12),
              Text('Preview:', style: theme.textTheme.labelSmall),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Builder(
                  builder: (context) {
                    final bytes = _parseInput();
                    if (bytes == null) return const SizedBox.shrink();
                    return Text(
                      '${bytes.length} bytes: ${ValueFormatters.formatHex(bytes)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _error == null && _controller.text.isNotEmpty ? _submit : null,
          child: const Text('Write'),
        ),
      ],
    );
  }
}
