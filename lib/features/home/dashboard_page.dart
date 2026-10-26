import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/pages.dart';
import '../../app/theme.dart';
import '../../core/models/activity_event.dart';
import '../../core/models/boon_device.dart' show DeviceType;
import '../../core/state/app_state.dart';
import '../../shared/utils/relative_time.dart';
import '../../shared/widgets/components.dart';
import '../../shared/widgets/neu.dart';
import '../../shared/widgets/quick_action_dialog.dart';

/// Dashboard — layout follows ui/dashboard.png:
/// device card + 3 feature cards, then activity/notification/media row.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, this.onNavigate});

  final ValueChanged<BoonPage>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 880;
        final row1Height = (constraints.maxWidth * 0.21).clamp(210.0, 280.0);
        final column = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: row1Height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: wide ? 17 : 100,
                    child: _DeviceCard(state: state),
                  ),
                  if (wide) ...[
                    const Spacer(flex: 1),
                    Expanded(
                      flex: 9,
                      child: FeatureCard(
                        icon: Icons.task_alt_rounded,
                        title: 'Clipboard',
                        subtitle: 'Sync Text, Images, Files',
                        onTap: () => onNavigate?.call(BoonPage.clipboard),
                      ),
                    ),
                    const Spacer(flex: 1),
                    Expanded(
                      flex: 9,
                      child: FeatureCard(
                        icon: Icons.cloud_upload_rounded,
                        title: 'File Transfer',
                        subtitle: 'Send And Receive Files',
                        onTap: () => onNavigate?.call(BoonPage.drop),
                      ),
                    ),
                    const Spacer(flex: 1),
                    Expanded(
                      flex: 9,
                      child: FeatureCard(
                        icon: Icons.fitness_center_rounded,
                        title: 'Phone Buddy',
                        subtitle: 'Notification, Media, Battery',
                        onTap: () => onNavigate?.call(BoonPage.phoneBuddy),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (wide)
              Expanded(
                child: _Row2(
                  state: state,
                  quickAction: (s, {required sendLink}) => _openQuickAction(context, s, sendLink: sendLink)                ),
              )
            else
              SizedBox(
                height: 430,
                child: _Row2(
                  state: state,
                  quickAction: (s, {required sendLink}) => _openQuickAction(context, s, sendLink: sendLink)                ),
              ),
          ],
        );
        // On wide windows the second row fills the remaining height, so the
        // dashboard has no dead space; narrower windows fall back to scroll.
        return wide
            ? Padding(
                padding: const EdgeInsets.fromLTRB(30, 10, 24, 22),
                child: column,
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(30, 10, 24, 20),
                child: column,
              );
      },
    );
  }

  void _openQuickAction(BuildContext context, AppState state, {required bool sendLink}) {
    showDialog<void>(
      context: context,
      builder: (_) => QuickActionDialog(state: state, sendLink: sendLink),
    );
  }
}

// =====================================================================
// Second dashboard row (activity / notifications / media + quick actions)
// =====================================================================

class _Row2 extends StatelessWidget {
  const _Row2({required this.state, required this.quickAction});

