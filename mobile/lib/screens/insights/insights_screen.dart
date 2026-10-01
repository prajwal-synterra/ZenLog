import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/zen_colors.dart';
import '../../models/insight_model.dart';
import '../../services/api_service.dart';
import '../../services/sleep_wake_storage.dart';
import '../../state/zen_state.dart';

// ZenLog v3 §6.9 – Insights screen
// Fully wired to real API data. Chart only from daily[]. Never hardcoded.
// AI report locked if < 3 days logged.

class InsightsScreen extends StatefulWidget {
  final ZenState state;
  final VoidCallback? onBack;

  const InsightsScreen({
    super.key,
    required this.state,
    this.onBack,
  });

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final ApiService _api = ApiService();
  bool _isWeekly = true;
  InsightModel? _insight;
  Duration? _localAvgSleep;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchInsight();
  }

  Future<void> _fetchInsight() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sleepFuture = SleepWakeStorage.getAverageSleepDuration(daysCount: _isWeekly ? 7 : 30);
      final result = _isWeekly
          ? await _api.getWeeklyInsights()
          : await _api.getMonthlyInsights();
      final localSleep = await sleepFuture;
      if (mounted) {
        setState(() {
          _insight = result;
          _localAvgSleep = localSleep;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load insights.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;

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
                    'Insights',
                    style: GoogleFonts.fraunces(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  const Spacer(),
                  if (_insight != null)
                    GestureDetector(
                      onTap: _fetchInsight,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: t.surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.line),
                        ),
                        child: Icon(Icons.auto_awesome, size: 18, color: t.inkMuted),
                      ),
                    ),
                ],
              ),
            ),

            // ── Period toggle ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _PeriodToggle(
                    label: 'Week',
                    selected: _isWeekly,
                    t: t,
                    onTap: () {
                      if (!_isWeekly) {
                        setState(() => _isWeekly = true);
                        _fetchInsight();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _PeriodToggle(
                    label: 'Month',
                    selected: !_isWeekly,
                    t: t,
                    onTap: () {
                      if (_isWeekly) {
                        setState(() => _isWeekly = false);
                        _fetchInsight();
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Container(height: 1, color: t.line),

            // ── Body ──
            Expanded(
              child: _isLoading
                  ? _buildSkeleton(t)
                  : _error != null
                      ? _buildErrorState(t)
                      : RefreshIndicator(
                          color: t.ink,
                          backgroundColor: t.surface,
                          onRefresh: _fetchInsight,
                          child: _buildContent(t),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ZenThemeTokens t) {
    final insight = _insight;
    final stats = insight?.statsSummary ?? {};
    final daysLogged = (stats['days_logged'] as num?)?.toInt()
        ?? (stats['completed_days'] as num?)?.toInt()
        ?? 0;
    final avgProtein = (stats['average_protein_g'] as num?)?.toDouble();
    final adherence = (stats['protein_target_adherence_percent'] as num?)?.toDouble();
    final workoutDone = (stats['workout_days'] as num?)?.toInt();
    final workoutTarget = widget.state.user?.weeklyWorkoutTarget ?? 3;
    final proteinTarget = widget.state.user?.dailyProteinTargetG ?? 126;
    final daily = ((insight?.progress?['daily']) as List?) ?? [];
    final alerts = ((insight?.progress?['alerts']) as List?) ?? [];

    // AI report gate: need >= 3 days logged
    final hasEnoughData = daysLogged >= 3;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline alert from backend
          if (alerts.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: t.warnTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.warnFill.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: t.warnText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      alerts[0]['text'] as String? ?? '',
                      style: TextStyle(color: t.ink, fontSize: 14, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Stat tiles ──
          Row(
            children: [
              _StatTile(
                value: '$daysLogged',
                label: 'Days\nlogged',
                icon: Icons.calendar_today_outlined,
                t: t,
              ),
              const SizedBox(width: 10),
              _StatTile(
                value: avgProtein != null ? '${avgProtein.toStringAsFixed(0)} g' : '—',
                label: 'Avg\nprotein',
                icon: Icons.bar_chart_rounded,
                t: t,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatTile(
                value: adherence != null ? '${adherence.toStringAsFixed(0)}%' : '—',
                label: 'Target\nadherence',
                icon: Icons.track_changes_outlined,
                t: t,
              ),
              const SizedBox(width: 10),
              _StatTile(
                value: () {
                  final avgSleepMins = (stats['average_sleep_minutes'] as num?)?.toInt();
                  final avgSleepHours = (stats['average_sleep_hours'] as num?)?.toDouble();
                  if (avgSleepMins != null && avgSleepMins > 0) {
                    return SleepWakeStorage.formatDuration(Duration(minutes: avgSleepMins));
                  } else if (_localAvgSleep != null) {
                    return SleepWakeStorage.formatDuration(_localAvgSleep);
                  } else if (avgSleepHours != null && avgSleepHours > 0) {
                    final h = avgSleepHours.floor();
                    final m = ((avgSleepHours - h) * 60).round();
                    return m > 0 ? '${h}h ${m}m' : '${h}h';
                  }
                  return '—';
                }(),
                label: 'Avg\nsleep',
                icon: Icons.bedtime_outlined,
                t: t,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatTile(
                value: workoutDone != null
                    ? '$workoutDone ${workoutDone == 1 ? "day" : "days"}'
                    : '—',
                label: () {
                  final effectiveTarget = _isWeekly ? workoutTarget : (workoutTarget * 4);
                  if (workoutDone != null && workoutDone >= effectiveTarget) {
                    return 'Workouts\nGoal: $effectiveTarget+ met ✓';
                  }
                  return 'Workouts\nGoal: $effectiveTarget+ days';
                }(),
                icon: Icons.fitness_center_outlined,
                t: t,
              ),
              const SizedBox(width: 10),
              _StatTile(
                value: () {
                  final avgHydration = (stats['average_hydration_ml'] as num?)?.toDouble();
                  if (avgHydration != null && avgHydration > 0) {
                    return '${avgHydration.toStringAsFixed(0)} ml';
                  }
                  return '—';
                }(),
                label: 'Avg\nwater',
                icon: Icons.water_drop_outlined,
                t: t,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Protein chart ──
          _SectionLabel(label: 'PROTEIN', t: t),
          const SizedBox(height: 10),
          _TrendChart(
            daily: daily,
            proteinTarget: proteinTarget,
            t: t,
          ),

          const SizedBox(height: 20),

          // ── What this week needs ──
          if (insight?.needs != null && (insight!.needs!).isNotEmpty) ...[
            _SectionLabel(label: 'WHAT THIS ${_isWeekly ? "WEEK" : "MONTH"} NEEDS', t: t),
            const SizedBox(height: 10),
            ...((insight.needs)!).map((need) => _NeedRow(need: need, t: t)),
            const SizedBox(height: 20),
          ],

          // ── AI Life Report ──
          _SectionLabel(label: 'AI LIFE REPORT', t: t),
          const SizedBox(height: 10),

          if (!hasEnoughData) ...[
            _LockedAICard(daysLogged: daysLogged, t: t),
          ] else if (insight?.ai == null) ...[
            _ZenCard(t: t, child: Text(
              'No report available yet.',
              style: TextStyle(color: t.inkMuted, fontSize: 14),
            )),
          ] else ...[
            _AIReportCard(insight: insight!, t: t),
          ],
        ],
      ),
    );
  }

  Widget _buildSkeleton(ZenThemeTokens t) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: _SkeletonBlock(t: t, height: 90)),
            const SizedBox(width: 10),
            Expanded(child: _SkeletonBlock(t: t, height: 90)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _SkeletonBlock(t: t, height: 90)),
            const SizedBox(width: 10),
            Expanded(child: _SkeletonBlock(t: t, height: 90)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _SkeletonBlock(t: t, height: 90)),
            const SizedBox(width: 10),
            Expanded(child: _SkeletonBlock(t: t, height: 90)),
          ]),
          const SizedBox(height: 16),
          _SkeletonBlock(t: t, height: 140),
          const SizedBox(height: 16),
          _SkeletonBlock(t: t, height: 200),
        ],
      ),
    );
  }

  Widget _buildErrorState(ZenThemeTokens t) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: t.inkFaint),
          const SizedBox(height: 16),
          Text("Couldn't load insights.", style: TextStyle(color: t.ink, fontSize: 16)),
          const SizedBox(height: 20),
          SizedBox(
            width: 140,
            child: OutlinedButton(onPressed: _fetchInsight, child: const Text('Try again')),
          ),
        ],
      ),
    );
  }
}

