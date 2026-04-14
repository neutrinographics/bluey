import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
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

// ─── Design tokens ────────────────────────────────────────────────────────────

const _kBg = Color(0xFFF7F9FB);
const _kCard = Colors.white;
const _kAccent = Color(0xFF3F6187);
const _kDark = Color(0xFF2C3437);
const _kMid = Color(0xFF596064);
const _kLight = Color(0xFF747C80);
const _kTopBarTitle = Color(0xFF0F172A);
const _kIconBg = Color(0xFFAFD2FD);
const _kUuidBg = Color(0xFFF0F4F7);
const _kBadgeBg = Color(0xFFE3E9ED);

// Property badge colors
const _kReadBadgeBg = Color(0x4D69F6B8); // rgba(105,246,184,0.3)
const _kReadBadgeText = Color(0xFF005A3C);
const _kWriteBadgeBg = Color(0x4DD3E4FE); // rgba(211,228,254,0.3)
const _kWriteBadgeText = Color(0xFF435368);
const _kNotifyActiveBg = Color(0xFF69F6B8); // solid green when subscribed

// Action button colors
const _kActionActiveBg = Color(0x66AFD2FD); // rgba(175,210,253,0.4)
const _kActionActiveText = Color(0xFF23486C);
const _kActionInactiveBg = Color(0xFFEAEFF2);
const _kActionInactiveText = Color(0x80747C80); // rgba(116,124,128,0.5)


// ─── Screen ──────────────────────────────────────────────────────────────────

class ServiceScreen extends StatefulWidget {
  final Connection connection;
  final RemoteService service;

  /// Optional callback to reload the service's characteristics. When provided,
  /// the refresh button in the header becomes active and shows a snackbar on
  /// completion. Return the updated [RemoteService], or null to leave the
  /// existing service unchanged.
  final Future<RemoteService?> Function()? onRefresh;

