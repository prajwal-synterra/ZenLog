import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/zen_colors.dart';
import '../../services/auth_storage.dart';
import '../../services/connection_monitor.dart';
import '../../services/sync_engine.dart';
import '../../services/wake_service.dart';
import '../../state/zen_state.dart';
import '../auth/landing_screen.dart';


class ProfileScreen extends StatefulWidget {
  final ZenState state;
  final VoidCallback? onBack;

  const ProfileScreen({
    super.key,
    required this.state,
    this.onBack,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WakeService().wakeAndProbe();
  }

  void _showTargetEditor({
    required String title,
    required String currentValue,
    required String unit,
    required String hint,
    required String helperText,
    double? min,
    double? max,
    required void Function(double) onSave,
  }) {
    final ctrl = TextEditingController(text: currentValue);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final t = context.zen;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
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
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.ink)),
                const SizedBox(height: 4),
                if (helperText.isNotEmpty)
                  Text(helperText, style: TextStyle(fontSize: 13, color: t.inkMuted, height: 1.4)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                  autofocus: true,
                  decoration: InputDecoration(
                    suffixText: unit,
                    hintText: hint,
                    filled: true,
                    fillColor: t.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.ink, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final val = double.tryParse(ctrl.text.trim());
                          if (val != null) {
                            if (min != null && val < min) return;
                            if (max != null && val > max) return;
                            onSave(val);
                            Navigator.pop(sheetCtx);
                            _showToast('Changes apply from today onward.');
                          }
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showToast(String msg) {
    final t = context.zen;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: t.ink,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  Future<void> _logout() async {
    final t = context.zen;
    final queued = SyncEngine().queuedCount;

    if (queued > 0) {
      // Dialog P40 (§8.5)
      final action = await showDialog<String>(
        context: context,
        builder: (dlgCtx) => AlertDialog(
          title: const Text('Unsynced entries'),
          content: Text('You have $queued unsynced entr${queued == 1 ? 'y' : 'ies'}. If you log out now they will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, 'cancel'),
              child: Text('Cancel', style: TextStyle(color: t.inkMuted)),
            ),
            if (ConnectionMonitor().current.state == ConnectionStateEnum.connected)
              ElevatedButton(
                onPressed: () => Navigator.pop(dlgCtx, 'sync_first'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.ink,
                  foregroundColor: t.onInk,
                ),
                child: const Text('Sync first'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, 'logout_anyway'),
              child: Text('Log out anyway', style: TextStyle(color: t.dangerFill, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

      if (action == 'sync_first') {
        await SyncEngine().runSync('manual');
        if (SyncEngine().queuedCount == 0 && mounted) {
          await _performLogout();
        }
      } else if (action == 'logout_anyway' && mounted) {
        await _performLogout();
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Log out of this device?'),
        content: const Text('Your journal stays saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: Text('Cancel', style: TextStyle(color: t.inkMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.dangerFill,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _performLogout();
    }
  }

  Future<void> _performLogout() async {
    await AuthStorage.handleUserLogout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingScreen()),
        (_) => false,
      );
    }
  }


  void _saveGoal(String goal) {
    final user = widget.state.user;
    // Confirm goal change dialog
    final t = context.zen;
    final goalLabel = _goalLabel(goal);
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('Change goal to $goalLabel?'),
        content: const Text(
          'Scoring and calorie rules change from today. Past days keep their old targets.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dlgCtx);
              widget.state.updateGoals(
                goal: goal,
                bodyWeight: user?.bodyWeightKg ?? 70.0,
                proteinTarget: user?.dailyProteinTargetG ?? 126.0,
                calorieTarget: user?.dailyCalorieTarget,
                waterTargetMl: user?.dailyWaterTargetMl,
                weeklyWorkoutTarget: user?.weeklyWorkoutTarget,
              );
              setState(() {});
            },
            child: Text('Change goal', style: TextStyle(color: t.onInk)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    final user = widget.state.user;
    final bodyWeight = user?.bodyWeightKg ?? 70.0;
    final protein = user?.dailyProteinTargetG ?? 126.0;
    final calTarget = user?.dailyCalorieTarget;
    final water = user?.dailyWaterTargetMl ?? 3000.0;
    final workouts = user?.weeklyWorkoutTarget ?? 3;
    final currentGoal = user?.goal ?? 'muscle_gain';
    final gPerKg = bodyWeight > 0 ? (protein / bodyWeight) : 0.0;

    final displayName = user?.name.isNotEmpty == true
        ? user!.name
        : (user?.username ?? 'You');
    final username = user?.username ?? '';
    final initials = _initials(displayName);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────────
              Text(
                'Me',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: 20),

              // ── User identity ────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.ink,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: TextStyle(color: t.onInk, fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: TextStyle(color: t.ink, fontSize: 18, fontWeight: FontWeight.w600)),
                      if (username.isNotEmpty)
                        Text('@$username', style: TextStyle(color: t.inkMuted, fontSize: 13)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ── GOAL ─────────────────────────────────────────────────────────
              _SectionLabel(label: 'GOAL', t: t),
              const SizedBox(height: 10),
              _GoalGrid(
                current: currentGoal,
                onChanged: _saveGoal,
                t: t,
              ),

              const SizedBox(height: 24),

              // ── DAILY TARGETS ────────────────────────────────────────────────
              _SectionLabel(label: 'DAILY TARGETS', t: t),
              const SizedBox(height: 10),
              _SettingsCard(t: t, children: [
                _SettingsRow(
                  label: 'Protein',
                  value: '${protein.toStringAsFixed(0)} g',
                  detail: '${gPerKg.toStringAsFixed(1)} g/kg',
                  t: t,
                  onTap: () => _showTargetEditor(
                    title: 'Daily Protein Target',
                    currentValue: protein.toStringAsFixed(0),
                    unit: 'g',
                    hint: 'e.g. 126',
                    helperText: 'Current: ${gPerKg.toStringAsFixed(1)} g/kg. Range: 20–400 g.',
                    min: 20, max: 400,
                    onSave: (val) => widget.state.updateGoals(
                      goal: currentGoal,
                      bodyWeight: bodyWeight,
                      proteinTarget: val,
                      calorieTarget: calTarget,
                      waterTargetMl: water,
                      weeklyWorkoutTarget: workouts,
                    ),
                  ),
                ),
                _Hairline(t: t),
                _SettingsRow(
                  label: 'Calories',
                  value: calTarget != null ? '${calTarget.toStringAsFixed(0)} kcal' : 'Not set',
                  detail: calTarget == null ? 'Won\'t count toward score' : '',
                  t: t,
                  onTap: () => _showTargetEditor(
                    title: 'Daily Calorie Target',
                    currentValue: calTarget?.toStringAsFixed(0) ?? '',
                    unit: 'kcal',
                    hint: 'e.g. 2200 (leave 0 to unset)',
                    helperText: 'Calories won\'t count toward your score until you set a target.',
                    min: 800, max: 6000,
                    onSave: (val) => widget.state.updateGoals(
                      goal: currentGoal,
                      bodyWeight: bodyWeight,
                      proteinTarget: protein,
                      calorieTarget: val > 0 ? val : null,
                      waterTargetMl: water,
                      weeklyWorkoutTarget: workouts,
                    ),
                  ),
                ),
                _Hairline(t: t),
                _SettingsRow(
                  label: 'Water',
                  value: '${water.toStringAsFixed(0)} ml',
                  t: t,
                  onTap: () => _showTargetEditor(
                    title: 'Daily Water Target',
                    currentValue: water.toStringAsFixed(0),
                    unit: 'ml',
                    hint: 'e.g. 3000',
                    helperText: 'Range: 500–8000 ml.',
                    min: 500, max: 8000,
                    onSave: (val) => widget.state.updateGoals(
                      goal: currentGoal,
                      bodyWeight: bodyWeight,
                      proteinTarget: protein,
                      calorieTarget: calTarget,
                      waterTargetMl: val,
                      weeklyWorkoutTarget: workouts,
                    ),
                  ),
                ),
                _Hairline(t: t),
                _SettingsRow(
                  label: 'Workouts / week',
                  value: '$workouts days',
                  t: t,
                  onTap: () => _showTargetEditor(
                    title: 'Weekly Workout Target',
                    currentValue: workouts.toString(),
                    unit: 'days',
                    hint: '0–7',
                    helperText: 'How many workouts you aim for per week.',
                    min: 0, max: 7,
                    onSave: (val) => widget.state.updateGoals(
                      goal: currentGoal,
                      bodyWeight: bodyWeight,
                      proteinTarget: protein,
                      calorieTarget: calTarget,
                      waterTargetMl: water,
                      weeklyWorkoutTarget: val.toInt(),
                    ),
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'Changes apply from today onward.',
                  style: TextStyle(color: t.inkFaint, fontSize: 12),
                ),
              ),

              const SizedBox(height: 24),

              // ── BODY ─────────────────────────────────────────────────────────
              _SectionLabel(label: 'BODY', t: t),
              const SizedBox(height: 10),
              _SettingsCard(t: t, children: [
                _SettingsRow(
                  label: 'Body weight',
                  value: '${bodyWeight.toStringAsFixed(1)} kg',
                  t: t,
                  onTap: () => _showTargetEditor(
                    title: 'Body Weight',
                    currentValue: bodyWeight.toStringAsFixed(1),
                    unit: 'kg',
                    hint: 'e.g. 70.0',
                    helperText: 'Used to calculate your g/kg protein ratio. Range: 20–300 kg.',
                    min: 20, max: 300,
                    onSave: (val) => widget.state.updateGoals(
                      goal: currentGoal,
                      bodyWeight: val,
                      proteinTarget: protein,
                      calorieTarget: calTarget,
                      waterTargetMl: water,
                      weeklyWorkoutTarget: workouts,
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              // ── THIS DEVICE ──────────────────────────────────────────────────
              _SectionLabel(label: 'THIS DEVICE', t: t),
              const SizedBox(height: 10),
              _SettingsCard(t: t, children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.smartphone_rounded, size: 18, color: t.inkMuted),
                      const SizedBox(width: 12),
                      Text('Flutter device · signed in', style: TextStyle(color: t.inkMuted, fontSize: 14)),
                    ],
                  ),
                ),
              ]),

              const SizedBox(height: 20),

              // ── LOG OUT ──────────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _logout,
                  icon: Icon(Icons.logout_rounded, size: 18, color: t.dangerFill),
                  label: Text(
                    'Log out',
                    style: TextStyle(color: t.dangerFill, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: t.dangerFill.withValues(alpha: 0.4)),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Section 8.4 Connection Card ──────────────────────────────────
              _buildConnectionCard(t),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionCard(ZenThemeTokens t) {
    return ListenableBuilder(
      listenable: WakeService(),
      builder: (context, _) {
        final wake = WakeService();
        return ListenableBuilder(
          listenable: SyncEngine(),
          builder: (context, _) {
            return StreamBuilder<ConnectionSnapshot>(
              stream: ConnectionMonitor().stream,
              initialData: ConnectionMonitor().current,
              builder: (context, snapshot) {
                final conn = snapshot.data ?? ConnectionMonitor().current;
                final queuedCount = SyncEngine().queuedCount;
                final isSyncing = SyncEngine().isSyncing;

                Color dotColor;
                String statusTitle;
                if (wake.isWaking) {
                  dotColor = t.warnFill;
                  statusTitle = 'Waking server… (cold start)';
                } else {
                  switch (conn.state) {
                    case ConnectionStateEnum.connected:
                      dotColor = t.successFill;
                      statusTitle = 'Connected to server';
                      break;
                    case ConnectionStateEnum.disconnected:
                      dotColor = t.dangerFill;
                      statusTitle = 'Backend not reachable';
                      break;
                    case ConnectionStateEnum.authRequired:
                      dotColor = t.warnFill;
                      statusTitle = 'Session ended. Log in again.';
                      break;
                    case ConnectionStateEnum.unknown:
                      dotColor = t.inkFaint;
                      statusTitle = 'Checking connection…';
                      break;
                  }
                }

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONNECTION',
                    style: TextStyle(
                      color: t.inkFaint,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusTitle,
                          style: TextStyle(
                            color: t.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (conn.state == ConnectionStateEnum.disconnected || wake.isUnreachable)
                        GestureDetector(
                          onTap: () {
                            WakeService().wakeAndProbe(forceColdCheck: true);
                            ConnectionMonitor().probeNow();
                            SyncEngine().runSync('manual');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: t.surfaceAlt,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: t.line),
                            ),
                            child: Text(
                              'Retry',
                              style: TextStyle(
                                color: t.ink,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else if (queuedCount > 0)
                        GestureDetector(
                          onTap: isSyncing
                              ? null
                              : () => SyncEngine().runSync('manual'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSyncing ? t.surfaceAlt : t.ink,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isSyncing ? 'Syncing…' : 'Sync now',
                              style: TextStyle(
                                color: isSyncing ? t.inkMuted : t.onInk,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Server: ${wake.isAwake ? "Awake" : wake.isWaking ? "Waking…" : "Unreachable"} · Ping: ${wake.timeSinceLastPingFormatted}',
                        style: TextStyle(color: t.inkMuted, fontSize: 11.5),
                      ),
                      const Spacer(),
                      Text('10m Keep-Alive Active', style: TextStyle(color: t.inkFaint, fontSize: 11)),
                    ],
                  ),
                  if (conn.state == ConnectionStateEnum.disconnected) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: conn.debugString));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied debug info: ${conn.debugString}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Text(
                        'Reason: ${conn.message}',
                        style: TextStyle(color: t.inkMuted, fontSize: 12, height: 1.3),
                      ),
                    ),
                  ],
                  if (conn.clockSkewMin != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Phone clock is ${conn.clockSkewMin} min off. Entry times may be wrong.',
                      style: TextStyle(color: t.warnFill, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (queuedCount > 0)
                        Text(
                          isSyncing ? 'Syncing entries…' : '$queuedCount entr${queuedCount == 1 ? 'y' : 'ies'} waiting to sync',
                          style: TextStyle(color: t.inkFaint, fontSize: 11),
                        )
                      else
                        Text(
                          'ZenLog v2.0 · Offline Ready',
                          style: TextStyle(color: t.inkFaint, fontSize: 11),
                        ),
                      const Spacer(),
                      Text('ZenLog v2.0', style: TextStyle(color: t.inkFaint, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  },
);
}


  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (name.isNotEmpty) return name[0].toUpperCase();
    return 'Z';
  }

  String _goalLabel(String goal) {
    return switch (goal) {
      'muscle_gain' => 'Muscle gain',
      'fat_loss'    => 'Fat loss',
      'maintenance' => 'Maintenance',
      'mindfulness' => 'Mindfulness',
      _             => goal,
    };
  }
}

// ─── Goal Grid ──────────────────────────────────────────────────────────────

class _GoalGrid extends StatelessWidget {
  final String current;
  final void Function(String) onChanged;
  final ZenThemeTokens t;

  const _GoalGrid({required this.current, required this.onChanged, required this.t});

  static const _goals = [
    ('muscle_gain', 'Muscle gain',   'Build strength and size'),
    ('fat_loss',    'Fat loss',      'Reduce body fat'),
    ('maintenance', 'Maintenance',   'Hold your current weight'),
    ('mindfulness', 'Mindfulness',   'Focus on consistent habits'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: _goals.map((g) {
        final (key, label, desc) = g;
        final selected = current == key;
        return GestureDetector(
          onTap: () => onChanged(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? t.ink : t.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? t.ink : t.line,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? t.onInk : t.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    color: selected ? t.onInk.withValues(alpha: 0.7) : t.inkMuted,
                    fontSize: 11,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Shared small widgets ────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final ZenThemeTokens t;
  const _SectionLabel({required this.label, required this.t});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: t.inkFaint,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final ZenThemeTokens t;
  const _SettingsCard({required this.children, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final ZenThemeTokens t;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.label,
    required this.value,
    this.detail = '',
    required this.t,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(color: t.ink, fontSize: 15)),
            ),
            if (detail.isNotEmpty)
              Text(detail, style: TextStyle(color: t.inkFaint, fontSize: 12)),
            if (detail.isNotEmpty) const SizedBox(width: 8),
            Text(value, style: TextStyle(color: t.inkMuted, fontSize: 14)),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 18, color: t.inkFaint),
            ],
          ],
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  final ZenThemeTokens t;
  const _Hairline({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 16),
      color: t.line,
    );
  }
}

