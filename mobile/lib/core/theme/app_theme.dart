import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One colour theme the user can pick.
class AppPalette {
  const AppPalette({
    required this.key,
    required this.label,
    required this.primary,
    required this.primaryDark,
    required this.accent,
    required this.background,
  });

  final String key;
  final String label; // Hindi; translated where shown
  final Color primary;
  final Color primaryDark;
  final Color accent;
  final Color background;
}

// i18n:off (palette names are translated where shown)
const palettes = [
  // Default: Fresh Minimal - white, near-black type, one neon-green accent.
  AppPalette(key: 'fresh', label: 'फ़्रेश (सफ़ेद)', primary: Color(0xFF0A8F3C), primaryDark: Color(0xFF0A0A0A), accent: Color(0xFF00E676), background: Color(0xFFFFFFFF)),
  // Deep green on cream, like the first reference design.
  AppPalette(key: 'forest', label: 'जंगल हरा', primary: Color(0xFF1F6B4F), primaryDark: Color(0xFF0F3D2E), accent: Color(0xFFF5A524), background: Color(0xFFF7F4EC)),
  AppPalette(key: 'ocean', label: 'समुद्री नीला', primary: Color(0xFF2563EB), primaryDark: Color(0xFF1E3A8A), accent: Color(0xFFF97316), background: Color(0xFFF2F5FB)),
  AppPalette(key: 'sunset', label: 'सूर्यास्त', primary: Color(0xFFE4572E), primaryDark: Color(0xFF8C2A12), accent: Color(0xFF14B8A6), background: Color(0xFFFDF4EE)),
  AppPalette(key: 'royal', label: 'शाही बैंगनी', primary: Color(0xFF7C3AED), primaryDark: Color(0xFF3B0F80), accent: Color(0xFFF59E0B), background: Color(0xFFF6F2FD)),
  AppPalette(key: 'rose', label: 'गुलाबी', primary: Color(0xFFDB2777), primaryDark: Color(0xFF831843), accent: Color(0xFF10B981), background: Color(0xFFFDF2F7)),
  AppPalette(key: 'teal', label: 'फ़िरोज़ी', primary: Color(0xFF0F766E), primaryDark: Color(0xFF134E4A), accent: Color(0xFFF43F5E), background: Color(0xFFEFF8F6)),
];
// i18n:on

/// Colours used across the app. They follow the chosen palette and light/dark mode; the app rebuilds
/// every screen when either changes (see app.dart), so reading these getters is always up to date.
class AppTheme {
  AppTheme._();

  static AppPalette palette = palettes.first;
  static bool dark = false;

  /// The Fresh Minimal look (light mode): white surfaces, hairline borders instead of shadows.
  static bool get minimal => palette.key == 'fresh' && !dark;

  static Color get primary => palette.primary;
  // Near-black buttons would vanish on the dark background, so dark mode uses the brand green there.
  static Color get primaryDark => dark && palette.key == 'fresh' ? palette.primary : palette.primaryDark;
  static Color get accent => palette.accent;
  /// Accent for icons and text drawn on light backgrounds (the neon accent is unreadable on white).
  static Color get accentInk => minimal ? const Color(0xFF00A344) : palette.accent;

  /// Text/icons drawn on an accent-filled background.
  static Color get onAccent => minimal ? Colors.black : Colors.white;
  static const Color deal = Color(0xFFF97316); // discount badges and offer prices stay warm orange
  static const Color featured = Color(0xFFF59E0B);

  static Color get background => dark ? const Color(0xFF0F1412) : palette.background;
  static Color get card => dark ? const Color(0xFF1A201E) : Colors.white;
  static Color get chip => dark ? const Color(0xFF252C29) : minimal ? const Color(0xFFF3F4F6) : const Color(0xFFF1F1EC);
  static Color get ink => dark ? const Color(0xFFF1F3F2) : minimal ? const Color(0xFF0A0A0A) : const Color(0xFF17201C);
  static Color get muted => dark ? const Color(0xFFA7B0AC) : minimal ? const Color(0xFF6B6B6B) : const Color(0xFF6B7470);

  static LinearGradient get heroGradient => minimal
      ? const LinearGradient(colors: [Color(0xFF0A0A0A), Color(0xFF262626)], begin: Alignment.topLeft, end: Alignment.bottomRight)
      : LinearGradient(colors: [palette.primaryDark, palette.primary], begin: Alignment.topLeft, end: Alignment.bottomRight);

  static const LinearGradient dealGradient = LinearGradient(
    colors: [Color(0xFFFF8A00), Color(0xFFFF3D54)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> softShadow([double opacity = 0.08]) => dark
      ? const []
      : minimal
          // A 1 px hairline instead of a soft shadow keeps white cards visible on the white background.
          ? const [BoxShadow(color: Color(0x17000000), spreadRadius: 1)]
          : [BoxShadow(color: Colors.black.withValues(alpha: opacity), blurRadius: 20, offset: const Offset(0, 8))];

  static final BorderRadius radius = BorderRadius.circular(20);

  static ThemeData build(AppPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF0F1412) : p.background;
    final surface = isDark ? const Color(0xFF1A201E) : Colors.white;
    final fresh = p.key == 'fresh' && !isDark;
    final ink = isDark ? const Color(0xFFF1F3F2) : fresh ? const Color(0xFF0A0A0A) : const Color(0xFF17201C);
    final line = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.07);
    final scheme = ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: brightness,
      primary: isDark ? Color.lerp(p.primary, Colors.white, 0.25) : p.primary,
      secondary: p.accent,
      surface: surface,
    );
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      // Fresh Minimal: heavier, tighter headings.
      textTheme: fresh
          ? const TextTheme(
              headlineMedium: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.8),
              headlineSmall: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.6),
              titleLarge: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5),
              titleMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2),
            )
          : null,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: line)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? scheme.primary : p.primaryDark,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: rounded,
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: rounded)),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: line),
        backgroundColor: surface,
        selectedColor: scheme.primary.withValues(alpha: 0.16),
        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.15),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primaryDark,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? const Color(0xFF2B3330) : const Color(0xFF17201C),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.3, color: ink),
        contentTextStyle: TextStyle(fontSize: 14.5, height: 1.45, color: ink.withValues(alpha: 0.7)),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.55),
        dragHandleColor: ink.withValues(alpha: 0.2),
        dragHandleSize: const Size(44, 5),
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 20)),
      dividerTheme: DividerThemeData(color: line, space: 1),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: ink,
        indicator: BoxDecoration(color: p.primaryDark, borderRadius: BorderRadius.circular(30)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