  const ServiceScreen({
    super.key,
    required this.connection,
    required this.service,
    this.onRefresh,
  });

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  late RemoteService _service;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service;
  }

  Future<void> _refresh() async {
    if (_isRefreshing || widget.onRefresh == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isRefreshing = true);
    try {
      final updated = await widget.onRefresh!();
      if (!mounted) return;
      setState(() {
        if (updated != null) _service = updated;
        _isRefreshing = false;
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Characteristics refreshed'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRefreshing = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Refresh failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.top + 64 + 16,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: _ServiceIdentityCard(service: _service),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  child: _CharacteristicsHeader(
                    count: _service.characteristics.length,
                    isRefreshing: _isRefreshing,
                    onRefresh: widget.onRefresh != null ? _refresh : null,
                  ),
                ),
              ),
              if (_service.characteristics.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Center(
                      child: Text(
                        'No characteristics',
                        style: GoogleFonts.inter(fontSize: 14, color: _kLight),
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final isLast =
                          index == _service.characteristics.length - 1;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          0,
                          24,
                          isLast ? 128 : 16,
                        ),
                        child: _CharacteristicCard(
                          characteristic: _service.characteristics[index],
                        ),
                      );
                    },
                    childCount: _service.characteristics.length,
                  ),
                ),
            ],
          ),
          const _TopBar(),
        ],
      ),
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 64 + top,
          color: const Color(0xCCF8FAFC),
          padding: EdgeInsets.only(top: top, left: 8, right: 16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: _kDark, size: 24),
                onPressed: () => Navigator.of(context).pop(),
                padding: const EdgeInsets.all(8),
              ),
              const SizedBox(width: 5),
              Text(
                'Service Details',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _kTopBarTitle,
                  letterSpacing: -0.45,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Service Identity Card ────────────────────────────────────────────────────

class _ServiceIdentityCard extends StatelessWidget {
  final RemoteService service;
  const _ServiceIdentityCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final name = UuidNames.getServiceName(service.uuid) ?? 'Unknown Service';

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kIconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.hub_outlined, color: _kAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.isPrimary
                          ? 'PRIMARY SERVICE'
                          : 'SECONDARY SERVICE',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _kLight,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _kDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _kUuidBg,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UUID',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _kMid,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  service.uuid.toString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: _kDark,
                    height: 1.43,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Characteristics Header ───────────────────────────────────────────────────

class _CharacteristicsHeader extends StatelessWidget {
  final int count;
  final bool isRefreshing;
  final VoidCallback? onRefresh;

  const _CharacteristicsHeader({
    required this.count,
    required this.isRefreshing,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Characteristics',
          style: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _kDark,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: isRefreshing ? null : onRefresh,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: isRefreshing
                    ? const CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: _kLight,
                      )
                    : const Icon(Icons.refresh, color: _kLight, size: 16),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _kBadgeBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${count.toString().padLeft(2, '0')} FOUND',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _kLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Characteristic Card ──────────────────────────────────────────────────────

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

class _CharacteristicCardContent extends StatefulWidget {
  const _CharacteristicCardContent();

  @override
  State<_CharacteristicCardContent> createState() =>
      _CharacteristicCardContentState();
}

class _CharacteristicCardContentState
    extends State<_CharacteristicCardContent> {

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CharacteristicCubit, CharacteristicState>(
      listenWhen:
          (prev, curr) => prev.error != curr.error && curr.error != null,
      listener: (context, state) {
        if (state.error != null) {
          ErrorSnackbar.show(context, state.error!);
          context.read<CharacteristicCubit>().clearError();
        }
      },
      builder: (context, state) {
        final char = state.characteristic;
        final props = char.properties;
        final name = state.userDescription
            ?? UuidNames.getCharacteristicName(char.uuid)
            ?? 'Characteristic';
        final shortCode = char.uuid.shortString.toUpperCase();
        final hasReadWrite =
            props.canRead || props.canWrite || props.canWriteWithoutResponse;
        final hasNotify = props.canNotify || props.canIndicate;

        return Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.01),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: name + property badges
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _kDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          shortCode,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: _kMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (props.canRead)
                        _PropertyBadge('READ', _kReadBadgeBg, _kReadBadgeText),
                      if (props.canWrite || props.canWriteWithoutResponse)
                        _PropertyBadge(
                          'WRITE',
                          _kWriteBadgeBg,
                          _kWriteBadgeText,
                        ),
                      if (hasNotify)
                        _PropertyBadge(
                          'NOTIFY',
                          state.isSubscribed
                              ? _kNotifyActiveBg
                              : _kReadBadgeBg,
                          _kReadBadgeText,
                        ),
                    ],
                  ),
                ],
              ),

              // Value display (shown after a read)
              if (state.value != null) ...[
                const SizedBox(height: 12),
                _ValueBox(value: state.value!),
              ],

              // Read / Write action buttons
              if (hasReadWrite) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: 'READ',
                        icon: Icons.arrow_forward,
                        active: props.canRead,
                        isLoading: state.isReading,
                        onTap:
                            (props.canRead && !state.isReading)
                                ? context.read<CharacteristicCubit>().read
                                : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        label: 'WRITE',
                        icon: Icons.edit_outlined,
                        active:
                            props.canWrite || props.canWriteWithoutResponse,
                        isLoading: state.isWriting,
                        onTap:
                            ((props.canWrite || props.canWriteWithoutResponse) &&
                                    !state.isWriting)
                                ? () => _showWriteDialog(context)
                                : null,
                      ),
                    ),
                  ],
                ),
              ],

              // Subscribe / Unsubscribe button
              if (hasNotify) ...[
                const SizedBox(height: 12),
                _SubscribeButton(
                  isSubscribed: state.isSubscribed,
                  onTap:
                      context.read<CharacteristicCubit>().toggleNotifications,
                ),
              ],

              // Log section
              if (state.log.isNotEmpty) ...[
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: Colors.black.withValues(alpha: 0.04),
                ),
                const SizedBox(height: 16),
                _CharacteristicLogSection(
                  log: state.log,
                  onClear: context.read<CharacteristicCubit>().clearLog,
                ),
              ],

            ],
          ),
        );
      },
    );
  }

  Future<void> _showWriteDialog(BuildContext context) async {
    final cubit = context.read<CharacteristicCubit>();
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

// ─── Property Badge ───────────────────────────────────────────────────────────

class _PropertyBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color textColor;

  const _PropertyBadge(this.label, this.bg, this.textColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

// ─── Value Box ────────────────────────────────────────────────────────────────

class _ValueBox extends StatelessWidget {
  final Uint8List value;
  const _ValueBox({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _kUuidBg,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HEX',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _kLight,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ValueFormatters.formatHex(value),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: _kDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'ASCII: ${ValueFormatters.formatAscii(value)}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: _kMid,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final bool isLoading;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.active,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: active ? _kActionActiveBg : _kActionInactiveBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: _kActionActiveText,
                ),
              )
            else
              Icon(
                icon,
                size: 12,
                color: active ? _kActionActiveText : _kActionInactiveText,
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? _kActionActiveText : _kActionInactiveText,
                letterSpacing: 0.275,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Subscribe Button ─────────────────────────────────────────────────────────

class _SubscribeButton extends StatelessWidget {
  final bool isSubscribed;
  final VoidCallback onTap;

  const _SubscribeButton({required this.isSubscribed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 40,
        decoration: BoxDecoration(
          color: isSubscribed ? _kAccent : _kActionActiveBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSubscribed ? Icons.notifications_off : Icons.notifications,
              size: 12,
              color:
                  isSubscribed
                      ? const Color(0xFFF7F9FF)
                      : _kActionActiveText,
            ),
            const SizedBox(width: 6),
            Text(
              isSubscribed ? 'UNSUBSCRIBE' : 'SUBSCRIBE',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color:
                    isSubscribed
                        ? const Color(0xFFF7F9FF)
                        : _kActionActiveText,
                letterSpacing: 0.275,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Characteristic Log ───────────────────────────────────────────────────────

Color _logTagBg(String op) => switch (op) {
  'Write' => const Color(0xFFAFD2FD),
  'Read' => const Color(0xFFD3E4FE),
  'Notify' => _kReadBadgeBg,
  _ => const Color(0x0D2C3437),
};

Color _logTagText(String op) => switch (op) {
  'Write' => _kActionActiveText,
  'Read' => _kDark,
  'Notify' => _kReadBadgeText,
  _ => _kDark,
};

class _CharacteristicLogSection extends StatelessWidget {
  final List<LogEntry> log;
  final VoidCallback onClear;

  const _CharacteristicLogSection({
    required this.log,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'EVENT LOG',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _kLight,
                letterSpacing: 0.55,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: _kBadgeBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${log.length}',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _kLight,
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onClear,
              child: Text(
                'Clear',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _kAccent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: _kUuidBg,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < log.length; i++)
                  _CharacteristicLogEntry(
                    entry: log[i],
                    showTopBorder: i > 0,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CharacteristicLogEntry extends StatelessWidget {
  final LogEntry entry;
  final bool showTopBorder;

  const _CharacteristicLogEntry({
    required this.entry,
    required this.showTopBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: showTopBorder ? null : Colors.white,
        border: showTopBorder
            ? const Border(top: BorderSide(color: Color(0xFFDCE4E8)))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _formatTime(entry.timestamp),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: _kLight,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: _logTagBg(entry.operation),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.operation.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: _logTagText(entry.operation),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${ValueFormatters.formatHex(entry.value)}'
                  '  ·  '
                  '${entry.value.length} ${entry.value.length == 1 ? 'byte' : 'bytes'}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: _kDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

// ─── Write Value Dialog ───────────────────────────────────────────────────────

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
