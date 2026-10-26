import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/state/app_state.dart';
import '../../shared/widgets/neu.dart';

/// Clipboard page — follows ui/clipboard.png.
class ClipboardPage extends StatelessWidget {
  const ClipboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final device = state.primaryDevice;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 6, 30, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeuCard(
            margin: const EdgeInsets.all(6),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: BoonColors.panelBase,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: BoonShadows.pressed(blur: 8),
                  ),
                  child: const Icon(Icons.task_alt_rounded, size: 22, color: BoonColors.accentDeep),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AUTOSYNC', style: BoonTypography.cardTitle),
                    Text(
                      state.autoSync
                          ? (device != null ? 'Enabled • syncing with ${device.name}' : 'Enabled • no device connected')
                          : 'Disabled',
                      style: BoonTypography.subtitle,
                    ),
                  ],
                ),
                const Spacer(),
                NeuToggle(
                  value: state.autoSync,
                  onChanged: state.setAutoSync,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 250,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Expanded(
                child: NeuCard(
                  margin: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sync Direction', style: BoonTypography.cardTitle),
                      const SizedBox(height: 8),
                      NeuRadioRow<SyncDirection>(
                        label: 'Both Ways (Recommended)',
                        selected: state.syncDirection == SyncDirection.both,
                        onSelect: () {
                          state.setSyncDirection(SyncDirection.both);
                        },
                      ),
                      const SizedBox(height: 8),
                      NeuRadioRow<SyncDirection>(
                        label: 'Phone → Desktop',
                        selected: state.syncDirection == SyncDirection.phoneToDesktop,
                        onSelect: () => state.setSyncDirection(SyncDirection.phoneToDesktop),
                      ),
                      const SizedBox(height: 8),
                      NeuRadioRow<SyncDirection>(
                        label: 'Desktop → Phone',
                        selected: state.syncDirection == SyncDirection.desktopToPhone,
                        onSelect: () => state.setSyncDirection(SyncDirection.desktopToPhone),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: NeuCard(
                  margin: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sensitive Content', style: BoonTypography.cardTitle),
                      const SizedBox(height: 12),
                      NeuRadioRow<SensitivePolicy>(
                        label: 'Allow It',
                        selected: state.sensitivePolicy == SensitivePolicy.allow,
                        onSelect: () => state.setSensitivePolicy(SensitivePolicy.allow),
                      ),
                      const SizedBox(height: 10),
                      NeuRadioRow<SensitivePolicy>(
                        label: 'Discard Immediately',
                        selected: state.sensitivePolicy == SensitivePolicy.discard,
                        onSelect: () => state.setSensitivePolicy(SensitivePolicy.discard),
                      ),
                      const Spacer(),
                      Text(
                        state.sensitivePolicy == SensitivePolicy.discard
                            ? 'Synced content is never kept in activity history.'
                            : 'Content appears in recent activity.',
                        style: BoonTypography.tiny,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: NeuCard(
                  margin: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Last Sync', style: BoonTypography.cardTitle),
                      const SizedBox(height: 6),
                      const Text('Today', style: BoonTypography.subtitle),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            state.lastSync == null ? '—' : clockDigits(state.lastSync!),
                            style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF9FB6CA),
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              state.lastSync == null ? '' : ampm(state.lastSync!),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF9FB6CA),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String clockDigits(DateTime t) {
    final minute = t.minute.toString().padLeft(2, '0');
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h.$minute';
  }

  String ampm(DateTime t) => t.hour < 12 ? 'AM' : 'PM';
}
