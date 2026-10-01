import 'package:flutter/material.dart';

/// ZenLog v3 "Ink & Paper" design tokens.
/// All components must consume tokens — never raw hex.
/// See ZENLOG_UI_UX_SPEC_V3.md §3.1
class ZenColors {
  ZenColors._();

  // ─── Light Tokens ──────────────────────────────────────────────────────────
  static const Color lightBg          = Color(0xFFF7F3EA);
  static const Color lightSurface     = Color(0xFFFFFDF8);
  static const Color lightSurfaceAlt  = Color(0xFFEFE9DB);
  static const Color lightLine        = Color(0xFFE3DCCB);
  static const Color lightInk         = Color(0xFF1D1B17);
  static const Color lightInkMuted    = Color(0xFF6B665B);
  static const Color lightInkFaint    = Color(0xFF9A9487);
  static const Color lightOnInk       = Color(0xFFF7F3EA);
  static const Color lightAccent      = Color(0xFFE8A33D);
  static const Color lightOnAccent    = Color(0xFF1D1B17);

  // Semantic — light
  static const Color lightSuccessFill = Color(0xFF2F7D5B);
  static const Color lightSuccessTint = Color(0xFFE1F0E7);
  static const Color lightSuccessText = Color(0xFF1F5A40);

  static const Color lightInfoFill    = Color(0xFF3E6A8A);
  static const Color lightInfoTint    = Color(0xFFE0EBF3);
  static const Color lightInfoText    = Color(0xFF2B4D68);

  static const Color lightWarnFill    = Color(0xFFD98E04);
  static const Color lightWarnTint    = Color(0xFFFBEFD3);
  static const Color lightWarnText    = Color(0xFF7A4B00);

  static const Color lightDangerFill  = Color(0xFFC0412F);
  static const Color lightDangerTint  = Color(0xFFF8E0DB);
  static const Color lightDangerText  = Color(0xFF8E2B1D);

  static const Color lightScrim       = Color(0x73000000); // rgba(29,27,23,0.45)

  // ─── Dark Tokens ──────────────────────────────────────────────────────────
  static const Color darkBg          = Color(0xFF14130F);
  static const Color darkSurface     = Color(0xFF1D1B16);
  static const Color darkSurfaceAlt  = Color(0xFF26231D);
  static const Color darkLine        = Color(0xFF34312A);
  static const Color darkInk         = Color(0xFFF3EEE2);
  static const Color darkInkMuted    = Color(0xFFA8A294);
  static const Color darkInkFaint    = Color(0xFF7A7568);
  static const Color darkOnInk       = Color(0xFF14130F);
  static const Color darkAccent      = Color(0xFFF2B544);
  static const Color darkOnAccent    = Color(0xFF14130F);

  // Semantic — dark
  static const Color darkSuccessFill = Color(0xFF5DBB8A);
  static const Color darkSuccessTint = Color(0x295DBB8A); // rgba(93,187,138,0.16)
  static const Color darkSuccessText = Color(0xFF8FD7B0);

  static const Color darkInfoFill    = Color(0xFF7FB0D6);
  static const Color darkInfoTint    = Color(0x297FB0D6); // rgba(127,176,214,0.16)
  static const Color darkInfoText    = Color(0xFFA9CBE6);

  static const Color darkWarnFill    = Color(0xFFF2B544);
  static const Color darkWarnTint    = Color(0x29F2B544); // rgba(242,181,68,0.16)
  static const Color darkWarnText    = Color(0xFFF6CC7E);

  static const Color darkDangerFill  = Color(0xFFE8715E);
  static const Color darkDangerTint  = Color(0x29E8715E); // rgba(232,113,94,0.16)
  static const Color darkDangerText  = Color(0xFFF2A394);

  static const Color darkScrim       = Color(0x99000000); // rgba(0,0,0,0.6)
}

