import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../app/window.dart';
import '../../core/state/app_state.dart';
import '../../services/companion/companion_bridge.dart';
import '../../shared/widgets/neu.dart';

/// Settings + Boon Link: identity, discovery, pairing, trusted devices
/// and demo mode. Pairing is initiated by another device too — incoming
/// requests appear automatically as dialogs.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final addressCtl = TextEditingController(text: '192.168.1.');
  final portCtl = TextEditingController(text: '45022');

  bool get alwaysOnTop => BoonWindow.alwaysOnTop;

  void _setAlwaysOnTop(bool on) {
    setState(() => unawaited(BoonWindow.setAlwaysOnTop(on)));
  }

  @override
  void dispose() {
    addressCtl.dispose();
    portCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trusted = state.link?.trustedDevices.toList() ?? const [];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 6, 30, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionCard(
            title: 'This Device',
            child: Row(
              children: [
                const Icon(
                  Icons.devices_rounded,
                  size: 34,
                  color: BoonColors.accentDeep,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.identity?.name ?? 'Boon Desktop',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        state.identity == null
                            ? 'Booting…'
                            : 'ID ${state.identity!.id} • type ${state.identity!.type}',
                        style: BoonTypography.tiny,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _SectionCard(
            title: 'Demo Mode',
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pixel 8 sample data${state.demoMode ? ' (active)' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: BoonColors.navy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Shows a fake companion device so the UI can be evaluated '
                        'before Android integration. Demo data is clearly labeled '
                        'and never mixed with real connections.',
                        style: BoonTypography.subtitle,
                      ),
                    ],
                  ),
                ),
                NeuToggle(value: state.demoMode, onChanged: state.setDemoMode),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (BoonWindow.supportsWidget)
            _SectionCard(
              title: 'Widget Window',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Always on top',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: BoonColors.navy,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Keep the Boon dashboard above other windows, '
                              'like a floating desktop widget. Drag the '
                              'dashboard header to reposition it.',
                              style: BoonTypography.subtitle,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      NeuToggle(value: alwaysOnTop, onChanged: _setAlwaysOnTop),
                    ],
                  ),
                ],
              ),
            ),
          if (BoonWindow.supportsWidget) const SizedBox(height: 10),
          if (Platform.isAndroid) ...[
            _SectionCard(
              title: 'Background Link',
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Keep link alive in background',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: BoonColors.navy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'The link requires a persistent notification; this is '
                          'an Android rule — without it, status and clipboard '
                          'shut down while the app is in the background.',
                          style: BoonTypography.subtitle,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  NeuToggle(
                    value: state.keepLinkAlive,
                    onChanged: state.setKeepLinkAlive,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _SectionCard(
              title: 'Notification Forwarding',
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Forward notifications',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: BoonColors.navy,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Pause sending phone notifications to Boon Desktop.',
                          style: BoonTypography.subtitle,
                        ),
                      ],
                    ),
                  ),
                  NeuToggle(
                    value: state.notificationsEnabled,
                    onChanged: state.setNotificationsEnabled,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (state.notificationAppNames.isNotEmpty) ...[
              _SectionCard(
                title: 'Notification Apps',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose which phone apps can forward notifications to Boon Desktop.',
                      style: BoonTypography.subtitle,
                    ),
                    const SizedBox(height: 8),
                    for (final appId
                        in state.notificationAppNames.keys.toList()..sort())
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                state.notificationAppNames[appId] ?? appId,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: BoonColors.navy,
                                ),
                              ),
                            ),
                            NeuToggle(
                              value:
                                  state.notificationAppEnabled[appId] != false,
                              trackWidth: 58,
                              trackHeight: 30,
                              onChanged: (value) =>
                                  state.setNotificationAppEnabled(appId, value),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
          _SectionCard(
            title: 'Trusted Devices',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (trusted.isEmpty)
                  const Text(
                    'No paired devices yet. Pairing requests appear automatically; '
                    'you can also initiate pairing by IP below.',
                    style: BoonTypography.subtitle,
                  )
                else
                  for (final d in trusted)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_user_rounded,
                            size: 20,
                            color: BoonColors.accentDeep,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              d.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                _confirmForget(state, d.id, d.name),
                            child: const Text(
                              'Forget',
                              style: TextStyle(
                                color: BoonColors.textDim,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          if (CompanionBridge.available) ...[
            const SizedBox(height: 10),
            _SectionCard(
              title: 'Remote screen control',
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Enable Boon in Android Accessibility settings to allow taps from your paired desktop. This permission is sensitive and remains under your control.',
                      style: BoonTypography.subtitle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  NeuButton(
                    label: 'Open settings',
                    onTap: () =>
                        unawaited(CompanionBridge.openAccessibilitySettings()),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          _SectionCard(
            title: 'Pair by IP',
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: NeuInput(controller: addressCtl, hint: '192.168.1.42'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: NeuInput(controller: portCtl, hint: '45022'),
                ),
                const SizedBox(width: 8),
                NeuButton(
                  label: 'Connect',
                  onTap: () async {
                    final port = int.tryParse(portCtl.text.trim()) ?? 45022;
                    await state.pairAt(addressCtl.text.trim(), port);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _SectionCard(
            title: 'Link Status',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.link?.discoveryUnavailable == true
                      ? 'Discovery unavailable: ${state.link?.discoveryErrorText ?? ''}\n'
                            'You can still pair directly by IP.'
                      : 'Discovery broadcast on UDP 45021 • link server on TCP 45022.',
                  style: BoonTypography.subtitle,
                ),
                const SizedBox(height: 6),
                Text(
                  '${state.discovered.length} device(s) visible on the local network.',
                  style: BoonTypography.tiny,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmForget(AppState state, String id, String name) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: BoonColors.panelBase,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Forget Device',
          style: TextStyle(color: BoonColors.navy, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Remove $name from trusted devices? You will have to pair again to reconnect.',
          style: const TextStyle(color: BoonColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: BoonColors.textDim),
            ),
          ),
          NeuButton(
            label: 'Forget',
            onTap: () {
              state.forgetDevice(id);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      margin: const EdgeInsets.all(6),
      contentPadding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: BoonTypography.sectionTitle),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
