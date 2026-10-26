import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/state/app_state.dart';
import 'neu.dart';

/// Send link / text dialog, shared by Dashboard and Phone Buddy.
class QuickActionDialog extends StatefulWidget {
  const QuickActionDialog({super.key, required this.state, required this.sendLink});

  final AppState state;
  final bool sendLink;

  @override
  State<QuickActionDialog> createState() => _QuickActionDialogState();
}

class _QuickActionDialogState extends State<QuickActionDialog> {
  final controller = TextEditingController();
  String? selectedPeer;

  @override
  void initState() {
    super.initState();
    final device = widget.state.primaryDevice;
    selectedPeer = device?.id;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.state.connectedDevices;
    return AlertDialog(
      backgroundColor: BoonColors.panelBase,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.sendLink ? 'Send Link' : 'Send Text',
        style: const TextStyle(fontWeight: FontWeight.w800, color: BoonColors.navy),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Destination', style: BoonTypography.sectionTitle),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              const Text('No device connected.', style: BoonTypography.subtitle)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in devices)
                    ChoiceChip(
                      label: Text(d.name),
                      selected: selectedPeer == d.id,
                      selectedColor: BoonColors.accent,
                      labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      onSelected: (_) => setState(() => selectedPeer = d.id),
                    ),
                ],
              ),
            const SizedBox(height: 14),
            NeuInput(controller: controller, hint: widget.sendLink ? 'https://' : 'Type text…'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: BoonColors.textDim)),
        ),
        NeuButton(
          label: 'Send',
          onTap: selectedPeer == null || controller.text.trim().isEmpty
              ? null
              : () async {
                  final text = controller.text.trim();
                  if (widget.sendLink) {
                    await widget.state.sendLink(selectedPeer!, text);
                  } else {
                    await widget.state.sendText(selectedPeer!, text);
                  }
                  if (context.mounted) Navigator.pop(context);
                },
        ),
      ],
    );
  }
}
