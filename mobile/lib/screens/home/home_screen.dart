import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/zen_colors.dart';
import '../../core/theme/zen_theme_controller.dart';
import '../../state/zen_state.dart';
import '../../services/wake_service.dart';
import '../../services/api_service.dart';
import '../profile/saved_meals_screen.dart';
import '../camera/photo_meal_sheet.dart';
import '../camera/label_scan_screen.dart';
import '../foods/my_products_screen.dart';
import 'widgets/morning_walk_card.dart';


Map<String, dynamic>? _asMap(dynamic val) {
  if (val == null) return null;
  if (val is Map<String, dynamic>) return val;
  if (val is Map) {
    return val.map((k, v) => MapEntry(k.toString(), v));
  }
  return null;
}

// ─── Home / Today Screen ───────────────────────────────────────────────────
// Implements ZenLog v3 §6.5 – "Ink & Paper" design
// 4 modes: today | past | future | empty_past
// Composer dock replaces FAB. No score on today. Next Move card (not stacked alerts).

class HomeScreen extends StatefulWidget {
  final ZenState state;
  final VoidCallback? onNavigateToCalendar;
  final VoidCallback? onNavigateToInsights;
  final VoidCallback? onNavigateToProfile;

  const HomeScreen({
    super.key,
    required this.state,
    this.onNavigateToCalendar,
    this.onNavigateToInsights,
    this.onNavigateToProfile,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final TextEditingController _logController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _dateStripController = ScrollController();
  final FocusNode _composerFocus = FocusNode();

  bool _composerExpanded = false;
  bool _isSending = false;
  String _selectedPastMealPreset = 'Lunch';
  TimeOfDay? _customTimeOfDay;

  @override
  void initState() {
    super.initState();
    _composerFocus.addListener(() => setState(() {}));
    // Auto-scroll date strip after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDateStripToSelected());
  }

  @override
  void dispose() {
    _logController.dispose();
    _scrollController.dispose();
    _dateStripController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _scrollDateStripToSelected() {
    final state = widget.state;
    final today = state.logicalToday ?? state.selectedDate;
    final todayDate = DateTime.tryParse(today) ?? DateTime.now();
    final dates = List.generate(29, (i) => todayDate.subtract(Duration(days: 14 - i)));
    final selectedIdx = dates.indexWhere((d) {
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return key == state.selectedDate;
    });
    if (selectedIdx >= 0 && _dateStripController.hasClients) {
      const itemW = 56.0; // approximate chip width
      final offset = (selectedIdx * itemW) - (MediaQuery.of(context).size.width / 2) + (itemW / 2);
      _dateStripController.animateTo(
        offset.clamp(0.0, _dateStripController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  DateTime _resolvePastDateTime(String dateStr, TimeOfDay tod) {
    final parts = dateStr.split('-');
    final y = int.tryParse(parts[0]) ?? DateTime.now().year;
    final m = int.tryParse(parts[1]) ?? DateTime.now().month;
    final d = int.tryParse(parts[2]) ?? DateTime.now().day;
    DateTime baseDate = DateTime(y, m, d);
    if (tod.hour < 4) {
      // 00:00 - 03:59 belongs to the logical previous day, so it occurs on next calendar day
      baseDate = baseDate.add(const Duration(days: 1));
    }
    return DateTime(baseDate.year, baseDate.month, baseDate.day, tod.hour, tod.minute);
  }

  Future<void> _handleRepeatLog(String id) async {
    final t = context.zen;
    final ok = await widget.state.repeatLog(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Log repeated to today' : 'Could not repeat log'),
          backgroundColor: t.ink,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handleChangeLogTime(String id, String currentDay) async {
    final t = context.zen;
    final currentDate = DateTime.tryParse(currentDay) ?? DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(DateTime.now()),
    );
    if (pickedTime == null || !mounted) return;

    final targetDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final ok = await widget.state.moveLogTime(id, targetDateTime);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Entry moved successfully' : 'Could not move entry'),
          backgroundColor: t.ink,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handleSaveAsFavorite(String id, String text) async {
    final t = context.zen;
    final ok = await widget.state.saveMealFromLog(id, name: text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Saved as favorite meal' : 'Could not save as favorite (needs nutrition values)'),
        backgroundColor: t.ink,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleQuickWater(int amount) async {
    HapticFeedback.lightImpact();
    final t = context.zen;
    final logId = await widget.state.logQuickWater(amount);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('+$amount ml water logged'),
        backgroundColor: t.ink,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          textColor: t.accent,
          onPressed: () {
            if (logId != null) {
              widget.state.deleteLog(logId);
            }
          },
        ),
      ),
    );
  }

  void _showCustomWaterDialog() {
    final t = context.zen;
    final ctrl = TextEditingController(text: '300');
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Custom Water Amount'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          decoration: InputDecoration(
            suffixText: 'ml',
            filled: true,
            fillColor: t.surfaceAlt,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text.trim());
              Navigator.pop(dlgCtx);
              if (val != null && val > 0) {
                _handleQuickWater(val);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: t.ink, foregroundColor: t.onInk),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showPortionSheet(Map<String, dynamic> meal) {
    final t = context.zen;
    final id = meal['id'] as String? ?? '';
    final name = meal['name'] as String? ?? 'Meal';
    final extracted = (meal['extracted'] as Map?) ?? {};
    final baseProtein = (extracted['protein_g'] as num?)?.toDouble() ?? 0.0;
    final baseCal = (extracted['calories'] as num?)?.toInt() ?? (extracted['calories_kcal'] as num?)?.toInt() ?? 0;

    double portion = 1.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final p = (baseProtein * portion).toStringAsFixed(1);
            final cal = (baseCal * portion).round();

            return Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: t.line),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: t.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    name,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose portion size to log:',
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [0.5, 1.0, 1.5, 2.0].map((opt) {
                      final isSelected = (portion - opt).abs() < 0.01;
                      return GestureDetector(
                        onTap: () => setSheetState(() => portion = opt),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? t.ink : t.surfaceAlt,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? t.ink : t.line),
                          ),
                          child: Text(
                            '${opt}×',
                            style: TextStyle(
                              color: isSelected ? t.onInk : t.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text('$p g protein', style: TextStyle(fontWeight: FontWeight.w600, color: t.ink)),
                        Text('·', style: TextStyle(color: t.inkMuted)),
                        Text('$cal kcal', style: TextStyle(fontWeight: FontWeight.w600, color: t.ink)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(sheetCtx);
                        HapticFeedback.lightImpact();
                        final ok = await widget.state.logSavedMeal(id, portion: portion);
                        if (mounted && ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Logged "$name (${portion}x)"'),
                              backgroundColor: t.ink,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.ink,
                        foregroundColor: t.onInk,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Log ${portion}×'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMealOptionsSheet(Map<String, dynamic> meal) {
    final t = context.zen;
    final id = meal['id'] as String? ?? '';
    final name = meal['name'] as String? ?? 'Meal';
    final isPinned = meal['pinned'] == true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: t.line),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: t.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.ink)),
            const SizedBox(height: 14),
            ListTile(
              leading: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin, color: t.ink),
              title: Text(isPinned ? 'Unpin from quick bar' : 'Pin to quick bar', style: TextStyle(color: t.ink)),
              onTap: () {
                Navigator.pop(sheetCtx);
                widget.state.updateSavedMeal(id, pinned: !isPinned);
              },
            ),
            ListTile(
              leading: Icon(Icons.manage_search_rounded, color: t.ink),
              title: Text('Manage in Saved Meals', style: TextStyle(color: t.ink)),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SavedMealsScreen(state: widget.state)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete favorite', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetCtx);
                widget.state.deleteSavedMeal(id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterQuickButtons(ZenThemeTokens t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _handleQuickWater(250),
          onLongPress: _showCustomWaterDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.line),
            ),
            child: Text(
              '+250',
              style: TextStyle(
                color: t.ink,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => _handleQuickWater(500),
          onLongPress: _showCustomWaterDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.line),
            ),
            child: Text(
              '+500',
              style: TextStyle(
                color: t.ink,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesChipRow(ZenState state, ZenThemeTokens t) {
    final meals = state.savedMeals.take(6).toList();
    if (meals.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 34,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: meals.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, i) {
          final meal = meals[i];
          final name = meal['name'] as String? ?? 'Meal';
          final isPinned = meal['pinned'] == true;

          return GestureDetector(
            onTap: () => _showPortionSheet(meal),
            onLongPress: () => _showMealOptionsSheet(meal),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: isPinned ? t.ink : t.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPinned) ...[
                    Icon(Icons.push_pin, size: 11, color: t.ink),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    name,
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSuggestionBanner(ZenState state, ZenThemeTokens t) {
    if (state.savedMealSuggestions.isEmpty) return const SizedBox.shrink();
    final first = state.savedMealSuggestions.first;
    final name = first['name'] as String? ?? '';
    final count = first['count'] as int? ?? 3;
    final sampleLogId = first['sample_log_id'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 16, color: t.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frequent meal detected',
                  style: TextStyle(color: t.inkFaint, fontSize: 10.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'You\'ve logged "$name" $count times. Save as favorite?',
                  style: TextStyle(color: t.ink, fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => state.dismissSuggestion(first['raw_text'] as String),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('Dismiss', style: TextStyle(color: t.inkMuted, fontSize: 11.5)),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: () async {
              if (sampleLogId != null) {
                await state.saveMealFromLog(sampleLogId, name: name);
              }
              state.dismissSuggestion(first['raw_text'] as String);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Saved "$name" as favorite'), backgroundColor: t.ink),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: t.ink,
              foregroundColor: t.onInk,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Save', style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _logController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSending = true);
    _logController.clear();
    _composerFocus.unfocus();
    setState(() => _composerExpanded = false);

    final mode = (widget.state.currentDayView?['mode'] as String?) ?? 'today';
    DateTime? loggedAt;
    if (mode == 'past') {
      TimeOfDay tod;
      switch (_selectedPastMealPreset) {
        case 'Breakfast':
          tod = const TimeOfDay(hour: 8, minute: 30);
          break;
        case 'Lunch':
          tod = const TimeOfDay(hour: 13, minute: 0);
          break;
        case 'Dinner':
          tod = const TimeOfDay(hour: 20, minute: 30);
          break;
        case 'Custom':
          tod = _customTimeOfDay ?? const TimeOfDay(hour: 12, minute: 0);
          break;
        default:
          tod = const TimeOfDay(hour: 13, minute: 0);
      }
      loggedAt = _resolvePastDateTime(widget.state.selectedDate, tod);
    }

    await widget.state.addLog(text, loggedAt: loggedAt);
    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final t = context.zen;
    final dayView = state.currentDayView;
    final isLoading = state.isDayViewLoading && dayView == null;
    final mode = (dayView?['mode'] as String?) ?? 'today';
    final isToday = mode == 'today';
    final composerEnabled = isToday || mode == 'past';

    return Scaffold(
      backgroundColor: t.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ──
            _buildHeader(state, mode, t),
            // ── Date strip ──
            _buildDateStrip(state, t),
            const _HairlineDivider(),
            // ── Body ──
            Expanded(
              child: isLoading
                  ? _buildSkeleton(t)
                  : dayView == null
                      ? _buildError(state, t)
                      : RefreshIndicator(
                          color: t.ink,
                          backgroundColor: t.surface,
                          onRefresh: () => state.loadDayView(state.selectedDate),
                          child: _buildModeBody(dayView, state, mode, t),
                        ),
            ),
            // ── Composer dock ──
            if (composerEnabled) _buildComposerDock(state, t),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(ZenState state, String mode, ZenThemeTokens t) {
    final user = state.user;
    final initials = _initials(user?.name);
    final today = state.logicalToday ?? state.selectedDate;
    final isOnToday = state.selectedDate == today;

    final rawName = user?.name.trim();
    final String? displayName = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : ((user?.username.trim().isNotEmpty == true) ? user!.username.trim() : null);

    String dayName;
    String dateStr;
    if (mode == 'today') {
      final now = DateTime.now();
      dayName = _weekdayFull(now.weekday);
      dateStr = '${now.day} ${_monthFull(now.month)}';
    } else {
      final d = DateTime.tryParse(state.selectedDate) ?? DateTime.now();
      dayName = _weekdayFull(d.weekday);
      dateStr = '${d.day} ${_monthFull(d.month)} ${d.year}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (displayName != null) ...[
                  Text(
                    'Welcome, $displayName',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: t.inkMuted,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  dayName,
                  style: GoogleFonts.fraunces(
                    fontSize: 32,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      dateStr,
                      style: TextStyle(
                        color: t.inkMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (mode == 'today') ...[
                      const SizedBox(width: 8),
                      _TodayPill(t: t),
                    ],
                    if (!isOnToday) ...[
                      const SizedBox(width: 8),
                      _ModeBadge(mode: mode, t: t),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    key: const ValueKey('theme_toggle_btn'),
                    onTap: () => ZenThemeController.instance.toggleTheme(context),

                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.surface,
                        border: Border.all(color: t.line),
                      ),
                      child: Center(
                        child: Icon(
                          t.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                          size: 20,
                          color: t.ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onNavigateToProfile,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.ink,
                        border: Border.all(color: t.line),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            color: t.onInk,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!isOnToday) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {
                    final today = state.logicalToday ?? state.selectedDate;
                    state.setSelectedDate(today);
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDateStripToSelected());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Back to today',
                      style: TextStyle(
                        color: t.onAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Date strip ─────────────────────────────────────────────────────────────

  Widget _buildDateStrip(ZenState state, ZenThemeTokens t) {
    final today = state.logicalToday ?? state.selectedDate;
    final todayDate = DateTime.tryParse(today) ?? DateTime.now();
    final dates = List.generate(29, (i) => todayDate.subtract(Duration(days: 14 - i)));

    return SizedBox(
      height: 68,
      child: ListView.builder(
        controller: _dateStripController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: dates.length,
        itemBuilder: (ctx, i) {
          final d = dates[i];
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          final isSelected = key == state.selectedDate;
          final isToday = key == today;
          final isFuture = d.isAfter(todayDate);

          return GestureDetector(
            onTap: () {
              state.setSelectedDate(key);
              WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDateStripToSelected());
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
              width: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isSelected ? t.ink : t.surface,
                border: Border.all(
                  color: isSelected ? t.ink : t.line,
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _dayLetter(d.weekday),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? t.onInk : t.inkFaint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? t.onInk
                          : isFuture
                              ? t.inkFaint
                              : t.ink,
                    ),
                  ),
                  if (isToday)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? t.accent : t.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Mode body ──────────────────────────────────────────────────────────────

  Widget _buildModeBody(Map<String, dynamic> dayView, ZenState state, String mode, ZenThemeTokens t) {
    return SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWakeBanner(t),
          if (mode == 'today') ...[
            if (widget.state.wakeTime != null) ...[
              MorningWalkCard(wakeTime: widget.state.wakeTime!),
            ],
            _buildDailyQuoteBanner(state, dayView, t),
            _buildSuggestionBanner(state, t),
            _buildPaceCard(dayView, t),
            const SizedBox(height: 12),
            _buildNextMoveCard(dayView, t),
            const SizedBox(height: 20),
            _buildEntriesSection(dayView, state, editable: true, t: t),
            const SizedBox(height: 20),
            if ((dayView['verdict'] as Map?)?['ai'] != null) ...[
              _buildVerdictNote(dayView, state, t),
              const SizedBox(height: 16),
            ],
            _buildAnalyzeCard(dayView, state, t),
          ] else if (mode == 'past') ...[
            _buildDailyQuoteBanner(state, dayView, t),
            _buildScoreRing(dayView, t),
            const SizedBox(height: 12),
            _buildVerdictNote(dayView, state, t),
            const SizedBox(height: 20),
            _buildEntriesSection(dayView, state, editable: true, t: t),
          ] else if (mode == 'future') ...[
            _buildMotivationHero(dayView, t),
            const SizedBox(height: 12),
            _buildFocusCard(dayView, t),
          ] else ...[
            _buildEmptyPast(state, t),
          ],
        ],
      ),
    );
  }

  // ── Cold-Start Wake Banner (Module 1) ────────────────────────────────────

  Widget _buildWakeBanner(ZenThemeTokens t) {
    return ListenableBuilder(
      listenable: WakeService(),
      builder: (context, _) {
        if (!WakeService().isWaking) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: t.warnTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.warnFill.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(t.warnFill),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Waking server… (can take up to a minute on cold start)',
                  style: TextStyle(
                    color: t.warnText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Pace card ──────────────────────────────────────────────────────────────

  Widget _buildPaceCard(Map<String, dynamic> dayView, ZenThemeTokens t) {
    final totals = _asMap(dayView['totals']) ?? {};
    final targets = _asMap(dayView['targets']) ?? {};
    final progress = _asMap(dayView['progress']) ?? {};
    final pendingCount = (dayView['pending_count'] as int?) ?? 0;

    final proteinActual = (totals['protein_g'] as num?)?.toDouble() ?? 0;
    final proteinTarget = (targets['protein_g'] as num?)?.toDouble() ?? 126;
    final waterActual = (totals['hydration_ml'] as num?)?.toDouble() ?? 0;
    final waterTarget = (targets['water_ml'] as num?)?.toDouble() ?? 3000;
    final calActual = (totals['calories_kcal'] as num?)?.toDouble() ?? 0;
    final calTarget = (targets['calories_kcal'] as num?)?.toDouble()
        ?? widget.state.user?.dailyCalorieTarget
        ?? 2000.0;
    final workoutDone = totals['workout_done'] == true;
    final weekDone = (progress['workout'] as Map?)?['week_done'] as int?
        ?? (widget.state.weeklyInsight?.statsSummary['workout_days'] as num?)?.toInt()
        ?? (workoutDone ? 1 : 0);
    final weekTarget = (progress['workout'] as Map?)?['week_target'] as int?
        ?? (targets['weekly_workout_target'] as num?)?.toInt()
        ?? 3;

    // Worst status for pace chip
    final proteinStatus = (progress['protein'] as Map?)?['status'] as String? ?? 'on_track';
    final waterStatus = (progress['water'] as Map?)?['status'] as String? ?? 'on_track';
    final calStatus = (progress['calories'] as Map?)?['status'] as String? ?? 'on_track';
    final worstStatus = _worstStatus([proteinStatus, waterStatus, calStatus]);

    return _ZenCard(
      t: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'PACE',
                style: TextStyle(
                  color: t.inkFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (pendingCount > 0)
                _ReadingChip(t: t)
              else
                _StatusChip(status: worstStatus, t: t),
            ],
          ),
          const SizedBox(height: 14),
          _PaceRow(
            label: 'Protein',
            actual: proteinActual,
            target: proteinTarget,
            unit: 'g',
            status: proteinStatus,
            expectedPct: (progress['protein'] as Map?)?['expected_pct_now'] as double?,
            t: t,
          ),
          const SizedBox(height: 12),
          _PaceRow(
            label: 'Water',
            actual: waterActual,
            target: waterTarget,
            unit: 'ml',
            status: waterStatus,
            expectedPct: (progress['water'] as Map?)?['expected_pct_now'] as double?,
            t: t,
            trailingAction: _buildWaterQuickButtons(t),
          ),
          const SizedBox(height: 12),
          _PaceRow(
            label: 'Calories',
            actual: calActual,
            target: calTarget,
            unit: 'kcal',
            status: calStatus,
            t: t,
          ),
          const SizedBox(height: 14),
          // Workout row
          Row(
            children: [
              Icon(Icons.fitness_center_outlined, size: 16, color: t.inkMuted),
              const SizedBox(width: 8),
              Text('Workout', style: TextStyle(color: t.inkMuted, fontSize: 14)),
              const Spacer(),
              Text(
                workoutDone ? 'Done today' : 'None today',
                style: TextStyle(
                  color: workoutDone ? t.successText : t.inkMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (weekTarget > 0) ...[
                Text(
                  '  ·  $weekDone/$weekTarget this week',
                  style: TextStyle(color: t.inkFaint, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Sleep row
          Row(
            children: [
              Icon(Icons.bedtime_outlined, size: 16, color: t.inkMuted),
              const SizedBox(width: 8),
              Text('Sleep', style: TextStyle(color: t.inkMuted, fontSize: 14)),
              const Spacer(),
              Text(
                widget.state.formattedSleepDuration,
                style: TextStyle(
                  color: widget.state.formattedSleepDuration != '—'
                      ? t.ink
                      : t.inkMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Next Move card ─────────────────────────────────────────────────────────

  Widget _buildNextMoveCard(Map<String, dynamic> dayView, ZenThemeTokens t) {
    final progress = _asMap(dayView['progress']) ?? {};
    final nextAction = _asMap(progress['next_action']);
    final alerts = (progress['alerts'] as List?) ?? [];

    final text = (nextAction?['text'] as String?) ??
        (alerts.isNotEmpty ? alerts[0]['text'] as String? : null) ??
        '';

    if (text.isEmpty) return const SizedBox.shrink();

    final metric = nextAction?['metric'] as String? ?? '';
    final status = _metricStatus(progress, metric);
    final tokens = t.statusTokens(status);
    final extraCount = alerts.length > 1 ? alerts.length - 1 : 0;

    return Container(
      decoration: BoxDecoration(
        color: tokens.tint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.fill.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left accent bar
          Container(
            width: 3,
            height: null,
            decoration: BoxDecoration(
              color: tokens.fill,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEXT MOVE',
                    style: TextStyle(
                      color: tokens.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    text,
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (extraCount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$extraCount more ▸',
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Entries ────────────────────────────────────────────────────────────────

  Widget _buildEntriesSection(
    Map<String, dynamic> dayView,
    ZenState state, {
    required bool editable,
    required ZenThemeTokens t,
  }) {
    final logs = (dayView['logs'] as List?) ?? [];

    if (logs.isEmpty && dayView['mode'] == 'today') {
      return _EmptyEntriesState(t: t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ENTRIES',
          style: TextStyle(
            color: t.inkFaint,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        ...logs.reversed.map((log) => _EntryRow(
          log: _asMap(log) ?? {},
          state: state,
          editable: editable,
          t: t,
          onEdit: (id, text) => _showEditDialog(id, text, state),
          onDelete: (id) => _confirmDelete(id, state),
          onRepeat: _handleRepeatLog,
          onChangeTime: _handleChangeLogTime,
          onSaveAsFavorite: _handleSaveAsFavorite,
        )).toList(),
      ],
    );
  }

  // ── Score ring (past) ──────────────────────────────────────────────────────

  Widget _buildScoreRing(Map<String, dynamic> dayView, ZenThemeTokens t) {
    final score = dayView['score'] as int?;
    final rating = (dayView['rating'] as String?) ?? 'insufficient_data';
    final tokens = t.statusTokens(rating);

    return _ZenCard(
      t: t,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score != null ? score / 100 : 0.1,
                  strokeWidth: 6,
                  backgroundColor: t.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.fill),
                ),
                Text(
                  score != null ? '$score' : '—',
                  style: GoogleFonts.fraunces(
                    fontSize: score != null ? 26 : 22,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusChip(status: rating, t: t),
              const SizedBox(height: 6),
              Text('Day score', style: TextStyle(color: t.inkMuted, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Verdict note (past) ────────────────────────────────────────────────────

  Widget _buildVerdictNote(Map<String, dynamic> dayView, ZenState state, ZenThemeTokens t) {
    final verdictStatus = (dayView['verdict_status'] as String?) ?? 'none';
    final verdict = _asMap(dayView['verdict']);
    final ai = _asMap(verdict?['ai']);

    if (verdictStatus == 'pending') {
      return _ZenCard(
        t: t,
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.inkMuted)),
            const SizedBox(width: 12),
            Text('Writing your review…', style: TextStyle(color: t.inkMuted, fontSize: 14)),
          ],
        ),
      );
    }

    if (ai == null) {
      return _ZenCard(
        t: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No review yet', style: TextStyle(color: t.inkMuted, fontSize: 14)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => state.analyzeDay(state.selectedDate),
              child: Text(
                'Generate review',
                style: TextStyle(
                  color: t.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final headline = ai['headline'] as String? ?? '';
    final summary = ai['verdict_summary'] as String? ?? '';
    final wentWell = ((ai['went_well'] as List?) ?? []).cast<String>();
    final hurt = ((ai['hurt_the_goal'] as List?) ?? []).cast<String>();
    final fixes = ((ai['fixes_for_tomorrow'] as List?) ?? []).cast<String>();
    final rating = (dayView['rating'] as String?) ?? '';

    final tokens = t.statusTokens(rating);
    final dataChanged = dayView['data_changed_since_review'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dataChanged) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.accent.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.sync_problem_rounded, size: 18, color: t.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Data changed since last review',
                    style: TextStyle(color: t.ink, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton(
                  onPressed: () => state.analyzeDay(state.selectedDate),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Update review',
                    style: TextStyle(color: t.accent, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
        // Headline card
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: tokens.fill,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: t.accent),
                          const SizedBox(width: 6),
                          Text('DAY REVIEW', style: TextStyle(color: t.inkFaint, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                          const Spacer(),
                          _StatusChip(status: rating, t: t),
                        ],
                      ),
                      if (headline.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          headline,
                          style: GoogleFonts.fraunces(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: t.ink,
                          ),
                        ),
                      ],
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(summary, style: TextStyle(color: t.inkMuted, fontSize: 14, height: 1.5)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (wentWell.isNotEmpty) ...[
          const SizedBox(height: 10),
          _VerdictSection(title: 'WENT WELL', items: wentWell, fillColor: t.successFill, tintColor: t.successTint, textColor: t.successText, t: t),
        ],
        if (hurt.isNotEmpty) ...[
          const SizedBox(height: 10),
          _VerdictSection(title: 'HURT THE GOAL', items: hurt, fillColor: t.dangerFill, tintColor: t.dangerTint, textColor: t.dangerText, t: t),
        ],
        if (fixes.isNotEmpty) ...[
          const SizedBox(height: 10),
          _VerdictSection(title: 'FIXES FOR TOMORROW', items: fixes, fillColor: t.warnFill, tintColor: t.warnTint, textColor: t.warnText, t: t),
        ],
      ],
    );
  }

  // ── Daily Quote Banner (Today / Past) ────────────────────────────────────

  Widget _buildDailyQuoteBanner(ZenState state, Map<String, dynamic> dayView, ZenThemeTokens t) {
    final quoteObj = state.currentDailyQuote;
    final quoteMap = _asMap(dayView['quote']);
    final quoteText = quoteObj?.quote ?? quoteMap?['quote'] as String?;
    final quoteAuthor = quoteObj?.author ?? quoteMap?['author'] as String?;

    if (quoteText == null || quoteText.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: t.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Icon(Icons.format_quote_rounded, size: 20, color: t.accent),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '“$quoteText”',
                    style: GoogleFonts.fraunces(
                      color: t.ink,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      height: 1.45,
                    ),
                  ),
                  if (quoteAuthor != null && quoteAuthor.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      '— $quoteAuthor',
                      style: TextStyle(
                        color: t.inkMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Motivation hero (future) ───────────────────────────────────────────────

  Widget _buildMotivationHero(Map<String, dynamic> dayView, ZenThemeTokens t) {
    final motivation = _asMap(dayView['motivation']) ?? {};
    final headline = motivation['headline'] as String? ?? 'Plan ahead';
    final tone = motivation['tone'] as String? ?? 'steady';

    final quoteObj = _asMap(dayView['quote']);
    final quoteText = quoteObj?['quote'] as String? ?? motivation['quote'] as String?;
    final quoteAuthor = quoteObj?['author'] as String? ?? motivation['author'] as String?;
    final fallbackMessage = motivation['message'] as String? ?? '';

    final bgColor = tone == 'push'
        ? t.warnTint
        : tone == 'celebrate'
            ? t.successTint
            : t.surfaceAlt;
    final accentColor = tone == 'push'
        ? t.warnFill
        : tone == 'celebrate'
            ? t.successFill
            : t.inkFaint;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote_rounded, size: 18, color: accentColor),
              const SizedBox(width: 6),
              Text(
                'DAILY MOTIVATION',
                style: TextStyle(
                  color: t.inkFaint,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            headline,
            style: GoogleFonts.fraunces(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: t.ink,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          if (quoteText != null && quoteText.isNotEmpty) ...[
            Text(
              '“$quoteText”',
              style: GoogleFonts.fraunces(
                color: t.ink,
                fontSize: 15,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
            if (quoteAuthor != null && quoteAuthor.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '— $quoteAuthor',
                style: TextStyle(
                  color: t.inkMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ] else if (fallbackMessage.isNotEmpty) ...[
            Text(fallbackMessage, style: TextStyle(color: t.inkMuted, fontSize: 14, height: 1.5)),
          ],
          Container(width: 32, height: 2, color: accentColor, margin: const EdgeInsets.only(top: 14)),
        ],
      ),
    );
  }

  Widget _buildFocusCard(Map<String, dynamic> dayView, ZenThemeTokens t) {
    final motivation = _asMap(dayView['motivation']) ?? {};
    final focusPoints = ((motivation['focus_points'] as List?) ?? []).cast<String>();
    final targets = _asMap(dayView['targets']) ?? {};
    final protein = targets['protein_g'];
    final water = targets['water_ml'];
    final calories = targets['calories_kcal'];

    return _ZenCard(
      t: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (focusPoints.isNotEmpty) ...[
            Text('FOCUS', style: TextStyle(color: t.inkFaint, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            ...focusPoints.map((fp) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('○ ', style: TextStyle(color: t.inkMuted, fontSize: 15)),
                  Expanded(child: Text(fp, style: TextStyle(color: t.ink, fontSize: 14, height: 1.4))),
                ],
              ),
            )),
            const SizedBox(height: 14),
            const _HairlineDivider(),
            const SizedBox(height: 14),
          ],
          Text('PLAN FOR THE DAY', style: TextStyle(color: t.inkFaint, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          const SizedBox(height: 10),
          if (protein != null) _TargetDetailRow(label: 'Protein', value: '${protein}g', t: t),
          if (water != null) _TargetDetailRow(label: 'Water', value: '${water}ml', t: t),
          if (calories != null) _TargetDetailRow(label: 'Calories', value: '${calories} kcal', t: t),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.line),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: t.inkFaint),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'You can write this day when it arrives.',
                  style: TextStyle(color: t.inkMuted, fontSize: 13),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty past ─────────────────────────────────────────────────────────────

  Widget _buildEmptyPast(ZenState state, ZenThemeTokens t) {
    final d = DateTime.tryParse(state.selectedDate) ?? DateTime.now();
    final weekday = _weekdayFull(d.weekday);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Text(
          'Nothing written for $weekday.',
          textAlign: TextAlign.center,
          style: GoogleFonts.fraunces(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'You can add entries for up to 14 days back.',
          textAlign: TextAlign.center,
          style: TextStyle(color: t.inkMuted, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: 200,
          child: ElevatedButton(
            onPressed: () {
              // Scroll down to composer or focus it
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: t.ink,
              foregroundColor: t.onInk,
              minimumSize: const Size(0, 48),
            ),
            child: const Text('Write an entry'),
          ),
        ),
      ],
    );
  }

  // ── Analyze card ───────────────────────────────────────────────────────────

  Widget _buildAnalyzeCard(Map<String, dynamic> dayView, ZenState state, ZenThemeTokens t) {
    final verdictStatus = (dayView['verdict_status'] as String?) ?? 'none';
    final hasVerdict = (dayView['verdict'] as Map?)?['ai'] != null;
    final isBusy = state.isAnalyzing || verdictStatus == 'pending';

    if (isBusy) {
      return _ZenCard(
        t: t,
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analyzing your day…',
                    style: TextStyle(color: t.ink, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Synthesizing your workout, nutrition & habits…',
                    style: TextStyle(color: t.inkMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return _ZenCard(
      t: t,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasVerdict ? 'Update day review' : 'Review my day so far',
                  style: TextStyle(color: t.ink, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  hasVerdict ? 'Re-run analysis with your latest entries' : 'Get a quick read on today',
                  style: TextStyle(color: t.inkMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () async {
              final today = state.logicalToday ?? state.selectedDate;
              if (state.selectedDate == today) {
                await state.handleNightSubmit(context);
              } else {
                final err = await state.analyzeDay(state.selectedDate);
                if (err != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(err),
                      backgroundColor: t.dangerFill,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: t.ink,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: t.onInk),
                  const SizedBox(width: 6),
                  Text(
                    hasVerdict ? 'Re-analyze' : 'Analyze',
                    style: TextStyle(color: t.onInk, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Composer dock ──────────────────────────────────────────────────────────

  Widget _buildComposerDock(ZenState state, ZenThemeTokens t) {
    final mode = (state.currentDayView?['mode'] as String?) ?? 'today';
    final isPast = mode == 'past';

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line, width: 1)),
        boxShadow: [
          BoxShadow(
            color: t.ink.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPast) _buildPastDayComposerBanner(state, t),
              _buildFavoritesChipRow(state, t),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _showCameraActionSheet,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.line),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.camera_alt_outlined,
                          size: 20,
                          color: t.ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      constraints: BoxConstraints(
                        minHeight: 44,
                        maxHeight: _composerExpanded ? 140 : 56,
                      ),
                      decoration: BoxDecoration(
                        color: t.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _composerFocus.hasFocus ? t.ink : t.line,
                          width: _composerFocus.hasFocus ? 1.5 : 1,
                        ),
                      ),
                      child: TextField(
                        controller: _logController,
                        focusNode: _composerFocus,
                        maxLines: null,
                        minLines: 1,
                        maxLength: 1000,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(color: t.ink, fontSize: 15, height: 1.4),
                        decoration: InputDecoration(
                          hintText: isPast ? 'What did you eat, do or feel that day?…' : 'Write what you ate, did or felt…',
                          hintStyle: TextStyle(color: t.inkFaint, fontSize: 15),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          counterText: '',
                        ),
                        onTap: () => setState(() => _composerExpanded = true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _logController.text.trim().isEmpty || _isSending ? null : _send,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _logController.text.trim().isEmpty || _isSending ? t.surfaceAlt : t.ink,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.line),
                      ),
                      child: Center(
                        child: _isSending
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: t.onInk),
                              )
                            : Icon(
                                Icons.arrow_upward_rounded,
                                size: 20,
                                color: _logController.text.trim().isEmpty ? t.inkFaint : t.onInk,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCameraActionSheet() async {
    final t = context.zen;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Camera & Food Scans',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: t.successTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.lunch_dining_rounded, color: t.successText, size: 20),
                ),
                title: Text(
                  'Meal Photo Log',
                  style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600, color: t.ink),
                ),
                subtitle: Text(
                  'Photograph your plate · AI estimates items & macros',
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _handlePhotoMealCapture();
                },
              ),
              const Divider(height: 12),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: t.infoTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.qr_code_scanner_rounded, color: t.infoText, size: 20),
                ),
                title: Text(
                  'Packaged Food Label Scanner',
                  style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600, color: t.ink),
                ),
                subtitle: Text(
                  'Scan nutrition facts · 0-100 rating & day impact',
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  LabelScanScreen.push(context, widget.state);
                },
              ),
              const Divider(height: 12),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: t.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.bookmark_added_rounded, color: t.accent, size: 20),
                ),
                title: Text(
                  'My Saved Products',
                  style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600, color: t.ink),
                ),
                subtitle: Text(
                  'Browse and log your saved packaged foods',
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  MyProductsScreen.push(context, widget.state);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handlePhotoMealCapture() async {
    final picker = ImagePicker();
    final t = context.zen;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Capture Plate Photo', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink)),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: t.ink),
              title: const Text('Take photo with camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: t.ink),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await picker.pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 85);
    if (picked == null) return;

    final imageFile = File(picked.path);

    // Show analyzing dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: t.surface,
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Analyzing meal with AI…',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink),
              ),
            ),
          ],
        ),
      ),
    );

    final res = await ApiService().analyzeMealPhoto(imageFile);
    if (!mounted) return;
    Navigator.pop(context); // close analyzing dialog

    if (res.ok && res.data != null) {
      PhotoMealReviewSheet.show(
        context,
        state: widget.state,
        imageFile: imageFile,
        draftData: res.data!,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.error ?? 'Could not analyze photo. Please try again.'),
          backgroundColor: t.dangerFill,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildPastDayComposerBanner(ZenState state, ZenThemeTokens t) {
    final d = DateTime.tryParse(state.selectedDate) ?? DateTime.now();
    final dayLabel = '${_weekdayFull(d.weekday).substring(0, 3)}, ${d.day} ${_monthFull(d.month).substring(0, 3)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 14, color: t.accent),
              const SizedBox(width: 6),
              Text(
                'Logging to $dayLabel',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: t.ink),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildMealChip('Breakfast (08:30)', 'Breakfast', t),
                const SizedBox(width: 6),
                _buildMealChip('Lunch (13:00)', 'Lunch', t),
                const SizedBox(width: 6),
                _buildMealChip('Dinner (20:30)', 'Dinner', t),
                const SizedBox(width: 6),
                _buildCustomMealChip(t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealChip(String label, String key, ZenThemeTokens t) {
    final isSelected = _selectedPastMealPreset == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedPastMealPreset = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? t.ink : t.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? t.ink : t.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? t.onInk : t.inkMuted,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomMealChip(ZenThemeTokens t) {
    final isSelected = _selectedPastMealPreset == 'Custom';
    final tod = _customTimeOfDay;
    String label = 'Custom';
    if (tod != null) {
      final hourStr = tod.hour.toString().padLeft(2, '0');
      final minStr = tod.minute.toString().padLeft(2, '0');
      final afterMidnight = tod.hour < 4 ? ' (after midnight)' : '';
      label = '$hourStr:$minStr$afterMidnight';
    }

    return GestureDetector(
      onTap: () async {
        final initialTime = _customTimeOfDay ?? const TimeOfDay(hour: 12, minute: 0);
        final picked = await showTimePicker(
          context: context,
          initialTime: initialTime,
        );
        if (picked != null) {
          setState(() {
            _customTimeOfDay = picked;
            _selectedPastMealPreset = 'Custom';
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? t.ink : t.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? t.ink : t.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.access_time_rounded,
              size: 12,
              color: isSelected ? t.onInk : t.inkMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? t.onInk : t.inkMuted,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error / skeleton ───────────────────────────────────────────────────────

  Widget _buildSkeleton(ZenThemeTokens t) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _SkeletonBlock(t: t, height: 160),
          const SizedBox(height: 12),
          _SkeletonBlock(t: t, height: 80),
          const SizedBox(height: 20),
          _SkeletonBlock(t: t, height: 60),
          const SizedBox(height: 10),
          _SkeletonBlock(t: t, height: 60),
        ],
      ),
    );
  }

  Widget _buildError(ZenState state, ZenThemeTokens t) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_outlined, size: 48, color: t.inkFaint),
          const SizedBox(height: 16),
          Text("Couldn't load this day.", style: TextStyle(color: t.ink, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Check your connection and try again.', style: TextStyle(color: t.inkMuted, fontSize: 14)),
          const SizedBox(height: 20),
          SizedBox(
            width: 140,
            child: OutlinedButton(
              onPressed: () => state.loadDayView(state.selectedDate),
              child: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showEditDialog(String id, String text, ZenState state) {
    final ctrl = TextEditingController(text: text);
    showDialog(
      context: context,
      builder: (_) {
        final t = context.zen;
        return AlertDialog(
          title: const Text('Edit entry'),
          content: TextField(
            controller: ctrl,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'What happened?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                state.editLog(id, ctrl.text);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: t.ink,
                foregroundColor: t.onInk,
                minimumSize: const Size(0, 44),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(String id, ZenState state) {
    final t = context.zen;
    // Use snackbar with undo per spec P04
    state.deleteLog(id).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Entry deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                // TODO: implement undo (requires backend support)
              },
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: t.ink,
          ),
        );
      }
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _initials(String? name) {
    if (name == null || name.isEmpty) return 'Z';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  String _weekdayFull(int d) => const ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][d - 1];
  String _monthFull(int m) => const ['January','February','March','April','May','June','July','August','September','October','November','December'][m - 1];
  String _dayLetter(int d) => const ['M','T','W','T','F','S','S'][d - 1];

  String _worstStatus(List<String> statuses) {
    const order = ['far_behind', 'over', 'impossible', 'behind', 'on_track', 'ahead', 'met'];
    for (final s in order) {
      if (statuses.contains(s)) return s;
    }
    return statuses.isNotEmpty ? statuses.first : 'on_track';
  }

  String _metricStatus(Map<String, dynamic> progress, String metric) {
    return (progress[metric] as Map?)?['status'] as String? ?? 'on_track';
  }
}

// ─── Shared Widgets ─────────────────────────────────────────────────────────

class _ZenCard extends StatelessWidget {
  final Widget child;
  final ZenThemeTokens t;

  const _ZenCard({required this.child, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line, width: 1),
      ),
      child: child,
    );
  }
}

class _HairlineDivider extends StatelessWidget {
  const _HairlineDivider();

  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    return Container(height: 1, color: t.line);
  }
}

class _TodayPill extends StatelessWidget {
  final ZenThemeTokens t;
  const _TodayPill({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Today',
        style: TextStyle(color: t.onAccent, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final String mode;
  final ZenThemeTokens t;
  const _ModeBadge({required this.mode, required this.t});

  @override
  Widget build(BuildContext context) {
    final label = switch (mode) {
      'past' => 'Reviewed',
      'future' => 'Planned',
      _ => '',
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.line),
      ),
      child: Text(label, style: TextStyle(color: t.inkMuted, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final ZenThemeTokens t;
  const _StatusChip({required this.status, required this.t});

  @override
  Widget build(BuildContext context) {
    final tokens = t.statusTokens(status);
    final label = switch (status) {
      'met' || 'good'        => 'Targets met',
      'on_track' || 'ahead'  => 'On pace',
      'behind' || 'ok'       => 'Behind',
      'far_behind'           => 'Falling short',
      'over'                 => 'Over',
      'poor'                 => 'Poor',
      'impossible'           => 'Can\'t reach',
      _                      => 'No data',
    };
    final icon = switch (status) {
      'met' || 'good'        => Icons.check_circle_outline,
      'on_track' || 'ahead'  => Icons.trending_up_rounded,
      'behind' || 'ok'       => Icons.radio_button_unchecked,
      'far_behind' || 'over' || 'poor' || 'impossible' => Icons.warning_amber_rounded,
      _                      => Icons.remove_circle_outline,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.tint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.fill.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tokens.text),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: tokens.text, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ReadingChip extends StatelessWidget {
  final ZenThemeTokens t;
  const _ReadingChip({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: t.inkMuted),
          ),
          const SizedBox(width: 6),
          Text('Reading…', style: TextStyle(color: t.inkMuted, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _PaceRow extends StatelessWidget {
  final String label;
  final double actual;
  final double target;
  final String unit;
  final String status;
  final double? expectedPct;
  final ZenThemeTokens t;
  final Widget? trailingAction;

  const _PaceRow({
    required this.label,
    required this.actual,
    required this.target,
    required this.unit,
    required this.status,
    this.expectedPct,
    required this.t,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    final pct = target > 0 ? (actual / target).clamp(0.0, 1.0) : 0.0;
    final expFrac = expectedPct != null ? (expectedPct! / 100).clamp(0.0, 1.0) : null;
    final tokens = t.statusTokens(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: t.inkMuted, fontSize: 14)),
            if (trailingAction != null) ...[
              const SizedBox(width: 8),
              trailingAction!,
            ],
            const Spacer(),
            Text(
              '${actual.toStringAsFixed(0)} / ${target.toStringAsFixed(0)} $unit',
              style: TextStyle(
                color: t.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (ctx, constraints) {
          return SizedBox(
            height: 10,
            child: Stack(
              children: [
                // Track
                Container(
                  decoration: BoxDecoration(
                    color: t.surfaceAlt,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: t.line, width: 0.5),
                  ),
                ),
                // Fill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  width: constraints.maxWidth * pct,
                  decoration: BoxDecoration(
                    color: tokens.fill,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                // Expected-by-now tick
                if (expFrac != null && expFrac > pct)
                  Positioned(
                    left: constraints.maxWidth * expFrac - 1,
                    child: Container(
                      width: 2,
                      height: 10,
                      color: tokens.fill.withValues(alpha: 0.5),
                    ),
                  ),
                // Hatch between fill and expected tick
                if (expFrac != null && expFrac > pct)
                  Positioned(
                    left: constraints.maxWidth * pct,
                    width: constraints.maxWidth * (expFrac - pct),
                    child: Container(
                      height: 10,
                      color: tokens.tint,
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  final Map<String, dynamic> log;
  final ZenState state;
  final bool editable;
  final ZenThemeTokens t;
  final void Function(String id, String text) onEdit;
  final void Function(String id) onDelete;
  final void Function(String id)? onRepeat;
  final void Function(String id, String currentDay)? onChangeTime;
  final void Function(String id, String text)? onSaveAsFavorite;

  const _EntryRow({
    required this.log,
    required this.state,
    required this.editable,
    required this.t,
    required this.onEdit,
    required this.onDelete,
    this.onRepeat,
    this.onChangeTime,
    this.onSaveAsFavorite,
  });

  @override
  Widget build(BuildContext context) {
    // ── Sync state (offline-first §8.1) ──────────────────────────────────────
    final syncState = (log['sync_state'] as String?);     // queued | syncing | failed | synced | null
    final isQueued  = syncState == 'queued';
    final isSyncing = syncState == 'syncing';
    final isFailed  = syncState == 'failed';
    final editPending = log['edit_pending'] == true;
    final failReason  = log['fail_reason'] as String?;

    // ── Extraction state (server-side) ───────────────────────────────────────
    final extractionStatus = (log['extraction_status'] as String?) ?? 'done';
    final extracted = _asMap(log['extracted']);
    final overrides = _asMap(log['overrides']) ?? {};
    final id   = log['id'] as String? ?? log['client_id'] as String? ?? '';
    final text = log['text'] as String? ?? '';
    final time = log['time_display'] as String? ?? '';

    // Nutrition chips (only for synced+done entries)
    final nutrition = _asMap(extracted?['nutrition']);
    final proteinG = overrides['protein_g'] ?? nutrition?['protein_g'];
    final calKcal  = overrides['calories_kcal'] ?? nutrition?['calories_kcal'];
    final hydraML  = overrides['hydration_ml'] ?? extracted?['hydration_ml'];
    final workout  = _asMap(extracted?['workout']);
    final goalAlignment = _asMap(extracted?['goal_alignment'])?['rating'] as String?;

    // ── Left edge bar colour ──────────────────────────────────────────────────
    Color edgeColor;
    if (isQueued || isSyncing) {
      edgeColor = t.inkFaint;
    } else if (isFailed) {
      edgeColor = t.dangerFill;
    } else if (goalAlignment == 'good') {
      edgeColor = t.successFill;
    } else if (goalAlignment == 'poor') {
      edgeColor = t.dangerFill;
    } else if (goalAlignment == 'neutral') {
      edgeColor = t.inkFaint;
    } else {
      edgeColor = Colors.transparent;
    }

    // ── Background tint ───────────────────────────────────────────────────────
    final bgColor = isFailed ? t.dangerTint : t.surface;

    // ── Border style (dashed for queued) ─────────────────────────────────────
    // Flutter doesn't support dashed borders natively; simulate with a lighter
    // border colour for queued entries to give a "muted / waiting" feel.
    final borderColor = (isQueued || isSyncing) ? t.inkFaint.withValues(alpha: 0.35) : (isFailed ? t.dangerFill.withValues(alpha: 0.4) : t.line);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left edge bar ────────────────────────────────────────────────────
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: edgeColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Time row + actions ──────────────────────────────────────
                  Row(
                    children: [
                      Text(time, style: TextStyle(color: t.inkFaint, fontSize: 12, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      // For failed entries always show edit/delete
                      if (editable || isFailed) ...[
                        if (onRepeat != null && id.isNotEmpty) ...[
                          _IconButton(
                            icon: Icons.repeat_rounded,
                            color: t.inkFaint,
                            onTap: () => onRepeat!(id),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (onSaveAsFavorite != null && id.isNotEmpty) ...[
                          _IconButton(
                            icon: Icons.bookmark_add_outlined,
                            color: t.inkFaint,
                            onTap: () => onSaveAsFavorite!(id, text),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (onChangeTime != null && id.isNotEmpty) ...[
                          _IconButton(
                            icon: Icons.schedule_rounded,
                            color: t.inkFaint,
                            onTap: () => onChangeTime!(id, log['date'] as String? ?? state.selectedDate),
                          ),
                          const SizedBox(width: 4),
                        ],
                        _IconButton(
                          icon: Icons.edit_outlined,
                          color: t.inkFaint,
                          onTap: () => onEdit(id, text),
                        ),
                        const SizedBox(width: 4),
                        _IconButton(
                          icon: Icons.delete_outline,
                          color: t.dangerFill,
                          onTap: () => onDelete(id),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(text, style: TextStyle(color: t.ink, fontSize: 14, height: 1.45)),

                  // ── §8.1 — Queued state ──────────────────────────────────────
                  if (isQueued) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _SyncChip(
                          icon: Icons.cloud_off_rounded,
                          label: 'Queued',
                          t: t,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Saved on this phone · syncs automatically',
                      style: TextStyle(color: t.inkFaint, fontSize: 11),
                    ),
                  ]
                  // ── §8.1 — Syncing state ─────────────────────────────────────
                  else if (isSyncing) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _SyncChip(
                          spinner: true,
                          label: 'Syncing…',
                          t: t,
                        ),
                      ],
                    ),
                  ]
                  // ── §8.1 — Failed state ──────────────────────────────────────
                  else if (isFailed) ...[
                    const SizedBox(height: 8),
                    Text(
                      "Couldn't sync${failReason != null ? ': $failReason' : ''}",
                      style: TextStyle(color: t.dangerText, fontSize: 12, height: 1.3),
                    ),
                  ]
                  // ── §8.1 — Edit queued on a synced entry ─────────────────────
                  else if (editPending) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _SyncChip(
                          icon: Icons.edit_note_rounded,
                          label: 'Edit queued',
                          t: t,
                        ),
                      ],
                    ),
                    // Show old extraction values dimmed / labelled
                    if (proteinG != null || calKcal != null || hydraML != null || workout != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (proteinG != null) _ExtractionChip(
                            label: '${(proteinG as num).toStringAsFixed(0)} g protein (old)',
                            bgColor: t.surfaceAlt,
                            textColor: t.inkFaint,
                          ),
                          if (calKcal != null) _ExtractionChip(
                            label: '${(calKcal as num).toStringAsFixed(0)} kcal (old)',
                            bgColor: t.surfaceAlt,
                            textColor: t.inkFaint,
                          ),
                          if (hydraML != null) _ExtractionChip(
                            label: '${(hydraML as num).toStringAsFixed(0)} ml (old)',
                            bgColor: t.surfaceAlt,
                            textColor: t.inkFaint,
                          ),
                          if (workout != null) _ExtractionChip(
                            label: '${workout['type'] ?? 'Workout'} (old)',
                            bgColor: t.surfaceAlt,
                            textColor: t.inkFaint,
                          ),
                        ],
                      ),
                    ],
                  ]
                  // ── Normal server-side extraction states ─────────────────────
                  else if (extractionStatus == 'pending') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: t.inkFaint)),
                        const SizedBox(width: 8),
                        Text('Reading…', style: TextStyle(color: t.inkFaint, fontSize: 12)),
                      ],
                    ),
                  ] else if (extractionStatus == 'failed') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: t.dangerFill, size: 14),
                        const SizedBox(width: 6),
                        Text("Couldn't read this", style: TextStyle(color: t.dangerText, fontSize: 12)),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => state.retryLog(id),
                          child: Text('Retry', style: TextStyle(color: t.ink, fontSize: 12, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                  ] else if (extractionStatus == 'done') ...[
                    if (proteinG != null || calKcal != null || hydraML != null || workout != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (proteinG != null) _ExtractionChip(
                            label: '+${(proteinG as num).toStringAsFixed(0)} g protein',
                            bgColor: t.successTint,
                            textColor: t.successText,
                          ),
                          if (calKcal != null) _ExtractionChip(
                            label: '${(calKcal as num).toStringAsFixed(0)} kcal',
                            bgColor: t.surfaceAlt,
                            textColor: t.inkMuted,
                          ),
                          if (hydraML != null) _ExtractionChip(
                            label: '${(hydraML as num).toStringAsFixed(0)} ml',
                            bgColor: t.infoTint,
                            textColor: t.infoText,
                          ),
                          if (workout != null) _ExtractionChip(
                            label: '${workout['type'] ?? 'Workout'}${workout['duration_mins'] != null ? ' · ${workout['duration_mins']} min' : ''}',
                            bgColor: t.surfaceAlt,
                            textColor: t.inkMuted,
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sync state chip (§8.1) ──────────────────────────────────────────────────

class _SyncChip extends StatelessWidget {
  final IconData? icon;
  final bool spinner;
  final String label;
  final ZenThemeTokens t;

  const _SyncChip({
    this.icon,
    this.spinner = false,
    required this.label,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: t.inkMuted),
            )
          else if (icon != null)
            Icon(icon, size: 12, color: t.inkMuted),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: t.inkMuted, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ExtractionChip extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;

  const _ExtractionChip({required this.label, required this.bgColor, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.line, width: 0.5),
      ),
      child: Text(label, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _VerdictSection extends StatelessWidget {
  final String title;
  final List<String> items;
  final Color fillColor;
  final Color tintColor;
  final Color textColor;
  final ZenThemeTokens t;

  const _VerdictSection({
    required this.title,
    required this.items,
    required this.fillColor,
    required this.tintColor,
    required this.textColor,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tintColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fillColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('· $item', style: TextStyle(color: t.ink, fontSize: 13, height: 1.4)),
          )),
        ],
      ),
    );
  }
}

class _TargetDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final ZenThemeTokens t;

  const _TargetDetailRow({required this.label, required this.value, required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: t.inkMuted, fontSize: 14)),
          const Spacer(),
          Text(value, style: TextStyle(color: t.ink, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _EmptyEntriesState extends StatelessWidget {
  final ZenThemeTokens t;
  const _EmptyEntriesState({required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          'Nothing here yet. Write your first line below.',
          textAlign: TextAlign.center,
          style: TextStyle(color: t.inkFaint, fontSize: 14, height: 1.5),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _IconButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final ZenThemeTokens t;
  final double height;

  const _SkeletonBlock({required this.t, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
    );
  }
}