  final AppState state;
  final void Function(AppState state, {required bool sendLink}) quickAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 42,
          child: _RecentActivityCard(state: state),
        ),
        const Spacer(flex: 1),
        Expanded(
          flex: 33,
          child: _NotificationsCard(state: state),
        ),
        const Spacer(flex: 1),
        Expanded(
          flex: 23,
          child: Column(
            children: [
              Expanded(
                flex: 66,
                child: _DashboardMedia(state: state),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 18,
                child: Row(
                  children: [
                    Expanded(
                      child: NeuSquareButton(
                        icon: Icons.link_rounded,
                        iconSize: 22,
                        size: null,
                        expanded: true,
                        onPressed: () => quickAction(state, sendLink: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NeuSquareButton(
                        icon: Icons.chat_rounded,
                        iconSize: 20,
                        size: null,
                        expanded: true,
                        onPressed: () => quickAction(state, sendLink: false),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// Connected device card
// =====================================================================

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final device = state.primaryDevice;
    return NeuCard(
      margin: const EdgeInsets.all(6),
      child: device == null
          ? const _DeviceEmptyState()
          : Row(
              children: [
                const PhoneSilhouette(width: 66, height: 120),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        device.name.toUpperCase(),
                        style: BoonTypography.cardTitle.copyWith(fontSize: 19, letterSpacing: 0.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      const ConnectionStatus(connected: true, compact: true),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: BoonColors.panelBottom,
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: BoonShadows.pressed(blur: 6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  device.charging ? Icons.bolt_rounded : Icons.timer_rounded,
                                  size: 13,
                                  color: BoonColors.textDim,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  device.battery == null
                                      ? 'Battery —'
                                      : '${device.battery}%',
                                  style: BoonTypography.tiny,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (device.type != DeviceType.unknown)
                            Text(device.type.name, style: BoonTypography.tiny),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('Last Seen', style: BoonTypography.subtitle),
                      Text(
                        device.lastSeen == null
                            ? '—'
                            : 'Today, ${formatClockTime(device.lastSeen!)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: BoonColors.navy,
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

class _DeviceEmptyState extends StatelessWidget {
  const _DeviceEmptyState();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 66,
          height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BoonColors.panelBottom,
            borderRadius: BorderRadius.circular(18),
            boxShadow: BoonShadows.pressed(blur: 8),
          ),
          child: Icon(Icons.phonelink_off_rounded, size: 26, color: BoonColors.textFaint),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('NO DEVICE', style: BoonTypography.cardTitle),
              const SizedBox(height: 5),
              Text(
                'Discover and pair a device in Settings.',
                style: BoonTypography.subtitle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// Feature cards (Clipboard / File Transfer / Phone Buddy)
// =====================================================================

class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      margin: const EdgeInsets.all(6),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconCircle(icon: icon, size: 50, iconSize: 24),
          const Spacer(),
          Text(
            title,
            style: BoonTypography.cardTitle.copyWith(fontSize: 17),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: BoonTypography.tiny,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Recent activity
// =====================================================================

IconData _kindIcon(ActivityKind kind) => switch (kind) {
      ActivityKind.fileSent => Icons.upload_rounded,
      ActivityKind.fileReceived => Icons.image_rounded,
      ActivityKind.clipboard => Icons.task_alt_rounded,
      ActivityKind.connection => Icons.link_rounded,
      ActivityKind.info => Icons.chat_rounded,
    };

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final items = state.activities;
    return NeuCard(
      margin: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Recent Activity', style: BoonTypography.sectionTitle)),
              Text('View All', style: BoonTypography.subtitle.copyWith(color: BoonColors.accentDeep)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('No recent Boon activity.', style: BoonTypography.subtitle),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final e = items[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: BoonColors.panelTop,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: BoonShadows.raised(
                                  blur: 7,
                                  darkOffset: const Offset(3, 3),
                                  lightOffset: const Offset(-3, -3),
                                ),
                              ),
                              child: Icon(_kindIcon(e.kind), size: 17, color: BoonColors.accentDeep),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.title,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: BoonColors.navy,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    e.subtitle,
                                    style: BoonTypography.tiny,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatRelative(e.time),
                              style: BoonTypography.tiny,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Mirrored notifications
// =====================================================================

IconData _notifIcon(String appId) {
  // Mock peers use short ids; real Android mirrors use package names.
  final id = appId.toLowerCase();
  if (id.contains('whatsapp')) return Icons.chat_bubble_rounded;
  if (id.contains('instagram')) return Icons.camera_alt_outlined;
  if (id.contains('telegram')) return Icons.send_rounded;
  if (id.contains('boon')) return Icons.satellite_alt_rounded;
  return Icons.notifications_rounded;
}

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final items = state.phoneNotifications;
    return NeuCard(
      margin: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Notification', style: BoonTypography.sectionTitle)),
              Text('View All', style: BoonTypography.subtitle.copyWith(color: BoonColors.accentDeep)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      state.primaryStatus?.notificationsReady == false
                          ? 'Notification access is off on the phone.\nEnable it in Boon on your phone.'
                          : 'No notifications mirrored yet.',
                      style: BoonTypography.subtitle,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final n = items[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: BoonColors.panelBottom,
                              child: Icon(_notifIcon(n.appId), size: 16, color: BoonColors.navy),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.appName,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: BoonColors.navy,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    state.privacyMode
                                        ? 'Content hidden (privacy mode)'
                                        : (n.body ?? n.title),
                                    style: BoonTypography.tiny,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Text(formatRelative(n.time), style: BoonTypography.tiny),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Dashboard media (small variant) + quick actions wiring
// =====================================================================

class _DashboardMedia extends StatelessWidget {
  const _DashboardMedia({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final media = state.media;
    return MediaPlayerCard(
      title: media.title ?? 'No Media',
      artist: media.artist ?? state.primaryDevice?.name ?? '—',
      playing: media.playing,
      position: media.progress,
      available: media.available,
      onPlayPause: () {
        if (media.available) {
          state.sendMediaAction(media.playing ? 'pause' : 'play');
        }
      },
      onPrev: () {
        if (media.available) state.sendMediaAction('prev');
      },
      onNext: () {
        if (media.available) state.sendMediaAction('next');
      },
    );
  }
}
