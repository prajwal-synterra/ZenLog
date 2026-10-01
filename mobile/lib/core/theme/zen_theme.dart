import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'zen_colors.dart';

/// ZenLog v3 "Ink & Paper" theme.
/// Typography: Fraunces (display/serif) + Inter (UI).
/// Both available via google_fonts — no network fetch needed at runtime
/// (they are loaded from the package's bundled assets via google_fonts).
class ZenTheme {
  ZenTheme._();

  static TextTheme _buildTextTheme(Color inkColor, Color mutedColor) {
    // Inter for UI text
    final inter = GoogleFonts.inter;

    return TextTheme(
      // Display styles — Fraunces (serif editorial)
      displayLarge: GoogleFonts.fraunces(
        fontSize: 40,
        height: 44 / 40,
        fontWeight: FontWeight.w600,
        color: inkColor,
      ),
      displayMedium: GoogleFonts.fraunces(
        fontSize: 28,
        height: 34 / 28,
        fontWeight: FontWeight.w600,
        color: inkColor,
      ),
      displaySmall: GoogleFonts.fraunces(
        fontSize: 32,
        height: 38 / 32,
        fontWeight: FontWeight.w600,
        color: inkColor,
      ),
      // Title — Inter semibold
      headlineLarge: inter(
        fontSize: 22,
        height: 28 / 22,
        fontWeight: FontWeight.w600,
        color: inkColor,
      ),
      headlineMedium: inter(
        fontSize: 18,
        height: 24 / 18,
        fontWeight: FontWeight.w600,
        color: inkColor,
      ),
      titleLarge: inter(
        fontSize: 18,
        height: 24 / 18,
        fontWeight: FontWeight.w600,
        color: inkColor,
      ),
      titleMedium: inter(
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w600,
        color: inkColor,
      ),
      titleSmall: inter(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        color: inkColor,
      ),
      // Body — Inter regular
      bodyLarge: inter(
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w400,
        color: inkColor,
      ),
      bodyMedium: inter(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        color: inkColor,
      ),
      bodySmall: inter(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w500,
        color: mutedColor,
      ),
      // Caption / label
      labelLarge: inter(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w500,
        color: mutedColor,
      ),
      labelMedium: inter(
        fontSize: 11,
        height: 16 / 11,
        fontWeight: FontWeight.w500,
        color: mutedColor,
      ),
      labelSmall: inter(
        fontSize: 10,
        height: 14 / 10,
        fontWeight: FontWeight.w500,
        color: mutedColor,
      ),
    );
  }

  static ThemeData get lightTheme {
    const tokens = ZenThemeTokens.light;
    return _buildTheme(
      brightness: Brightness.light,
      tokens: tokens,
      systemOverlay: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: ZenColors.lightSurface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  static ThemeData get darkTheme {
    const tokens = ZenThemeTokens.dark;
    return _buildTheme(
      brightness: Brightness.dark,
      tokens: tokens,
      systemOverlay: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: ZenColors.darkSurface,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ZenThemeTokens tokens,
    required SystemUiOverlayStyle systemOverlay,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: tokens.bg,

      colorScheme: ColorScheme(
        brightness: brightness,
        primary: tokens.ink,
        onPrimary: tokens.onInk,
        secondary: tokens.accent,
        onSecondary: tokens.onAccent,
        surface: tokens.surface,
        onSurface: tokens.ink,
        error: tokens.dangerFill,
        onError: tokens.onInk,
        outline: tokens.line,
        surfaceContainerHighest: tokens.surfaceAlt,
      ),

      textTheme: _buildTextTheme(tokens.ink, tokens.inkMuted),

      // Cards: 1 px hairline, no shadow
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: tokens.line, width: 1),
        ),
      ),

      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.ink, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.dangerFill),
        ),
        hintStyle: GoogleFonts.inter(
          color: tokens.inkFaint,
          fontSize: 16,
          height: 1.5,
        ),
        labelStyle: GoogleFonts.inter(
          color: tokens.inkMuted,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),

      // Primary button (ink fill, 52 high, radius 14)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.ink,
          foregroundColor: tokens.onInk,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),

      // Outlined (secondary) button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.ink,
          side: BorderSide(color: tokens.line),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),

      // Text button (tertiary)
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.ink,
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // AppBar: transparent, no elevation
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: tokens.ink,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: tokens.ink),
        systemOverlayStyle: systemOverlay,
      ),

      // Bottom navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: tokens.surface,
        selectedItemColor: tokens.ink,
        unselectedItemColor: tokens.inkFaint,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tokens.line),
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: tokens.ink,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 15,
          color: tokens.inkMuted,
          height: 1.5,
        ),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.ink,
        contentTextStyle: GoogleFonts.inter(color: tokens.onInk, fontSize: 14),
        actionTextColor: tokens.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 8,
      ),

      // Divider
      dividerTheme: DividerThemeData(color: tokens.line, thickness: 1),

      // Icon
      iconTheme: IconThemeData(color: tokens.inkMuted, size: 22),

      // Progress indicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.accent,
        linearTrackColor: tokens.surfaceAlt,
        circularTrackColor: tokens.surfaceAlt,
      ),

      // Switch / checkbox
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return tokens.ink;
          return tokens.surfaceAlt;
        }),
        checkColor: WidgetStateProperty.all(tokens.onInk),
        side: BorderSide(color: tokens.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}
