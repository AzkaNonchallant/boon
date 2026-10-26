import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state/app_state.dart';
import '../features/link/link_status_page.dart';
import '../features/transfer/mobile_transfers_page.dart';
import '../features/settings/settings_page.dart';
import '../shared/widgets/components.dart' show AppIconCircle;
import '../shared/widgets/neu.dart';
import 'theme.dart';

/// Phone-flavored shell: a compact header + a two-tab bottom nav
/// (Link status/pairing + Settings). The neumorphic panel language of
/// [HomeShell] is preserved; desktop-only window chrome is dropped.
class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key});

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> with WidgetsBindingObserver {
  int _tab = 0;
  int? _openDialogKey;
  AppLifecycleState? _lastLifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackgrounded =
        _lastLifecycle == AppLifecycleState.paused ||
        _lastLifecycle == AppLifecycleState.hidden;
    _lastLifecycle = state;

    // Android 10+ blocks background clipboard reads; the moment the phone
    // regains focus is when phone→desktop sync becomes possible again.
    // Push immediately instead of waiting for the poller's next tick.
    // Gated to actual resume-from-background: Android denies clipboard
    // reads before the window is focused (including the very first resume
    // at app launch), so firing this during startup would just spam the
    // system log with denials.
    if (state == AppLifecycleState.resumed && wasBackgrounded) {
      final appState = context.read<AppState>();
      unawaited(appState.syncNow(quiet: true));
      unawaited(appState.refreshCompanionStatus());
      unawaited(appState.pushSelfStatus());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _maybeShowPairingDialogs(state);

    return Scaffold(
      backgroundColor: BoonColors.panelBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(state: state),
            Expanded(
              child: switch (_tab) {
                0 => const LinkStatusPage(),
                1 => const MobileTransfersPage(),
                _ => const SettingsPage(),
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: BoonColors.panelTop,
          boxShadow: [
            BoxShadow(
              color: BoonColors.shadowDark,
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _NavItem(
                Icons.link_rounded,
                'Link',
                0,
                selected: _tab,
                onSelect: (i) => setState(() => _tab = i),
              ),
              _NavItem(
                Icons.folder_rounded,
                'Files',
                1,
                selected: _tab,
                onSelect: (i) => setState(() => _tab = i),
              ),
              _NavItem(
                Icons.settings_rounded,
                'Settings',
                2,
                selected: _tab,
                onSelect: (i) => setState(() => _tab = i),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // Pairing dialogs — same flow as the desktop shell (home_shell.dart)
  // ----------------------------------------------------------------------

  void _maybeShowPairingDialogs(AppState state) {
    final incoming = state.incomingPairings.isEmpty
        ? null
        : state.incomingPairings.entries.first;
    final outgoing = state.outgoingCodes.isEmpty
        ? null
        : state.outgoingCodes.entries.first;
    if (incoming != null && _openDialogKey != '${incoming.key}:in'.hashCode) {
      _openDialogKey = '${incoming.key}:in'.hashCode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showIncomingDialog(
          context,
          state,
          incoming.key,
          incoming.value.device.name,
          incoming.value.code,
        );
      });
    } else if (outgoing != null &&
        _openDialogKey != '${outgoing.key}:out'.hashCode) {
      _openDialogKey = '${outgoing.key}:out'.hashCode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showCodeDialog(
          context,
          state,
          outgoing.key,
          outgoing.value.device.name,
          outgoing.value.code,
        );
      });
    }
  }

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Pairing Request',
          style: TextStyle(fontWeight: FontWeight.w800, color: BoonColors.navy),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name wants to pair with this device.',
              style: const TextStyle(color: BoonColors.textDim),
            ),
            const SizedBox(height: 16),
            const Text(
              'Verification code',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: BoonColors.textFaint,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                code.isEmpty ? '—' : code,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: BoonColors.navy,
                  letterSpacing: 8,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Check the same code shows on the other device before accepting.',
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
            child: const Text(
              'Deny',
              style: TextStyle(color: BoonColors.textDim),
            ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Verify Code',
          style: TextStyle(fontWeight: FontWeight.w800, color: BoonColors.navy),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pairing with $name. Confirm the code matches the desktop.',
              style: const TextStyle(color: BoonColors.textDim),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: BoonColors.navy,
                  letterSpacing: 8,
                ),
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
            child: const Text(
              'Cancel',
              style: TextStyle(color: BoonColors.textDim),
            ),
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
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
      child: Row(
        children: [
          const AppIconCircle(
            icon: Icons.connected_tv_rounded,
            size: 42,
            iconSize: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BOON LINK', style: BoonTypography.sectionTitle),
                Text(
                  // Real link only — demo mode must not claim a desktop link.
                  (state.link?.hasLinkedPeer ?? false)
                      ? 'Linked to your desktop'
                      : 'Same Wi-Fi as your desktop',
                  style: BoonTypography.tiny,
                ),
              ],
            ),
          ),
          if (state.link?.hasLinkedPeer ?? false)
            const Icon(Icons.wifi_rounded, size: 20, color: BoonColors.online)
          else
            const Icon(
              Icons.wifi_find_rounded,
              size: 20,
              color: BoonColors.textFaint,
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
    this.icon,
    this.label,
    this.index, {
    required this.selected,
    required this.onSelect,
  });

  final IconData icon;
  final String label;
  final int index;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final active = index == selected;
    return Expanded(
      child: Material(
        color: active ? BoonColors.panelBase : Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: active
                      ? BoonColors.accentDeep
                      : BoonColors.iconNeutral,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? BoonColors.accentDeep
                        : BoonColors.iconNeutral,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
