import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/models/transfer_record.dart';
import '../../core/state/app_state.dart';
import '../../shared/utils/relative_time.dart';
import '../../shared/widgets/neu.dart';

/// Mobile file picker and transfer history.
class MobileTransfersPage extends StatefulWidget {
  const MobileTransfersPage({super.key});

  @override
  State<MobileTransfersPage> createState() => _MobileTransfersPageState();
}

class _MobileTransfersPageState extends State<MobileTransfersPage> {
  bool _sending = false;

  Future<void> _pickFiles(AppState state) async {
    if (state.connectedDevices.isEmpty) {
      _message('Hubungkan desktop terlebih dahulu.');
      return;
    }
    final files = await openFiles(
      acceptedTypeGroups: const [XTypeGroup(label: 'Files')],
    );
    if (files.isEmpty || !mounted) return;

    setState(() => _sending = true);
    try {
      for (final file in files) {
        final localPath = await _localPath(file);
        await state.offerFile(localPath);
      }
      if (mounted) _message('${files.length} file masuk antrean pengiriman.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<String> _localPath(XFile file) async {
    final original = File(file.path);
    if (await original.exists()) return original.path;

    // Some Android document providers return content:// URIs. Materialize
    // those into the app cache so the shared transfer engine can stream them.
    final cache = await getTemporaryDirectory();
    final safeName = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final target = File(
      '${cache.path}${Platform.pathSeparator}boon-send-${DateTime.now().microsecondsSinceEpoch}-$safeName',
    );
    final sink = target.openWrite();
    await sink.addStream(file.openRead());
    await sink.close();
    return target.path;
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final devices = state.connectedDevices;
    final transfers = state.transfers;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeuCard(
            contentPadding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.swap_horiz_rounded,
                      color: BoonColors.accentDeep,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'File Transfer',
                        style: BoonTypography.cardTitle,
                      ),
                    ),
                    NeuButton(
                      label: _sending ? 'Sending…' : 'Choose files',
                      onTap: _sending ? null : () => _pickFiles(state),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (devices.isEmpty)
                  const Text(
                    'Belum ada desktop terhubung.',
                    style: BoonTypography.subtitle,
                  )
                else ...[
                  const Text('Send to', style: BoonTypography.tiny),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final device in devices)
                        ChoiceChip(
                          label: Text(device.name),
                          selected: state.selectedDeviceId == device.id,
                          selectedColor: BoonColors.accent,
                          labelStyle: TextStyle(
                            color: state.selectedDeviceId == device.id
                                ? Colors.white
                                : BoonColors.navy,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          onSelected: (_) => state.selectDevice(device.id),
                        ),
                    ],
                  ),
                ],
                const Divider(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto-save photos/videos',
                            style: BoonTypography.subtitle,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Save received media to Gallery automatically',
                            style: BoonTypography.tiny,
                          ),
                        ],
                      ),
                    ),
                    NeuToggle(
                      value: state.autoSaveMediaToGallery,
                      trackWidth: 62,
                      trackHeight: 32,
                      onChanged: state.setAutoSaveMediaToGallery,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('Transfer history', style: BoonTypography.sectionTitle),
          ),
          const SizedBox(height: 6),
          if (transfers.isEmpty)
            const NeuCard(
              child: Text(
                'Belum ada file terkirim atau diterima.',
                style: BoonTypography.subtitle,
              ),
            )
          else
            for (final record in transfers.take(40))
              _TransferTile(
                record: record,
                onOpen: record.status == TransferStatus.completed
                    ? () async {
                        final opened = await state.openTransfer(record.id);
                        if (!opened) {
                          _message(
                            'Tidak ada aplikasi untuk membuka file ini.',
                          );
                        }
                      }
                    : null,
                onSave:
                    !record.outgoing &&
                        record.status == TransferStatus.completed &&
                        _isGalleryMedia(record.fileName) &&
                        !record.gallerySaved
                    ? () => state.saveTransferToGallery(record.id)
                    : null,
                onCancel: record.status == TransferStatus.active
                    ? () => state.cancelTransfer(record.id)
                    : null,
              ),
        ],
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({
    required this.record,
    this.onOpen,
    this.onSave,
    this.onCancel,
  });

  final TransferRecord record;
  final VoidCallback? onOpen;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final status = switch (record.status) {
      TransferStatus.completed => 'Completed',
      TransferStatus.active => '${(record.progress * 100).round()}%',
      TransferStatus.queued => 'Queued',
      TransferStatus.failed => 'Failed',
      TransferStatus.cancelled => 'Cancelled',
    };
    return NeuCard(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            record.outgoing
                ? Icons.north_east_rounded
                : Icons.south_west_rounded,
            color: record.status == TransferStatus.completed
                ? BoonColors.accentDeep
                : BoonColors.textFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: BoonColors.navy,
                  ),
                ),
                Text(
                  '${record.outgoing ? 'To' : 'From'} ${record.peerName} • ${formatRelative(record.time)} • $status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BoonTypography.tiny,
                ),
                if (record.status == TransferStatus.active) ...[
                  const SizedBox(height: 5),
                  LinearProgressIndicator(
                    value: record.progress.clamp(0.0, 1.0),
                    minHeight: 4,
                    color: BoonColors.accentDeep,
                    backgroundColor: BoonColors.panelBottom,
                  ),
                ],
              ],
            ),
          ),
          if (onSave != null)
            IconButton(
              tooltip: 'Save to Gallery',
              onPressed: onSave,
              icon: const Icon(
                Icons.photo_library_outlined,
                color: BoonColors.accentDeep,
              ),
            ),
          if (record.gallerySaved)
            const Icon(
              Icons.photo_library_rounded,
              size: 18,
              color: BoonColors.accentDeep,
            ),
          if (onOpen != null)
            IconButton(
              tooltip: 'Open',
              onPressed: onOpen,
              icon: const Icon(
                Icons.open_in_new_rounded,
                color: BoonColors.textDim,
              ),
            ),
          if (onCancel != null)
            IconButton(
              tooltip: 'Cancel',
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, color: BoonColors.textDim),
            ),
        ],
      ),
    );
  }
}

bool _isGalleryMedia(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.webm');
}
