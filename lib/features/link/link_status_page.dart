import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/companion/android_companion.dart';
import '../../shared/utils/relative_time.dart';
import '../../shared/widgets/neu.dart';
import '../../shared/widgets/components.dart';
import '../../core/models/activity_event.dart';
import '../../core/models/boon_device.dart';
import '../../core/state/app_state.dart';
import '../../app/theme.dart';

/// Boon Link on the phone: own status, discovered devices and pairing.
///
/// Tapping a discovered device initiates the same verification-code
/// pairing flow used from the desktop (PairingEvent dialogs come from
/// [PhoneShell], mirroring home_shell's dialogs).
class LinkStatusPage extends StatefulWidget {
  const LinkStatusPage({super.key});

  @override
  State<LinkStatusPage> createState() => _LinkStatusPageState();
}

class _LinkStatusPageState extends State<LinkStatusPage> {
  AndroidBattery? _battery;
  Timer? _batteryTimer;
  final _addressCtl = TextEditingController(text: '192.168.');
  final _portCtl =     TextEditingController(text: '45022');

  @override
  void initState() {
    super.initState();
    unawaited(_refreshBattery());
    _batteryTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refreshBattery()),
    );
  }

  @override
  void dispose() {
    _batteryTimer?.cancel();
    _addressCtl.dispose();
    _portCtl.dispose();
    super.dispose();
  }

  Future<void> _refreshBattery() async {
    final battery = await AndroidCompanion.readBattery();
    if (!mounted) return;
    setState(() => _battery = battery);
  }

  void _pairDiscovered(AppState state, BoonDevice device) {
    unawaited(state.pairAt(device.address!, device.port));
  }

  void _pairManual(AppState state) {
    final address = _addressCtl.text.trim();
    final port = int.tryParse(_portCtl.text.trim());
    if (address.isEmpty) {
      state.addActivity(ActivityKind.info, 'Pair by address', 'Enter the desktop IP first.');
      state.requestUiUpdate();
      return;
    }
    unawaited(state.pairAt(address, port));
    state.requestUiUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final identity = state.identity;
    final link = state.link;
    final discovered = state.discovered;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ThisDeviceCard(
            name: identity?.name ?? 'Booning…',
            id: identity?.id,
            battery: _battery,
          ),
          if (state.companionSupported && !state.notificationListenerActive) ...[
            const SizedBox(height: 14),
            NeuCard(
              contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_active_rounded,
                          size: 20, color: BoonColors.accentDeep),
                      const SizedBox(width: 8),
                      const Text('Notification access', style: BoonTypography.cardTitle),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Allow Boon to mirror notifications to your desktop and control '
                    'media playback. This needs Android\'s Notification Access '
                    'special permission — Boon never reads content it does not forward.',
                    style: BoonTypography.subtitle,
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: NeuButton(
                      label: 'Allow access',
                      onTap: state.openNotificationListenerSettings,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (link?.discoveryUnavailable ?? false)
            NeuCard(
              contentPadding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 20, color: BoonColors.textDim),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      link?.discoveryErrorText ?? 'Discovery unavailable — pair by address.',
                      style: BoonTypography.subtitle,
                    ),
                  ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 10, 8, 2),
            child: Text('Discovered Devices', style: BoonTypography.sectionTitle),
          ),
          if (discovered.isEmpty)
            NeuCard(
              contentPadding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.radar_rounded, size: 22, color: BoonColors.accentDeep),
                      const SizedBox(width: 8),
                      const Text('Scanning this Wi-Fi…',
                          style: BoonTypography.cardTitle),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Boon devices on the same network appear here. Start Boon on the '
                    'desktop then pull to refresh by leaving and reopening this page.',
                    style: BoonTypography.subtitle,
                  ),
                ],
              ),
            )
          else
            ...discovered.map((device) => _DiscoveredCard(
                  device: device,
                  trusted: state.trustedDevices.containsKey(device.id),
                  onPair: () => _pairDiscovered(state, device),
                )),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 18, 8, 2),
            child: Text('Pair by Address', style: BoonTypography.sectionTitle),
          ),
          NeuCard(
            contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: NeuInput(
                        controller: _addressCtl,
                        hint: 'IP of the desktop, e.g. 192.168.1.10',
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 90,
                      child: NeuInput(controller: _portCtl, hint: 'Port'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: NeuButton(
                    label: 'Pair',
                    onTap: () => _pairManual(state),
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
                  ),
                ),
              ],
            ),
          ),
          if (state.trustedDevices.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 18, 8, 2),
              child: Text('Trusted Devices', style: BoonTypography.sectionTitle),
            ),
            ...state.trustedDevices.values.map(
              (p) => NeuCard(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, size: 20, color: BoonColors.accentDeep),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, color: BoonColors.navy)),
                          Text('ID ${p.id.substring(0, 8)}…', style: BoonTypography.tiny),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Forget',
                      icon: const Icon(Icons.link_off_rounded, size: 18, color: BoonColors.textFaint),
                      onPressed: () {
                        state.forgetDevice(p.id);
                        state.addActivity(ActivityKind.connection, 'Device forgotten', p.name);
                        state.requestUiUpdate();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThisDeviceCard extends StatelessWidget {
  const _ThisDeviceCard({required this.name, this.id, this.battery});

  final String name;
  final String? id;
  final AndroidBattery? battery;

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      contentPadding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(
        children: [
          const AppIconCircle(icon: Icons.smartphone_rounded, size: 48, iconSize: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: BoonTypography.cardTitle.copyWith(fontSize: 17),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  id == null ? 'Generating identity…' : 'ID ${id!.substring(0, 8)}… • phone',
                  style: BoonTypography.tiny,
                ),
              ],
            ),
          ),
          const ConnectionStatus(connected: true, compact: true, label: 'Online'),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [BoonColors.accent, BoonColors.accentDeep],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: BoonColors.shadowDark,
                  offset: const Offset(3, 4),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  battery == null
                      ? Icons.battery_unknown_rounded
                      : battery!.charging
                          ? Icons.bolt_rounded
                          : Icons.battery_std_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  battery == null ? '—' : '${battery!.level}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Colors.white,
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

class _DiscoveredCard extends StatelessWidget {
  const _DiscoveredCard({
    required this.device,
    required this.trusted,
    required this.onPair,
  });

  final BoonDevice device;
  final bool trusted;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            device.type == DeviceType.phone
                ? Icons.smartphone_rounded
                : Icons.computer_rounded,
            size: 22,
            color: BoonColors.accentDeep,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: BoonColors.navy),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${device.address ?? '?'}:${device.port ?? 45022} • seen ${device.lastSeen == null ? '' : formatRelative(device.lastSeen!)}',
                  style: BoonTypography.tiny,
                ),
              ],
            ),
          ),
          if (trusted)
            const Icon(Icons.verified_rounded, size: 20, color: BoonColors.online)
          else
            NeuButton(
              label: 'Pair',
              onTap: onPair,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
            ),
        ],
      ),
    );
  }
}
