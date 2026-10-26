import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/state/app_state.dart';
import '../../core/protocol/boon_message.dart';
import '../../shared/utils/relative_time.dart';
import '../../shared/widgets/components.dart';
import '../../shared/widgets/neu.dart';
import '../../shared/widgets/quick_action_dialog.dart';

/// Phone Buddy page — follows ui/phonebuddy.png.
class PhoneBuddyPage extends StatelessWidget {
  const PhoneBuddyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final device = state.primaryDevice;

    if (device == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.phonelink_off_rounded,
              size: 54,
              color: BoonColors.textFaint,
            ),
            SizedBox(height: 14),
            Text('No phone connected', style: BoonTypography.cardTitle),
            SizedBox(height: 6),
            Text(
              'Discover and pair your phone in Settings to use Phone Buddy.',
              style: BoonTypography.subtitle,
            ),
          ],
        ),
      );
    }

    // On tall windows the content fills the panel (no dead space); short
    // windows fall back to scrolling.
    return LayoutBuilder(
      builder: (context, constraints) {
        final fill = constraints.maxHeight > 560;
        final column = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PhoneStatusCard(state: state),
            const SizedBox(height: 14),
            if (fill)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _actionsRow(context, state),
                ),
              )
            else
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _actionsRow(context, state),
                ),
              ),
          ],
        );
        return fill
            ? Padding(
                padding: const EdgeInsets.fromLTRB(30, 6, 30, 20),
                child: column,
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(30, 6, 30, 20),
                child: column,
              );
      },
    );
  }

  List<Widget> _actionsRow(BuildContext context, AppState state) {
    final device = state.primaryDevice!;
    return [
      Expanded(flex: 40, child: _NotificationSettingsCard(state: state)),
      const SizedBox(width: 10),
      Expanded(
        flex: 34,
        child: MediaPlayerCard(
          title: state.media.title ?? 'No Media',
          artist: state.media.artist ?? device.name,
          playing: state.media.playing,
          position: state.media.progress,
          available: state.media.available,
          onPlayPause: () {
            if (state.media.available) {
              state.sendMediaAction(state.media.playing ? 'pause' : 'play');
            }
          },
          onPrev: () {
            if (state.media.available) state.sendMediaAction('prev');
          },
          onNext: () {
            if (state.media.available) state.sendMediaAction('next');
          },
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 26,
        child: LayoutBuilder(
          builder: (context, c) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 40,
                  child: Row(
                    children: [
                      Expanded(
                        child: NeuSquareButton(
                          icon: Icons.link_rounded,
                          iconSize: 22,
                          size: null,
                          expanded: true,
                          onPressed: () =>
                              _openAction(context, state, sendLink: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: NeuSquareButton(
                          icon: Icons.chat_rounded,
                          iconSize: 20,
                          size: null,
                          expanded: true,
                          onPressed: () =>
                              _openAction(context, state, sendLink: false),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  flex: 40,
                  child: Row(
                    children: [
                      Expanded(
                        child: NeuSquareButton(
                          icon: Icons.task_alt_rounded,
                          iconSize: 22,
                          size: null,
                          expanded: true,
                          onPressed: state.syncNow,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: NeuSquareButton(
                          icon: Icons.phonelink_erase_rounded,
                          iconSize: 20,
                          size: null,
                          expanded: true,
                          onPressed: null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ];
  }

  void _openAction(
    BuildContext context,
    AppState state, {
    required bool sendLink,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => QuickActionDialog(state: state, sendLink: sendLink),
    );
  }

  void _openScreenMirror(BuildContext context, AppState state, String peerId) {
    unawaited(state.requestScreenShare(peerId));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Consumer<AppState>(
        builder: (context, current, _) => AlertDialog(
          backgroundColor: BoonColors.panelBase,
          title: Row(
            children: [
              const Expanded(
                child: Text('Phone screen', style: BoonTypography.sectionTitle),
              ),
              IconButton(
                tooltip: 'Close screen sharing',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          content: SizedBox(
            width: 760,
            height: 520,
            child: current.screenFrame == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (current.screenError == null)
                          const CircularProgressIndicator()
                        else
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 34,
                            color: BoonColors.textFaint,
                          ),
                        const SizedBox(height: 16),
                        Text(
                          current.screenError ??
                              current.screenStage ??
                              'Approve screen sharing on your phone.',
                          textAlign: TextAlign.center,
                          style: BoonTypography.subtitle,
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio:
                                current.screenFrameWidth > 0 &&
                                    current.screenFrameHeight > 0
                                ? current.screenFrameWidth /
                                      current.screenFrameHeight
                                : 9 / 19,
                            child: LayoutBuilder(
                              builder: (context, constraints) =>
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (details) => state.sendScreenTap(
                                      peerId,
                                      (details.localPosition.dx /
                                              constraints.maxWidth)
                                          .clamp(0.0, 1.0),
                                      (details.localPosition.dy /
                                              constraints.maxHeight)
                                          .clamp(0.0, 1.0),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(
                                        current.screenFrame!,
                                        fit: BoxFit.fill,
                                        gaplessPlayback: true,
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Tap control requires Boon Accessibility to be enabled on the phone.',
                              style: BoonTypography.tiny,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => state.link?.sendToPeer(
                              peerId,
                              BoonMessage.tCompanionAction,
                              {'action': 'open_accessibility_settings'},
                            ),
                            icon: const Icon(Icons.touch_app_rounded, size: 17),
                            label: const Text('Enable control'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ).then((_) => state.stopScreenShare(peerId));
  }
}

class _PhoneStatusCard extends StatelessWidget {
  const _PhoneStatusCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final device = state.primaryDevice!;
    return NeuCard(
      margin: const EdgeInsets.all(6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Row(
        children: [
          const PhoneSilhouette(width: 82, height: 148),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  device.name.toUpperCase(),
                  style: BoonTypography.cardTitle.copyWith(fontSize: 21),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                const ConnectionStatus(connected: true),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: BoonColors.panelBottom,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: BoonShadows.pressed(blur: 7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        device.charging
                            ? Icons.bolt_rounded
                            : Icons.timer_rounded,
                        size: 14,
                        color: BoonColors.textDim,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        device.charging ? 'Charging' : 'On battery',
                        style: BoonTypography.subtitle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  device.lastSeen == null
                      ? ''
                      : 'Last seen ${formatRelative(device.lastSeen!)}',
                  style: BoonTypography.tiny,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              NeuButton(
                label: 'View screen',
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                onTap: () => PhoneBuddyPage()._openScreenMirror(
                  context,
                  state,
                  device.id,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [BoonColors.accent, BoonColors.accentDeep],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: BoonColors.shadowDark,
                      offset: const Offset(4, 5),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Text(
                  device.battery == null ? 'Battery —' : '${device.battery}%',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationSettingsCard extends StatelessWidget {
  const _NotificationSettingsCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ready = state.primaryStatus?.notificationsReady ?? false;
    return NeuCard(
      margin: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Notification', style: BoonTypography.sectionTitle),
              ),
              TextButton(
                onPressed: state.notificationAppNames.isEmpty
                    ? null
                    : () => _showAppFilters(context, state),
                child: const Text('Manage apps'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                ready ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                size: 14,
                color: ready ? BoonColors.online : BoonColors.textFaint,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  ready ? 'Phone access granted' : 'Access off on the phone',
                  style: BoonTypography.tiny,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Forward notifications',
                  style: BoonTypography.subtitle,
                ),
              ),
              NeuToggle(
                value: state.notificationsEnabled,
                trackWidth: 64,
                trackHeight: 32,
                onChanged: state.setNotificationsEnabled,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Privacy Mode\nHide notification content',
                  style: BoonTypography.subtitle,
                ),
              ),
              NeuToggle(
                value: state.privacyMode,
                trackWidth: 64,
                trackHeight: 32,
                onChanged: state.setPrivacyMode,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.phoneNotifications.isEmpty
                ? 'No recent notifications'
                : 'Recent notifications',
            style: BoonTypography.tiny,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: state.phoneNotifications.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      ready
                          ? 'They’ll appear here when received.'
                          : 'Grant access on your phone to get started.',
                      style: BoonTypography.tiny,
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: state.phoneNotifications.take(3).length,
                    itemBuilder: (context, index) {
                      final notification = state.phoneNotifications[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.notifications_rounded,
                              size: 15,
                              color: BoonColors.accentDeep,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${notification.appName} · ${state.privacyMode ? 'Content hidden' : (notification.body ?? notification.title)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: BoonTypography.tiny,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatRelative(notification.time),
                              style: BoonTypography.tiny,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Android access', style: BoonTypography.tiny),
              if (!ready)
                GestureDetector(
                  onTap: () {
                    final device = state.primaryDevice;
                    if (device != null) {
                      state.requestNotificationAccess(device.id);
                    }
                  },
                  child: const Text(
                    'Enable on phone',
                    style: BoonTypography.tiny,
                  ),
                )
              else
                const Text('Mirroring on', style: BoonTypography.tiny),
            ],
          ),
        ],
      ),
    );
  }

  void _showAppFilters(BuildContext context, AppState state) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BoonColors.panelBase,
        title: const Text(
          'Notification apps',
          style: BoonTypography.sectionTitle,
        ),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final appId
                  in state.notificationAppNames.keys.toList()..sort())
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(state.notificationAppNames[appId] ?? appId),
                  subtitle: Text(
                    appId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: state.notificationAppEnabled[appId] != false,
                  onChanged: (enabled) =>
                      state.setNotificationAppEnabled(appId, enabled),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
