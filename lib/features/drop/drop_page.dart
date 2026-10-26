import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/activity_event.dart';
import '../../core/models/transfer_record.dart';
import '../../core/state/app_state.dart';
import '../../app/theme.dart';
import '../../shared/utils/relative_time.dart';
import '../../shared/widgets/components.dart';
import '../../shared/widgets/neu.dart';

/// File Transfer page — follows ui/file_transfer.png (Send / History).
class DropPage extends StatefulWidget {
  const DropPage({super.key});

  @override
  State<DropPage> createState() => _DropPageState();
}

class _DropPageState extends State<DropPage> {
  bool sendTab = true;

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 4, 56, 20),
      child: Column(
        children: [
          _SegmentedControl(
            selected: sendTab,
            onSend: () => setState(() => sendTab = true),
            onHistory: () => setState(() => sendTab = false),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: sendTab
                ? const _SendView()
                : _HistoryView(
                    onCancel: (id) =>
                        context.read<AppState>().cancelTransfer(id),
                    onOpen: (id) => context.read<AppState>().openTransfer(id),
                  ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Segmented control (Send | History)
// =====================================================================

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.selected,
    required this.onSend,
    required this.onHistory,
  });

  final bool selected;
  final VoidCallback onSend;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: BoonColors.panelBase,
        boxShadow: BoonShadows.raised(
          blur: 14,
          darkOffset: const Offset(6, 6),
          lightOffset: const Offset(-6, -6),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              label: 'Send',
              leading: Icons.task_alt_rounded,
              selected: selected,
              onTap: onSend,
            ),
          ),
          Expanded(
            child: _Segment(
              label: 'History',
              trailing: Icons.task_alt_rounded,
              selected: !selected,
              onTap: onHistory,
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? leading;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFFA8C6DE), BoonColors.accentDeep],
                  )
                : null,
            color: selected ? null : BoonColors.panelBase,
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.35)
                          : BoonColors.panelBase,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      leading,
                      size: 16,
                      color: selected ? Colors.white : BoonColors.accentDeep,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : BoonColors.navy,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.35)
                          : BoonColors.panelBase,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: selected
                          ? null
                          : [
                              BoxShadow(
                                color: BoonColors.shadowDark,
                                offset: const Offset(2, 2),
                                blurRadius: 5,
                              ),
                            ],
                    ),
                    child: Icon(
                      trailing,
                      size: 16,
                      color: selected ? Colors.white : BoonColors.accentDeep,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Send view: destination + drag & drop zone
// =====================================================================

class _SendView extends StatefulWidget {
  const _SendView();

  @override
  State<_SendView> createState() => _SendViewState();
}

class _SendViewState extends State<_SendView> {
  bool _dragging = false;

  Future<void> _offer(String path) async {
    final state = context.read<AppState>();
    await state.offerFile(path);
  }

  Future<void> _pickFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const [XTypeGroup(label: 'files')],
    );
    for (final f in files) {
      await _offer(f.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final devices = state.connectedDevices;
    final selected = state.selectedDeviceId;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Send to:', style: BoonTypography.sectionTitle),
            const SizedBox(width: 10),
            if (devices.isEmpty)
              const Text('No connected device', style: BoonTypography.subtitle)
            else
              for (final d in devices)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(d.name),
                    selected: selected == d.id,
                    selectedColor: BoonColors.accent,
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => state.selectDevice(d.id),
                  ),
                ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: DropTarget(
            onDragEntered: (_) {
              setState(() => _dragging = true);
            },
            onDragExited: (_) {
              setState(() => _dragging = false);
            },
            onDragDone: (details) async {
              setState(() => _dragging = false);
              final targets = state.connectedDevices;
              if (targets.isEmpty) {
                state.addActivity(
                  ActivityKind.info,
                  'No destination',
                  'Pair a device before sending files.',
                );
                return;
              }
              for (final file in details.files) {
                await _offer(file.path);
              }
            },
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: _dragging ? BoonColors.panelTop : BoonColors.panelBase,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _dragging ? BoonColors.accent : Colors.transparent,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: BoonColors.shadowDark,
                    offset: const Offset(6, 6),
                    blurRadius: 16,
                  ),
                  BoxShadow(
                    color: Colors.white,
                    offset: const Offset(-6, -6),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AppIconCircle(
                    icon: Icons.cloud_upload_rounded,
                    size: 64,
                    iconSize: 30,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _dragging ? 'DROP TO SEND' : 'DRAG & DROP FILES',
                    style: BoonTypography.pageTitle(16),
                  ),
                  const SizedBox(height: 8),
                  const Text('OR', style: BoonTypography.tiny),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.transparent,
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [BoonColors.accentSoft, BoonColors.accent],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: InkWell(
                        onTap: devices.isEmpty ? null : _pickFiles,
                        borderRadius: BorderRadius.circular(10),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 10,
                          ),
                          child: Text(
                            'Select Files',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Text(
                      devices.isEmpty
                          ? 'Pair and connect a device in Settings first.'
                          : 'Files are encrypted in transit and SHA-256 verified on arrival.',
                      style: BoonTypography.tiny,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// History view
// =====================================================================

class _HistoryView extends StatelessWidget {
  const _HistoryView({required this.onCancel, required this.onOpen});

  final void Function(String) onCancel;
  final Future<void> Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final transfers = state.transfers.reversed.toList();
    if (transfers.isEmpty) {
      return const Center(
        child: Text('No transfers yet.', style: BoonTypography.subtitle),
      );
    }
    return ListView.builder(
      itemCount: transfers.length,
      itemBuilder: (context, i) {
        final t = transfers[i];
        final statusColor = switch (t.status) {
          TransferStatus.completed => BoonColors.accentDeep,
          TransferStatus.failed ||
          TransferStatus.cancelled => Colors.redAccent.withValues(alpha: 0.8),
          _ => BoonColors.accent,
        };
        final sizeLabel = t.sizeBytes >= (1 << 20)
            ? '${(t.sizeBytes / (1 << 20)).toStringAsFixed(1)} MB'
            : '${(t.sizeBytes / 1024).round()} KB';
        return NeuCard(
          margin: const EdgeInsets.all(6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: BoonColors.panelTop,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  t.outgoing
                      ? Icons.north_east_rounded
                      : Icons.south_west_rounded,
                  size: 18,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.fileName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: BoonColors.navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.outgoing ? 'To' : 'From'} ${t.peerName} • $sizeLabel • ${formatRelative(t.time)}',
                      style: BoonTypography.tiny,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (t.status == TransferStatus.active) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: t.progress.clamp(0.0, 1.0),
                          minHeight: 4,
                          color: BoonColors.accentDeep,
                          backgroundColor: BoonColors.panelBottom,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              switch (t.status) {
                TransferStatus.queued => const Text(
                  'Queued',
                  style: BoonTypography.tiny,
                ),
                TransferStatus.active => TextButton(
                  onPressed: () => onCancel(t.id),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 12, color: BoonColors.textDim),
                  ),
                ),
                TransferStatus.completed => const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: BoonColors.accentDeep,
                ),
                TransferStatus.failed => const Text(
                  'Failed',
                  style: BoonTypography.tiny,
                ),
                TransferStatus.cancelled => const Text(
                  'Cancelled',
                  style: BoonTypography.tiny,
                ),
              },
              if (t.status == TransferStatus.completed &&
                  (t.path != null || t.file?.path != null))
                IconButton(
                  tooltip: 'Open file',
                  onPressed: () => onOpen(t.id),
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    size: 18,
                    color: BoonColors.textDim,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
