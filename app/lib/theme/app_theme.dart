import 'package:flutter/material.dart';

/// Identifies one of the app's built-in visual themes.
enum AppThemeId { midnight, blossom }

/// Semantic surface colors not covered by [ColorScheme], swapped per theme:
/// the raised button/chip background used by steppers and tooltips, the
/// bottom-sheet background, and the line-chart grid color.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color raisedSurface;
  final Color sheetBackground;
  final Color chartGridLine;

  const AppPalette({
    required this.raisedSurface,
    required this.sheetBackground,
    required this.chartGridLine,
  });

  @override
  AppPalette copyWith({
    Color? raisedSurface,
    Color? sheetBackground,
    Color? chartGridLine,
  }) => AppPalette(
    raisedSurface: raisedSurface ?? this.raisedSurface,
    sheetBackground: sheetBackground ?? this.sheetBackground,
    chartGridLine: chartGridLine ?? this.chartGridLine,
  );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      raisedSurface: Color.lerp(raisedSurface, other.raisedSurface, t)!,
      sheetBackground: Color.lerp(sheetBackground, other.sheetBackground, t)!,
      chartGridLine: Color.lerp(chartGridLine, other.chartGridLine, t)!,
    );
  }
}

/// Metadata + [ThemeData] for one built-in theme.
class AppTheme {
  final AppThemeId id;
  final String label;
  final IconData icon;
  final ThemeData data;
  const AppTheme({
    required this.id,
    required this.label,
    required this.icon,
    required this.data,
  });
}

/// Registry of every built-in theme, keyed by [AppThemeId].
class AppThemes {
  AppThemes._();

  static const List<AppThemeId> all = [AppThemeId.midnight, AppThemeId.blossom];

  static AppTheme of(AppThemeId id) => switch (id) {
    AppThemeId.midnight => _midnight,
    AppThemeId.blossom => _blossom,
  };

  static final AppTheme _midnight = AppTheme(
    id: AppThemeId.midnight,
    label: 'Midnight',
    icon: Icons.dark_mode,
    data: _build(
      brightness: Brightness.dark,
      primary: Colors.redAccent,
      secondary: Colors.blueAccent,
      background: const Color(0xFF0E1117),
      surface: const Color(0xFF262730),
      palette: const AppPalette(
        raisedSurface: Color(0xFF1C1C26),
        sheetBackground: Color(0xFF262730),
        chartGridLine: Colors.white12,
      ),
    ),
  );

  /// Flowery / cutesy theme: soft pink-and-lavender pastels on a light,
  /// blush background.
  static final AppTheme _blossom = AppTheme(
    id: AppThemeId.blossom,
    label: 'Blossom',
    icon: Icons.local_florist,
    data: _build(
      brightness: Brightness.light,
      primary: const Color(0xFFE0679A),
      secondary: const Color(0xFF9B7FD4),
      background: const Color(0xFFFFF3F8),
      surface: const Color(0xFFFFE7F1),
      palette: const AppPalette(
        raisedSurface: Color(0xFFFBD6E6),
        sheetBackground: Color(0xFFFFEEF6),
        chartGridLine: Color(0x339B7FD4),
      ),
    ),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color secondary,
    required Color background,
    required Color surface,
    required AppPalette palette,
  }) {
    final colorScheme = brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: primary,
            secondary: secondary,
            surface: surface,
          )
        : ColorScheme.light(
            primary: primary,
            secondary: secondary,
            surface: surface,
          );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      cardColor: surface,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.25),
      ),
      extensions: [palette],
    );
  }
}
