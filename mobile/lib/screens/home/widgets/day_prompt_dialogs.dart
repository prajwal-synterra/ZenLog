import 'package:flutter/material.dart';
import '../../../../state/zen_state.dart';

/// v2: Morning prompt dialogs are no longer mandatory gating popups.
/// Per the v2 blueprint: "No gating popups. Wake/sleep are optional."
///
/// This class is kept as a stub for backward compat with any remaining call sites.
class DayPromptDialogs {
  /// No-op in v2. The morning popup sequence has been removed.
  static Future<void> checkAndShowMorningSequence(
    BuildContext context,
    ZenState state,
  ) async {
    // v2: No popup sequence. Data loads via /api/days/{date}/view.
  }
}