// ─── Chart ───────────────────────────────────────────────────────────────────

class _TrendChart extends StatelessWidget {
  final List daily;
  final double proteinTarget;
  final ZenThemeTokens t;

  const _TrendChart({required this.daily, required this.proteinTarget, required this.t});

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.line),
        ),
        child: Center(
          child: Text(
            'Nothing logged this week.',
            style: TextStyle(color: t.inkFaint, fontSize: 14),
          ),
        ),
      );
    }

    // Find max value for scaling
    double maxVal = proteinTarget * 1.2;
    for (final d in daily) {
      final v = (d['protein_g'] as num?)?.toDouble() ?? 0;
      if (v > maxVal) maxVal = v;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Target line label
          Row(
            children: [
              Container(width: 20, height: 1.5, color: t.inkFaint, child: null),
              const SizedBox(width: 6),
              Text(
                'Target ${proteinTarget.toStringAsFixed(0)} g',
                style: TextStyle(color: t.inkFaint, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: LayoutBuilder(builder: (ctx, constraints) {
              final barWidth = (constraints.maxWidth - (daily.length - 1) * 6) / daily.length;
              final targetFrac = maxVal > 0 ? proteinTarget / maxVal : 0.0;

              return Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // Target dashed line
                  Positioned(
                    bottom: 100 * targetFrac,
                    left: 0,
                    right: 0,
                    child: CustomPaint(
                      painter: _DashedLinePainter(color: t.inkFaint),
                      child: const SizedBox(height: 1),
                    ),
                  ),
                  // Bars
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: daily.asMap().entries.map((e) {
                      final i = e.key;
                      final d = e.value is Map<String, dynamic>
                          ? e.value as Map<String, dynamic>
                          : (e.value is Map ? Map<String, dynamic>.from(e.value as Map) : <String, dynamic>{});
                      final proteinG = (d['protein_g'] as num?)?.toDouble() ?? 0;
                      final rating = (d['rating'] as String?) ?? 'insufficient_data';

                      final frac = maxVal > 0 ? (proteinG / maxVal).clamp(0.0, 1.0) : 0.0;
                      final tokens = t.statusTokens(rating);
                      final barColor = rating == 'insufficient_data'
                          ? t.surfaceAlt
                          : tokens.fill;

                      return Padding(
                        padding: EdgeInsets.only(left: i > 0 ? 6 : 0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (proteinG > 0)
                              Text(
                                '${proteinG.toStringAsFixed(0)}',
                                style: TextStyle(color: t.inkFaint, fontSize: 9),
                              ),
                            const SizedBox(height: 2),
                            AnimatedContainer(
                              duration: Duration(milliseconds: 400 + i * 50),
                              curve: Curves.easeOut,
                              width: barWidth.clamp(8, 48),
                              height: frac > 0 ? (90 * frac).clamp(4, 90) : 4,
                              decoration: BoxDecoration(
                                color: frac > 0 ? barColor : t.line,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 8),
          // Day labels
          Row(
            children: daily.asMap().entries.map((e) {
              final d = e.value is Map<String, dynamic>
                  ? e.value as Map<String, dynamic>
                  : (e.value is Map ? Map<String, dynamic>.from(e.value as Map) : <String, dynamic>{});
              final date = d['date'] as String? ?? '';
              DateTime? dt;
              try { dt = DateTime.parse(date); } catch (_) {}
              final label = dt != null
                  ? const ['M','T','W','T','F','S','S'][dt.weekday - 1]
                  : '?';
              return Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.inkFaint, fontSize: 10),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1.2;
    double x = 0;
    const dash = 6.0, gap = 4.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── AI report card ───────────────────────────────────────────────────────────

class _AIReportCard extends StatelessWidget {
  final InsightModel insight;
  final ZenThemeTokens t;

  const _AIReportCard({required this.insight, required this.t});

  @override
  Widget build(BuildContext context) {
    final ai = insight.ai;
    if (ai == null) return const SizedBox.shrink();

    final summary = (ai['summary'] as String?) ?? insight.summary;
    final highlights = ((ai['highlights'] as List?) ?? insight.highlights).cast<String>();
    final improvements = ((ai['areas_to_improve'] as List?) ?? insight.areasToImprove).cast<String>();
    final coaching = (ai['coaching_notes'] as String?) ?? insight.coachingNotes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ZenCard(
          t: t,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: t.accent),
                  const SizedBox(width: 6),
                  Text('WEEKLY', style: TextStyle(color: t.inkFaint, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                ],
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  summary,
                  style: TextStyle(color: t.ink, fontSize: 14, height: 1.55),
                ),
              ],
            ],
          ),
        ),
        if (highlights.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ZenCard(
            t: t,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('KEY WINS', style: TextStyle(color: t.inkFaint, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                const SizedBox(height: 10),
                ...highlights.map((h) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline, size: 14, color: t.successFill),
                      const SizedBox(width: 8),
                      Expanded(child: Text(h, style: TextStyle(color: t.ink, fontSize: 14, height: 1.4))),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
        if (improvements.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ZenCard(
            t: t,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AREAS TO IMPROVE', style: TextStyle(color: t.inkFaint, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                const SizedBox(height: 10),
                ...improvements.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.arrow_upward_rounded, size: 14, color: t.warnFill),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item, style: TextStyle(color: t.ink, fontSize: 14, height: 1.4))),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
        if (coaching.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('COACHING NOTE', style: TextStyle(color: t.inkFaint, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Text(coaching, style: TextStyle(color: t.inkMuted, fontSize: 14, height: 1.5)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Locked AI card ───────────────────────────────────────────────────────────

class _LockedAICard extends StatelessWidget {
  final int daysLogged;
  final ZenThemeTokens t;

  const _LockedAICard({required this.daysLogged, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 22, color: t.inkFaint),
          const SizedBox(height: 12),
          Text(
            'Log at least 3 days to unlock your report ($daysLogged/3).',
            style: TextStyle(color: t.ink, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: daysLogged / 3,
              minHeight: 6,
              backgroundColor: t.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(t.accent),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Need row ────────────────────────────────────────────────────────────────

class _NeedRow extends StatelessWidget {
  final dynamic need;
  final ZenThemeTokens t;
  const _NeedRow({required this.need, required this.t});

  @override
  Widget build(BuildContext context) {
    final String text = need['text'] as String? ?? need.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_forward_rounded, size: 14, color: t.inkFaint),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: t.ink, fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _PeriodToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final ZenThemeTokens t;
  final VoidCallback onTap;

  const _PeriodToggle({required this.label, required this.selected, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? t.ink : t.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? t.ink : t.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? t.onInk : t.inkMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final ZenThemeTokens t;

  const _StatTile({required this.value, required this.label, required this.icon, required this.t});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: t.inkFaint),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.inkMuted, fontSize: 12, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final ZenThemeTokens t;
  const _SectionLabel({required this.label, required this.t});

  @override
  Widget build(BuildContext context) {
    return Text(label, style: TextStyle(color: t.inkFaint, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8));
  }
}

class _ZenCard extends StatelessWidget {
  final Widget child;
  final ZenThemeTokens t;
  const _ZenCard({required this.child, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: child,
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
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
    );
  }
}