/// Resolved tokens that change with theme. Use via extension below.
class ZenThemeTokens {
  const ZenThemeTokens({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.onInk,
    required this.accent,
    required this.onAccent,
    required this.successFill,
    required this.successTint,
    required this.successText,
    required this.infoFill,
    required this.infoTint,
    required this.infoText,
    required this.warnFill,
    required this.warnTint,
    required this.warnText,
    required this.dangerFill,
    required this.dangerTint,
    required this.dangerText,
    required this.scrim,
    required this.isDark,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color line;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color onInk;
  final Color accent;
  final Color onAccent;
  final Color successFill;
  final Color successTint;
  final Color successText;
  final Color infoFill;
  final Color infoTint;
  final Color infoText;
  final Color warnFill;
  final Color warnTint;
  final Color warnText;
  final Color dangerFill;
  final Color dangerTint;
  final Color dangerText;
  final Color scrim;
  final bool isDark;

  /// Returns the fill/tint/text triple for a given log status string.
  ({Color fill, Color tint, Color text}) statusTokens(String? status) {
    switch (status) {
      case 'met':
      case 'good':
        return (fill: successFill, tint: successTint, text: successText);
      case 'on_track':
      case 'ahead':
        return (fill: infoFill, tint: infoTint, text: infoText);
      case 'behind':
      case 'ok':
        return (fill: warnFill, tint: warnTint, text: warnText);
      case 'far_behind':
      case 'over':
      case 'poor':
      case 'impossible':
        return (fill: dangerFill, tint: dangerTint, text: dangerText);
      default:
        return (fill: inkFaint, tint: bg, text: inkFaint);
    }
  }

  static const ZenThemeTokens light = ZenThemeTokens(
    bg: ZenColors.lightBg,
    surface: ZenColors.lightSurface,
    surfaceAlt: ZenColors.lightSurfaceAlt,
    line: ZenColors.lightLine,
    ink: ZenColors.lightInk,
    inkMuted: ZenColors.lightInkMuted,
    inkFaint: ZenColors.lightInkFaint,
    onInk: ZenColors.lightOnInk,
    accent: ZenColors.lightAccent,
    onAccent: ZenColors.lightOnAccent,
    successFill: ZenColors.lightSuccessFill,
    successTint: ZenColors.lightSuccessTint,
    successText: ZenColors.lightSuccessText,
    infoFill: ZenColors.lightInfoFill,
    infoTint: ZenColors.lightInfoTint,
    infoText: ZenColors.lightInfoText,
    warnFill: ZenColors.lightWarnFill,
    warnTint: ZenColors.lightWarnTint,
    warnText: ZenColors.lightWarnText,
    dangerFill: ZenColors.lightDangerFill,
    dangerTint: ZenColors.lightDangerTint,
    dangerText: ZenColors.lightDangerText,
    scrim: ZenColors.lightScrim,
    isDark: false,
  );

  static const ZenThemeTokens dark = ZenThemeTokens(
    bg: ZenColors.darkBg,
    surface: ZenColors.darkSurface,
    surfaceAlt: ZenColors.darkSurfaceAlt,
    line: ZenColors.darkLine,
    ink: ZenColors.darkInk,
    inkMuted: ZenColors.darkInkMuted,
    inkFaint: ZenColors.darkInkFaint,
    onInk: ZenColors.darkOnInk,
    accent: ZenColors.darkAccent,
    onAccent: ZenColors.darkOnAccent,
    successFill: ZenColors.darkSuccessFill,
    successTint: ZenColors.darkSuccessTint,
    successText: ZenColors.darkSuccessText,
    infoFill: ZenColors.darkInfoFill,
    infoTint: ZenColors.darkInfoTint,
    infoText: ZenColors.darkInfoText,
    warnFill: ZenColors.darkWarnFill,
    warnTint: ZenColors.darkWarnTint,
    warnText: ZenColors.darkWarnText,
    dangerFill: ZenColors.darkDangerFill,
    dangerTint: ZenColors.darkDangerTint,
    dangerText: ZenColors.darkDangerText,
    scrim: ZenColors.darkScrim,
    isDark: true,
  );
}

/// Extension to resolve tokens from BuildContext.
extension ZenContextTokens on BuildContext {
  ZenThemeTokens get zen {
    final isDark = Theme.of(this).brightness == Brightness.dark;
    return isDark ? ZenThemeTokens.dark : ZenThemeTokens.light;
  }
}

// ─── Legacy aliases for files not yet migrated ────────────────────────────
// TODO: Remove these once all screens are migrated to context.zen.*
class ZenColors2 {
  // Kept temporarily so old references compile. Map to v3 light tokens.
  static const Color background    = ZenColors.lightBg;
  static const Color surface       = ZenColors.lightSurface;
  static const Color cardBg        = ZenColors.lightSurface;
  static const Color cardBorder    = ZenColors.lightLine;
  static const Color primary       = ZenColors.lightInk;
  static const Color accent        = ZenColors.lightAccent;
  static const Color textPrimary   = ZenColors.lightInk;
  static const Color textSecondary = ZenColors.lightInkMuted;
  static const Color pillBg        = ZenColors.lightSurfaceAlt;
  static const Color pillBorder    = ZenColors.lightLine;
  static const Color forestDark    = ZenColors.lightInk;
  static const Color forestMedium  = ZenColors.lightInkMuted;
  static const Color forestLight   = ZenColors.lightInkFaint;
  static const Color emeraldAccent = ZenColors.lightSuccessFill;
  static const Color completeGreen = ZenColors.lightSuccessFill;
  static const Color mintSoft      = ZenColors.lightSuccessTint;
  static const Color mintGlow      = ZenColors.lightLine;
  static const Color hydrationCyan = ZenColors.lightInfoFill;
  static const Color hydrationSoft = ZenColors.lightInfoTint;
  static const Color workoutPurple = ZenColors.lightAccent;
  static const Color workoutSoft   = ZenColors.lightSurfaceAlt;
  static const Color incompleteAmber = ZenColors.lightWarnFill;
  static const Color incompleteSoft  = ZenColors.lightWarnTint;
  static const Color sageBg        = ZenColors.lightBg;
  static const Color sageSurface   = ZenColors.lightSurface;
  static const Color cardSurface   = ZenColors.lightSurface;
  static const Color divider       = ZenColors.lightLine;
  static const Color textDark      = ZenColors.lightInk;
  static const Color textMuted     = ZenColors.lightInkMuted;
  static const Color textSubtle    = ZenColors.lightInkFaint;
}
