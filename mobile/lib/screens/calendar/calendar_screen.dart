import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/zen_colors.dart';
import '../../services/api_service.dart';
import '../../services/quote_storage.dart';
import '../../services/sleep_wake_storage.dart';
import '../../state/zen_state.dart';


// ZenLog v3 §6.8 – Days (calendar) screen
// Ink & Paper design: month grid, day summary card, "Open day" navigation.
// All data from /api/calendar and /api/days/{date}/view.

class CalendarScreen extends StatefulWidget {
  final ZenState state;
  final VoidCallback? onBack;

  const CalendarScreen({
    super.key,
    required this.state,
    this.onBack,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final ApiService _api = ApiService();
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay;
  Map<String, dynamic>? _selectedDayView;
  Map<String, Map<String, dynamic>> _calendarData = {};
  bool _calendarLoading = false;
  bool _dayViewLoading = false;

  @override
  void initState() {
    super.initState();
    // Select today by default
    _selectedDay = DateTime.now();
    _loadCalendarMonth(_focusedMonth);
  }

  Future<void> _loadCalendarMonth(DateTime month) async {
    setState(() => _calendarLoading = true);
    final from = DateTime(month.year, month.month, 1);
    final to = DateTime(month.year, month.month + 1, 0);
    final data = await _api.getCalendar(_dateStr(from), _dateStr(to));
    final map = <String, Map<String, dynamic>>{};
    for (final d in data) {
      if (d['date'] != null) map[d['date'] as String] = d;
    }
    if (mounted) {
      setState(() {
        _calendarData = {..._calendarData, ...map};
        _calendarLoading = false;
      });
      // Load day view for selected day
      if (_selectedDay != null) _selectDay(_selectedDay!);
    }
  }

  Future<void> _selectDay(DateTime day) async {
    setState(() {
      _selectedDay = day;
      _selectedDayView = null;
      _dayViewLoading = true;
    });
    final data = await _api.getDayView(_dateStr(day));
    if (mounted) {
      setState(() {
        _selectedDayView = data;
        _dayViewLoading = false;
      });
    }
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<String> _getSleepDurationForDay(DateTime day) async {
    final wakeDate = _dateStr(day);
    final prev = day.subtract(const Duration(days: 1));
    final nightDate = _dateStr(prev);
    final dur = await SleepWakeStorage.calculateSleepDuration(
      wakeDate: wakeDate,
      nightDate: nightDate,
    );
    return SleepWakeStorage.formatDuration(dur);
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() => _focusedMonth = DateTime(now.year, now.month));
    _loadCalendarMonth(_focusedMonth);
    _selectDay(now);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Journal',
                    style: GoogleFonts.fraunces(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _goToToday,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: t.surfaceAlt,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: t.line),
                      ),
                      child: Text(
                        'Today',
                        style: TextStyle(color: t.ink, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Month nav ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _MonthNavButton(
                    icon: Icons.chevron_left_rounded,
                    t: t,
                    onTap: () {
                      final prev = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
                      setState(() => _focusedMonth = prev);
                      _loadCalendarMonth(prev);
                    },
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_monthFull(_focusedMonth.month)} ${_focusedMonth.year}',
                    style: TextStyle(color: t.ink, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 12),
                  _MonthNavButton(
                    icon: Icons.chevron_right_rounded,
                    t: t,
                    onTap: () {
                      final next = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
                      // Don't go into the future beyond current month
                      if (next.year > today.year || (next.year == today.year && next.month > today.month)) return;
                      setState(() => _focusedMonth = next);
                      _loadCalendarMonth(next);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Weekday headers ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) {
                  return Expanded(
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF9A9487), // inkFaint
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 8),

            // ── Calendar grid ──
            if (_calendarLoading)
              Container(
                height: 260,
                alignment: Alignment.center,
                child: CircularProgressIndicator(color: context.zen.ink, strokeWidth: 2),
              )
            else
              _buildGrid(today, t),

            const SizedBox(height: 8),

            // ── Legend ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildLegend(t),
            ),

            const SizedBox(height: 12),
            Container(height: 1, color: t.line),
            const SizedBox(height: 12),

            // ── Day summary card ──
            Expanded(
              child: _selectedDay == null
                  ? Center(child: Text('Tap a day to see details', style: TextStyle(color: t.inkFaint, fontSize: 14)))
                  : _dayViewLoading
                      ? Center(child: CircularProgressIndicator(color: t.ink, strokeWidth: 2))
                      : _selectedDayView == null
                          ? _buildErrorCard(t)
                          : _buildSummaryCard(_selectedDay!, _selectedDayView!, t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(DateTime today, ZenThemeTokens t) {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final startOffset = firstDay.weekday % 7; // 0 = Sunday
    final totalCells = ((startOffset + daysInMonth) / 7).ceil() * 7;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: 1.0,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: totalCells,
        itemBuilder: (ctx, i) {
          final dayNum = i - startOffset + 1;
          if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox();

          final d = DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
          final key = _dateStr(d);
          final calEntry = _calendarData[key];
          final rating = calEntry?['rating'] as String?;
          final hasEntries = (calEntry?['log_count'] as int? ?? 0) > 0;
          final isToday = _dateStr(d) == _dateStr(today);
          final isSelected = _selectedDay != null && _dateStr(_selectedDay!) == key;
          final isFuture = d.isAfter(today);
          final workoutDone = calEntry?['workout_done'] == true;

          return GestureDetector(
            onTap: () => _selectDay(d),
            child: _CalendarCell(
              day: dayNum,
              rating: rating,
              hasEntries: hasEntries,
              isToday: isToday,
              isSelected: isSelected,
              isFuture: isFuture,
              workoutDone: workoutDone,
              t: t,
            ),
          );
        },
      ),
    );
  }

  Widget _buildLegend(ZenThemeTokens t) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        _LegendItem(color: t.successFill, label: 'Good', t: t),
        _LegendItem(color: t.warnFill, label: 'OK', t: t),
        _LegendItem(color: t.dangerFill, label: 'Poor', t: t),
        _LegendItem(color: t.surfaceAlt, label: 'None', t: t, bordered: true),
      ],
    );
  }

  Widget _buildSummaryCard(DateTime day, Map<String, dynamic> dayView, ZenThemeTokens t) {
    final mode = dayView['mode'] as String? ?? '';
    final isToday = mode == 'today';
    final totals = (dayView['totals'] as Map?) ?? {};
    final targets = (dayView['targets'] as Map?) ?? {};
    final logs = (dayView['logs'] as List?) ?? [];
    final score = dayView['score'] as int?;
    final rating = dayView['rating'] as String?;

    final proteinActual = (totals['protein_g'] as num?)?.toDouble() ?? 0;
    final proteinTarget = (targets['protein_g'] as num?)?.toDouble() ?? 126;
    final waterActual = (totals['hydration_ml'] as num?)?.toDouble() ?? 0;
    final workoutDone = totals['workout_done'] == true;

    final dayName = _weekdayFull(day.weekday);
    final dateLabel = '$dayName, ${_monthFull(day.month).substring(0, 3)} ${day.day}';

    final tokens = rating != null ? t.statusTokens(rating) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(dateLabel, style: TextStyle(color: t.ink, fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(999)),
                    child: Text('Today', style: TextStyle(color: t.onAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                  )
                else if (score != null && tokens != null)
                  Row(
                    children: [
                      Text(
                        '$score',
                        style: GoogleFonts.fraunces(fontSize: 22, fontWeight: FontWeight.w600, color: t.ink),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tokens.tint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _ratingLabel(rating ?? ''),
                          style: TextStyle(color: tokens.text, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 14),

            // Stats
            Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                _MiniStat(label: 'Protein', value: '${proteinActual.toStringAsFixed(0)} / ${proteinTarget.toStringAsFixed(0)} g', t: t),
                _MiniStat(label: 'Water', value: '${waterActual.toStringAsFixed(0)} ml', t: t),
                _MiniStat(label: 'Workout', value: workoutDone ? 'Done' : 'None', t: t),
                FutureBuilder<String>(
                  future: _getSleepDurationForDay(day),
                  builder: (context, snapshot) {
                    final sleepStr = snapshot.data ?? '—';
                    return _MiniStat(label: 'Sleep', value: sleepStr, t: t);
                  },
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Entry count + preview
            Text(
              '${logs.length} entr${logs.length == 1 ? 'y' : 'ies'}',
              style: TextStyle(color: t.inkFaint, fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            ...logs.take(2).map((log) {
              final logMap = log is Map<String, dynamic>
                  ? log
                  : (log is Map ? Map<String, dynamic>.from(log) : <String, dynamic>{});
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '· ${logMap['text'] as String? ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.inkMuted, fontSize: 13, height: 1.4),
                ),
              );
            }).toList(),

            FutureBuilder<DailyQuote>(
              future: QuoteStorage.getOrFetchQuote(
                _dateStr(day),
                fetchRemote: (d) => ApiService().getDailyQuote(d),
              ),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final q = snapshot.data!;
                  return Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: t.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.format_quote_rounded, size: 14, color: t.accent),
                              const SizedBox(width: 4),
                              Text(
                                'DAILY QUOTE',
                                style: TextStyle(
                                  color: t.inkFaint,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '“${q.quote}”',
                            style: GoogleFonts.fraunces(
                              color: t.ink,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '— ${q.author}',
                            style: TextStyle(
                              color: t.inkMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            const SizedBox(height: 16),

            // Open day button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.state.setSelectedDate(_dateStr(day));
                  widget.onBack?.call(); // navigate to Today tab
                },
                child: const Text('Open day'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(ZenThemeTokens t) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: t.inkFaint, size: 32),
            const SizedBox(height: 12),
            Text("Couldn't load this day.", style: TextStyle(color: t.inkMuted, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  String _monthFull(int m) => const ['January','February','March','April','May','June','July','August','September','October','November','December'][m - 1];
  String _weekdayFull(int d) => const ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][d - 1];
  String _ratingLabel(String rating) => switch (rating) {
    'good' => 'Good',
    'ok' => 'OK',
    'poor' => 'Poor',
    _ => rating,
  };
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _CalendarCell extends StatelessWidget {
  final int day;
  final String? rating;
  final bool hasEntries;
  final bool isToday;
  final bool isSelected;
  final bool isFuture;
  final bool workoutDone;
  final ZenThemeTokens t;

  const _CalendarCell({
    required this.day,
    required this.rating,
    required this.hasEntries,
    required this.isToday,
    required this.isSelected,
    required this.isFuture,
    required this.workoutDone,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color textColor;
    BoxBorder? border;

    if (isSelected) {
      bg = t.ink;
      textColor = t.onInk;
      border = null;
    } else if (rating == 'good' && !isFuture) {
      bg = t.successTint;
      textColor = t.successText;
    } else if (rating == 'ok' && !isFuture) {
      bg = t.warnTint;
      textColor = t.warnText;
    } else if (rating == 'poor' && !isFuture) {
      bg = t.dangerTint;
      textColor = t.dangerText;
    } else if (isFuture) {
      bg = Colors.transparent;
      textColor = t.inkFaint;
      border = Border.all(color: t.line, width: 1);
    } else {
      bg = t.surface;
      textColor = hasEntries ? t.ink : t.inkFaint;
    }

    if (isToday && !isSelected) {
      border = Border.all(color: t.accent, width: 2);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: border,
          ),
          child: Center(
            child: Text(
              '$day',
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
        if (workoutDone && !isSelected)
          Positioned(
            top: 2,
            right: 3,
            child: Icon(Icons.fitness_center, size: 8, color: t.accent),
          ),
      ],
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  final IconData icon;
  final ZenThemeTokens t;
  final VoidCallback onTap;

  const _MonthNavButton({required this.icon, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.line),
        ),
        child: Icon(icon, size: 20, color: t.inkMuted),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final ZenThemeTokens t;
  final bool bordered;

  const _LegendItem({required this.color, required this.label, required this.t, this.bordered = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: bordered ? Border.all(color: t.line) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: t.inkMuted, fontSize: 11)),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final ZenThemeTokens t;

  const _MiniStat({required this.label, required this.value, required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: t.inkFaint, fontSize: 10, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: t.ink, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

