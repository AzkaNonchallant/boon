import 'package:flutter/material.dart';

/// Boon visual identity — light gray neumorphic panels floating as a
/// widget over the desktop wallpaper, steel-blue accents. Matches
/// ui/*.png references.
class BoonColors {
  BoonColors._();

  // Neumorphic panel base
  static const panelBase = Color(0xFFEBEDF1);
  static const panelTop = Color(0xFFF4F5F7);
  static const panelBottom = Color(0xFFE2E5EA);

  // Neumorphic shadows
  static const shadowDark = Color(0xFFB8C0CB);
  static const shadowLight = Colors.white;

  // Accent
  static const accent = Color(0xFF8FB7D8);
  static const accentDeep = Color(0xFF6FA3C9);
  static const accentSoft = Color(0xFFB9D4E8);

  // Text
  static const navy = Color(0xFF14344F);
  static const textDim = Color(0xFF3E5C74);
  static const textFaint = Color(0xFF5F7C96);

  // Status
  static const online = Color(0xFF2E90DC);

  static const iconNeutral = Color(0xFF57758F);
}

class BoonShadows {
  BoonShadows._();

  static List<BoxShadow> raised({
    double blur = 14,
    Offset darkOffset = const Offset(7, 7),
    Offset lightOffset = const Offset(-7, -7),
  }) => [
        BoxShadow(
          color: BoonColors.shadowDark,
          offset: darkOffset,
          blurRadius: blur,
        ),
        BoxShadow(
          color: BoonColors.shadowLight,
          offset: lightOffset,
          blurRadius: blur,
        ),
      ];

  static List<BoxShadow> pressed({
    double blur = 12,
    bool invert = true,
  }) => invert
      ? [
          BoxShadow(
            color: BoonColors.shadowDark,
            offset: const Offset(-5, -5),
            blurRadius: blur,
          ),
          BoxShadow(
            color: BoonColors.shadowLight,
            offset: const Offset(5, 5),
            blurRadius: blur,
          ),
        ]
      : raised(blur: blur);

  static List<BoxShadow> floating() => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          offset: const Offset(8, 10),
          blurRadius: 30,
        ),
      ];
}

class BoonTypography {
  BoonTypography._();

  /// Big condensed uppercase page title, e.g. "GOOD MORNING".
  static TextStyle pageTitle(double size) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: BoonColors.navy,
        height: 1.05,
        letterSpacing: 0.5,
      );

  static const cardTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: BoonColors.navy,
  );

  static const sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: BoonColors.navy,
    letterSpacing: 0.3,
  );

  static const subtitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: BoonColors.textDim,
    height: 1.3,
  );

  static const tiny = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: BoonColors.textFaint,
  );
}

ThemeData buildBoonTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: ColorScheme.fromSeed(
      seedColor: BoonColors.accentDeep,
      brightness: Brightness.light,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: BoonColors.navy),
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.comfortable,
  );
}
