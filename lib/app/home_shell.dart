import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/pages.dart' show BoonPage;
import '../core/state/app_state.dart';
import '../features/clipboard/clipboard_page.dart';
import '../features/drop/drop_page.dart';
import '../features/home/dashboard_page.dart';
import '../features/phone_buddy/phone_buddy_page.dart';
import '../features/settings/settings_page.dart';
import '../shared/utils/relative_time.dart';
import '../shared/widgets/neu.dart';
import 'theme.dart';
import 'window.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  BoonPage page = BoonPage.home;
  int? _openDialogKey;

  static const navItems = <(BoonPage, IconData)>[
    (BoonPage.home, Icons.home_rounded),
    (BoonPage.clipboard, Icons.task_alt_rounded),
    (BoonPage.drop, Icons.cloud_upload_rounded),
    (BoonPage.phoneBuddy, Icons.fitness_center_rounded),
    (BoonPage.settings, Icons.settings_rounded),
  ];

  static String _title(BoonPage p) => switch (p) {
        BoonPage.home => '',
        BoonPage.clipboard => 'CLIPBOARD',
        BoonPage.drop => 'FILE TRANSFER',
        BoonPage.phoneBuddy => 'PHONE BUDDY',
        BoonPage.settings => 'SETTINGS',
      };

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _maybeShowPairingDialogs(state);

    // Unified shell like the updated reference: one continuous light panel
    // that fills the window; the nav rail is an inset column inside it.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onPanStart: (_) => unawaited(BoonWindow.startDragging()),
        behavior: HitTestBehavior.translucent,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF0F1F4), Color(0xFFE3E6EB)],
              ),
              boxShadow: BoonShadows.floating(),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  current: page,
                  items: navItems,
                  onSelect: (p) => setState(() => page = p),
                ),
                Expanded(
                  child: _MainPanel(
                    title: page == BoonPage.home ? _greeting() : _title(page),
                    titleSize: page == BoonPage.home ? 46 : 38,
                    onBell: () => _showNotifications(context),
                    onProfile: () => _showProfile(context),
                    child: switch (page) {
                      BoonPage.home => DashboardPage(onNavigate: (p) => setState(() => page = p)),
                      BoonPage.clipboard => const ClipboardPage(),
                      BoonPage.drop => const DropPage(),
                      BoonPage.phoneBuddy => const PhoneBuddyPage(),
                      BoonPage.settings => const SettingsPage(),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Pairing dialogs (incoming request + outgoing code verification)
  // ------------------------------------------------------------------

  void _maybeShowPairingDialogs(AppState state) {
    final incoming =
        state.incomingPairings.isEmpty ? null : state.incomingPairings.entries.first;
    final outgoing =
        state.outgoingCodes.isEmpty ? null : state.outgoingCodes.entries.first;
    if (incoming != null && _openDialogKey != _hash('in:${incoming.key}')) {
      _openDialogKey = _hash('in:${incoming.key}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showIncomingDialog(context, state, incoming.key, incoming.value.device.name, incoming.value.code);
      });
    } else if (outgoing != null && _openDialogKey != _hash('out:${outgoing.key}')) {
      _openDialogKey = _hash('out:${outgoing.key}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showCodeDialog(context, state, outgoing.key, outgoing.value.device.name, outgoing.value.code);
      });
    }
  }

  int _hash(String s) => s.hashCode;

  void _showIncomingDialog(
    BuildContext context,
    AppState state,
    String peerId,
    String name,
    String code,
  ) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: BoonColors.panelBase,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Pairing Request', style: TextStyle(fontWeight: FontWeight.w800, color: BoonColors.navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name wants to pair with this Boon device.',
                style: const TextStyle(color: BoonColors.textDim)),
            const SizedBox(height: 16),
            const Text('Verification code',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: BoonColors.textFaint)),
            const SizedBox(height: 4),
            Text(
              code.isEmpty ? '—' : code,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: BoonColors.navy, letterSpacing: 6),
            ),
            const SizedBox(height: 12),
            const Text(
              'Make sure the same code is shown on the other device before accepting.',
              style: TextStyle(fontSize: 12, color: BoonColors.textFaint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              state.rejectIncomingPairing(peerId);
              _openDialogKey = null;
              Navigator.pop(context);
            },
            child: const Text('Deny', style: TextStyle(color: BoonColors.textDim)),
          ),
          NeuButton(
            label: 'Accept',
            onTap: () async {
              await state.confirmIncomingPairing(peerId);
              _openDialogKey = null;
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showCodeDialog(
    BuildContext context,
    AppState state,
    String peerId,
    String name,
    String code,
  ) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: BoonColors.panelBase,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Verify Code', style: TextStyle(fontWeight: FontWeight.w800, color: BoonColors.navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pairing with $name. Confirm the code below matches the one shown on the other device.',
                style: const TextStyle(color: BoonColors.textDim)),
            const SizedBox(height: 16),
            Center(
              child: Text(
                code,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: BoonColors.navy, letterSpacing: 6),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              state.rejectIncomingPairing(peerId);
              _openDialogKey = null;
              Navigator.pop(context);
            },
            child: const Text('Cancel', style: TextStyle(color: BoonColors.textDim)),
          ),
          NeuButton(
            label: 'Code Matches',
            onTap: () async {
              await state.confirmOutgoingPairing(peerId);
              _openDialogKey = null;
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Bell + profile popups
  // ------------------------------------------------------------------

  void _showNotifications(BuildContext context) {
    final state = context.read<AppState>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BoonColors.panelBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Notification', style: BoonTypography.sectionTitle),
              const SizedBox(height: 10),
              if (state.phoneNotifications.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No notifications mirrored yet.',
                      style: BoonTypography.subtitle),
                )
              else
                ...state.phoneNotifications.take(6).map(
                      (n) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.smartphone, color: BoonColors.accentDeep),
                        title: Text(n.appName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        subtitle: Text(n.body ?? n.title, style: const TextStyle(fontSize: 12)),
                        trailing: Text(formatRelative(n.time), style: BoonTypography.tiny),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProfile(BuildContext context) {
    final state = context.read<AppState>();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: BoonColors.panelBase,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('This Device', style: TextStyle(fontWeight: FontWeight.w800, color: BoonColors.navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.identity?.name ?? 'Boon Desktop',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              state.identity == null
                  ? 'Booting…'
                  : 'ID: ${state.identity!.id}\nType: ${state.identity!.type}',
              style: BoonTypography.tiny,
            ),
            const SizedBox(height: 12),
            const Text(
              'Manage connectivity, demo mode and trusted devices in Settings.',
              style: BoonTypography.subtitle,
            ),
          ],
        ),
        actions: [
          NeuButton(
            label: 'OK',
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Sidebar
// =====================================================================

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.current,
    required this.items,
    required this.onSelect,
  });

  final BoonPage current;
  final List<(BoonPage, IconData)> items;
  final ValueChanged<BoonPage> onSelect;

  @override
  Widget build(BuildContext context) {
    // Inset nav rail merged into the unified panel (no separate card).
    return Container(
      width: 92,
      margin: const EdgeInsets.fromLTRB(10, 14, 4, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          colors: [Color(0xFFDFE3E9), Color(0xFFD6DBE2)],
        ),
        boxShadow: [
          BoxShadow(
            color: BoonColors.shadowDark,
            offset: const Offset(3, 3),
            blurRadius: 8,
          ),
          BoxShadow(
            color: Colors.white,
            offset: const Offset(-3, -3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [for (final (page, icon) in items) _NavItem(page, icon, page == current, onSelect)],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.page, this.icon, this.selected, this.onSelect);

  final BoonPage page;
  final IconData icon;
  final bool selected;
  final ValueChanged<BoonPage> onSelect;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: page.name,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? BoonColors.panelTop : Colors.transparent,
          ),
          child: InkWell(
            onTap: () => onSelect(page),
            customBorder: const CircleBorder(),
            child: Center(
              child: selected
                  ? Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFEFF1F4),
                        boxShadow: [
                          BoxShadow(
                            color: BoonColors.shadowDark,
                            offset: Offset(4, 4),
                            blurRadius: 10,
                          ),
                          BoxShadow(
                            color: Colors.white,
                            offset: Offset(-4, -4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(icon, size: 26, color: BoonColors.accentDeep),
                    )
                  : Icon(icon, size: 26, color: BoonColors.iconNeutral),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Main panel
// =====================================================================

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    required this.title,
    required this.titleSize,
    required this.child,
    required this.onBell,
    required this.onProfile,
  });

  final String title;
  final double titleSize;
  final Widget child;
  final VoidCallback onBell;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    // Content of the unified panel; the panel chrome (gradient + shadow +
    // radius) is applied by the shell wrapper.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(34, 24, 20, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: BoonTypography.pageTitle(titleSize),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              NeuIconButton(icon: Icons.notifications_none, onPressed: onBell),
              const SizedBox(width: 12),
              NeuIconButton(icon: Icons.person_outline_rounded, onPressed: onProfile),
              const SizedBox(width: 12),
              // Frameless window controls (native title bar is hidden
              // because the widget shell renders over the desktop).
              NeuIconButton(
                icon: Icons.remove_rounded,
                size: 38,
                iconSize: 18,
                onPressed: () => unawaited(BoonWindow.minimize()),
              ),
              const SizedBox(width: 8),
              NeuIconButton(
                icon: Icons.close_rounded,
                size: 38,
                iconSize: 17,
                iconColor: BoonColors.textDim,
                onPressed: () => unawaited(BoonWindow.close()),
              ),
            ],
          ),
        ),
        Expanded(child: child),
        const SizedBox(height: 8),
      ],
    );
  }
}

