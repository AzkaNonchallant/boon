import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Base neumorphic container following the soft-UI reference style.
class NeuCard extends StatelessWidget {
  const NeuCard({
    super.key,
    required this.child,
    this.contentPadding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.all(6),
    this.radius = 18,
    this.color,
    this.border,
    this.onTap,
  });

  final Widget child;

  /// Spacing between the content and the card walls.
  final EdgeInsetsGeometry contentPadding;

  /// Outer spacing so soft shadows are not clipped.
  final EdgeInsetsGeometry margin;
  final double radius;
  final Color? color;
  final Color? border;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? BoonColors.panelBase,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!, width: 1.5),
        boxShadow: BoonShadows.raised(),
      ),
      child: Padding(padding: contentPadding, child: child),
    );
    if (onTap == null) {
      return Padding(padding: margin, child: box);
    }
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: box,
        ),
      ),
    );
  }
}

/// Neumorphic text field used by dialogs (send link / send text / pairing).
class NeuInput extends StatelessWidget {
  const NeuInput({
    super.key,
    required this.controller,
    this.hint,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String? hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: BoonColors.navy, fontSize: 13),
      cursorColor: BoonColors.accentDeep,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: BoonColors.textFaint, fontSize: 13),
        filled: true,
        fillColor: BoonColors.panelBottom,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: BoonColors.accentDeep,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

/// Pill-shaped raised primary button used in dialogs and CTAs.
class NeuButton extends StatelessWidget {
  const NeuButton({
    super.key,
    required this.label,
    this.onTap,
    this.accent = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
  });

  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: accent ? null : BoonColors.panelBase,
          gradient: accent
              ? const LinearGradient(
                  colors: [BoonColors.accent, BoonColors.accentDeep],
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: BoonColors.shadowDark,
              offset: const Offset(3, 4),
              blurRadius: 8,
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: padding,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular neumorphic button (header icons, media controls).
class NeuIconButton extends StatelessWidget {
  const NeuIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.iconSize = 20,
    this.iconColor = BoonColors.iconNeutral,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: BoonColors.panelBase,
          shape: BoxShape.circle,
          boxShadow: BoonShadows.raised(
            blur: 10,
            darkOffset: const Offset(4, 4),
            lightOffset: const Offset(-4, -4),
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Center(
            child: Icon(icon, size: iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}

/// Neumorphic rounded-square button (quick actions).
/// Pass [size] as null (with [expanded] = true) to fill its parent.
class NeuSquareButton extends StatelessWidget {
  const NeuSquareButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 62,
    this.iconSize = 24,
    this.expanded = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double? size;
  final double iconSize;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: expanded ? double.infinity : size,
        child: AspectRatio(
          aspectRatio: expanded ? 1 : 1,
          child: Ink(
            decoration: BoxDecoration(
              color: BoonColors.panelBase,
              borderRadius: BorderRadius.circular(16),
              boxShadow: BoonShadows.raised(
                blur: 12,
                darkOffset: const Offset(5, 5),
                lightOffset: const Offset(-5, -5),
              ),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(16),
              child: Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: BoonColors.iconNeutral,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Neumorphic on/off switch.
class NeuToggle extends StatelessWidget {
  const NeuToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.trackWidth = 58,
    this.trackHeight = 32,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final double trackWidth;
  final double trackHeight;

  @override
  Widget build(BuildContext context) {
    final knobSize = trackHeight - 6;
    return Semantics(
      button: true,
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: trackWidth,
          height: trackHeight,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? BoonColors.accentDeep : BoonColors.panelBottom,
            borderRadius: BorderRadius.circular(trackHeight / 2),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: knobSize,
              height: knobSize,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    offset: const Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One radio row used on the Clipboard settings cards.
class NeuRadioRow<T> extends StatelessWidget {
  const NeuRadioRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelect,
    this.title = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final bool title;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: title ? BoonColors.navy : BoonColors.textDim,
    );
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: BoonColors.panelBase,
                shape: BoxShape.circle,
                boxShadow: BoonShadows.raised(
                  blur: 6,
                  darkOffset: const Offset(2, 2),
                  lightOffset: const Offset(-2, -2),
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: BoonColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Text(label, style: titleStyle),
          ],
        ),
      ),
    );
  }
}

/// Small soft pill with text, e.g. the blue "78%" battery pill.
class NeuPill extends StatelessWidget {
  const NeuPill({
    super.key,
    required this.label,
    this.filled = true,
    this.gradient = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
  });

  final String label;
  final bool filled;
  final bool gradient;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: gradient
            ? null
            : (filled ? BoonColors.accent : BoonColors.panelBase),
        gradient: gradient
            ? const LinearGradient(
                colors: [BoonColors.accentSoft, BoonColors.accent],
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: BoonColors.shadowDark,
            offset: const Offset(3, 3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: filled || gradient ? Colors.white : BoonColors.textDim,
        ),
      ),
    );
  }
}
