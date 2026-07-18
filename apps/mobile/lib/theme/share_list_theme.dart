import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand colors aligned with the public landing page (`server/src/landing.ts`).
abstract final class ShareListColors {
  static const navy = Color(0xFF1A1A4E);
  static const magenta = Color(0xFFE91E8C);
  static const purple = Color(0xFF7B2CBF);
  static const teal = Color(0xFF2EC4B6);
  static const coral = Color(0xFFFF6B6B);
  static const royal = Color(0xFF4361EE);
  static const ink = Color(0xFFF7F2FF);
  static const muted = Color(0xB8F7F2FF); // ~72% ink
  static const deep = Color(0xFF12123A);
  static const mid = Color(0xFF4A1F7A);
  static const hot = Color(0xFFC2186A);
  static const panel = Color(0x6B0C0A24); // ~42% #0c0a24
  static const panelSolid = Color(0xFF16132E);
  static const line = Color(0x24FFFFFF); // ~14% white
  static const link = Color(0xFF9AD5FF);
}

abstract final class ShareListTheme {
  static const backgroundDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        ShareListColors.deep,
        ShareListColors.mid,
        ShareListColors.hot,
      ],
      stops: [0.0, 0.48, 1.0],
    ),
  );

  /// Magenta + royal washes matching the landing page radials.
  static const backgroundOverlays = [
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.85, -0.9),
          radius: 1.15,
          colors: [
            Color(0x8CE91E8C),
            Color(0x00E91E8C),
          ],
        ),
      ),
    ),
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.95, 1.05),
          radius: 1.05,
          colors: [
            Color(0x664361EE),
            Color(0x004361EE),
          ],
        ),
      ),
    ),
  ];

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: ShareListColors.magenta,
      brightness: Brightness.dark,
      primary: ShareListColors.magenta,
      onPrimary: ShareListColors.ink,
      secondary: ShareListColors.royal,
      onSecondary: ShareListColors.ink,
      tertiary: ShareListColors.teal,
      onTertiary: ShareListColors.deep,
      error: ShareListColors.coral,
      onError: ShareListColors.deep,
      surface: ShareListColors.panelSolid,
      onSurface: ShareListColors.ink,
      onSurfaceVariant: ShareListColors.muted,
      outline: ShareListColors.line,
      outlineVariant: const Color(0x33FFFFFF),
      surfaceTint: ShareListColors.magenta,
    ).copyWith(
      primaryContainer: const Color(0xFF5C1048),
      onPrimaryContainer: ShareListColors.ink,
      secondaryContainer: const Color(0xFF24358A),
      onSecondaryContainer: ShareListColors.ink,
      tertiaryContainer: const Color(0xFF1A5C56),
      onTertiaryContainer: ShareListColors.ink,
      surfaceContainerLowest: const Color(0xFF0C0A24),
      surfaceContainerLow: const Color(0xFF12102A),
      surfaceContainer: ShareListColors.panelSolid,
      surfaceContainerHigh: const Color(0xFF1E1A3A),
      surfaceContainerHighest: const Color(0xFF262045),
      inversePrimary: ShareListColors.purple,
    );

    final baseText = GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme);
    final textTheme = baseText
        .apply(
          bodyColor: ShareListColors.ink,
          displayColor: ShareListColors.ink,
        )
        .copyWith(
          displayLarge: GoogleFonts.syne(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
            color: ShareListColors.ink,
          ),
          displayMedium: GoogleFonts.syne(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            color: ShareListColors.ink,
          ),
          displaySmall: GoogleFonts.syne(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: ShareListColors.ink,
          ),
          headlineLarge: GoogleFonts.syne(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: ShareListColors.ink,
          ),
          headlineMedium: GoogleFonts.syne(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: ShareListColors.ink,
          ),
          headlineSmall: GoogleFonts.syne(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: ShareListColors.ink,
          ),
          titleLarge: GoogleFonts.syne(
            fontWeight: FontWeight.w700,
            color: ShareListColors.ink,
          ),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ShareListColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.syne(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: ShareListColors.ink,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ShareListColors.panelSolid.withValues(alpha: 0.92),
        indicatorColor: ShareListColors.magenta.withValues(alpha: 0.28),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? ShareListColors.ink : ShareListColors.muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? ShareListColors.magenta : ShareListColors.muted,
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: ShareListColors.panelSolid.withValues(alpha: 0.72),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: ShareListColors.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ShareListColors.panelSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: ShareListColors.line),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: ShareListColors.panelSolid,
        modalBackgroundColor: ShareListColors.panelSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ShareListColors.navy,
        contentTextStyle: GoogleFonts.outfit(color: ShareListColors.ink),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ShareListColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ShareListColors.magenta,
          foregroundColor: ShareListColors.ink,
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ShareListColors.ink,
          side: const BorderSide(color: ShareListColors.line),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ShareListColors.link,
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ShareListColors.magenta,
        foregroundColor: ShareListColors.ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ShareListColors.panelSolid.withValues(alpha: 0.65),
        hintStyle: const TextStyle(color: ShareListColors.muted),
        labelStyle: const TextStyle(color: ShareListColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ShareListColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ShareListColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ShareListColors.magenta, width: 1.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: ShareListColors.line,
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: ShareListColors.muted,
        textColor: ShareListColors.ink,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: ShareListColors.magenta,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return ShareListColors.ink;
          }
          return ShareListColors.muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return ShareListColors.magenta;
          }
          return ShareListColors.navy;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ShareListColors.panelSolid,
        selectedColor: ShareListColors.magenta.withValues(alpha: 0.3),
        side: const BorderSide(color: ShareListColors.line),
        labelStyle: GoogleFonts.outfit(color: ShareListColors.ink),
      ),
    );
  }

  /// Paints the landing-page gradient behind every route.
  static Widget wrapBackground(Widget? child) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(decoration: backgroundDecoration),
        ...backgroundOverlays,
        child ?? const SizedBox.shrink(),
      ],
    );
  }
}
