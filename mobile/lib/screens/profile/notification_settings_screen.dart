import 'package:flutter/material.dart';
import '../../core/theme/zen_colors.dart';
import '../../services/api_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final ApiService _api = ApiService();

  bool _isLoading = true;
  bool _isSaving = false;

  // Settings state
  bool _breakfastReminder = true;
  bool _lunchReminder = true;
  bool _dinnerReminder = true;
  bool _morningQuote = true;
  bool _eveningQuote = true;
  bool _hydrationReminder = true;
  List<Map<String, dynamic>> _customReminders = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final data = await _api.getNotificationSettings();
    if (mounted) {
      if (data != null) {
        setState(() {
          _breakfastReminder = data['breakfast_reminder'] ?? true;
          _lunchReminder = data['lunch_reminder'] ?? true;
          _dinnerReminder = data['dinner_reminder'] ?? true;
          _morningQuote = data['morning_quote'] ?? true;
          _eveningQuote = data['evening_quote'] ?? true;
          _hydrationReminder = data['hydration_reminder'] ?? true;
          _customReminders = List<Map<String, dynamic>>.from(
            (data['custom_reminders'] as List?)?.map((x) => Map<String, dynamic>.from(x as Map)) ?? [],
          );
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    final payload = {
      'breakfast_reminder': _breakfastReminder,
      'lunch_reminder': _lunchReminder,
      'dinner_reminder': _dinnerReminder,
      'morning_quote': _morningQuote,
      'evening_quote': _eveningQuote,
      'hydration_reminder': _hydrationReminder,
      'custom_reminders': _customReminders,
    };
    final ok = await _api.updateNotificationSettings(payload);
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Reminder preferences saved' : 'Could not save preferences'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _triggerTest(String template, String label) async {
    final t = context.zen;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Dispatching $label test…'),
        backgroundColor: t.ink,
        duration: const Duration(seconds: 1),
      ),
    );

    final res = await _api.triggerTestNotification(template: template);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.ok ? t.ink : t.dangerFill,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showAddCustomDialog() {
    final t = context.zen;
    final labelCtrl = TextEditingController();
    TimeOfDay selectedTime = const TimeOfDay(hour: 8, minute: 30);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final timeStr =
                '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: Container(
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(color: t.line),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: SingleChildScrollView(
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
                      Text('Add Custom Reminder', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.ink)),
                      const SizedBox(height: 6),
                      Text('e.g. Creatine, Whey Protein, Evening Gym, Water, Vitamins', style: TextStyle(fontSize: 13, color: t.inkMuted)),
                      const SizedBox(height: 16),
                      Text('Reminder Label', style: TextStyle(color: t.inkMuted, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: labelCtrl,
                        decoration: InputDecoration(
                          hintText: 'e.g. Take Creatine 5g',
                          filled: true,
                          fillColor: t.surfaceAlt,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.line)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('Time', style: TextStyle(color: t.inkMuted, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            setSheetState(() => selectedTime = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: t.surfaceAlt,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: t.line),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.access_time_rounded, size: 20, color: t.ink),
                              const SizedBox(width: 12),
                              Text(
                                '${selectedTime.format(context)} ($timeStr)',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.ink),
                              ),
                              const Spacer(),
                              Text('Change', style: TextStyle(color: t.inkFaint, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
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
                                final text = labelCtrl.text.trim();
                                if (text.isEmpty) return;
                                final newReminder = {
                                  'id': DateTime.now().millisecondsSinceEpoch.toString(),
                                  'time': timeStr,
                                  'label': text,
                                  'enabled': true,
                                };
                                setState(() {
                                  _customReminders.add(newReminder);
                                });
                                Navigator.pop(sheetCtx);
                                _saveSettings();
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: t.ink, foregroundColor: t.onInk),
                              child: const Text('Add Reminder'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Text(
          'Reminders & Alerts',
          style: TextStyle(color: t.ink, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        backgroundColor: t.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: t.ink),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: t.ink))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                // ── Section 1: Smart Missing Meal Reminders ──
                _SectionHeader(
                  title: 'SMART MEAL CHECKS',
                  subtitle: 'ZenLog checks your journal. You will ONLY be notified if that meal is missing at that time.',
                  t: t,
                ),
                const SizedBox(height: 8),
                _CardContainer(
                  t: t,
                  children: [
                    _SwitchTile(
                      icon: Icons.breakfast_dining_rounded,
                      title: 'Breakfast Check',
                      time: '11:00 AM',
                      subtitle: 'Alert only if breakfast is unlogged',
                      value: _breakfastReminder,
                      onChanged: (v) {
                        setState(() => _breakfastReminder = v);
                        _saveSettings();
                      },
                      t: t,
                    ),
                    _Divider(t: t),
                    _SwitchTile(
                      icon: Icons.lunch_dining_rounded,
                      title: 'Lunch Check',
                      time: '3:00 PM',
                      subtitle: 'Alert only if lunch is unlogged',
                      value: _lunchReminder,
                      onChanged: (v) {
                        setState(() => _lunchReminder = v);
                        _saveSettings();
                      },
                      t: t,
                    ),
                    _Divider(t: t),
                    _SwitchTile(
                      icon: Icons.dinner_dining_rounded,
                      title: 'Dinner & Wrap-Up',
                      time: '10:00 PM',
                      subtitle: 'Alert only if dinner is unlogged',
                      value: _dinnerReminder,
                      onChanged: (v) {
                        setState(() => _dinnerReminder = v);
                        _saveSettings();
                      },
                      t: t,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Section 2: Quotes & Mindset ──
                _SectionHeader(
                  title: 'DAILY INSPIRATION & REFLECTION',
                  subtitle: 'Discipline quotes formatted in beautiful Ink & Paper cards on your lock screen.',
                  t: t,
                ),
                const SizedBox(height: 8),
                _CardContainer(
                  t: t,
                  children: [
                    _SwitchTile(
                      icon: Icons.wb_sunny_rounded,
                      title: 'Morning Motivation',
                      time: '7:00 AM',
                      subtitle: 'Discipline quote to start your morning',
                      value: _morningQuote,
                      onChanged: (v) {
                        setState(() => _morningQuote = v);
                        _saveSettings();
                      },
                      t: t,
                    ),
                    _Divider(t: t),
                    _SwitchTile(
                      icon: Icons.nightlight_round,
                      title: 'Evening Reflection',
                      time: '7:00 PM',
                      subtitle: 'Mindful quote & daily progress recap',
                      value: _eveningQuote,
                      onChanged: (v) {
                        setState(() => _eveningQuote = v);
                        _saveSettings();
                      },
                      t: t,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Section 3: Smart Health Nudges ──
                _SectionHeader(
                  title: 'HEALTH NUDGES',
                  subtitle: 'Gentle pacing alerts during active hours.',
                  t: t,
                ),
                const SizedBox(height: 8),
                _CardContainer(
                  t: t,
                  children: [
                    _SwitchTile(
                      icon: Icons.water_drop_rounded,
                      title: 'Hydration Check',
                      time: '4:00 PM',
                      subtitle: 'Alert if under 50% of your water target',
                      value: _hydrationReminder,
                      onChanged: (v) {
                        setState(() => _hydrationReminder = v);
                        _saveSettings();
                      },
                      t: t,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Section 4: Custom Reminders ──
                Row(
                  children: [
                    Expanded(
                      child: _SectionHeader(
                        title: 'CUSTOM REMINDERS',
                        subtitle: 'Vitamins, Creatine, Gym, or customized habits.',
                        t: t,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _showAddCustomDialog,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CardContainer(
                  t: t,
                  children: [
                    if (_customReminders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        child: Center(
                          child: Text(
                            'No custom reminders added yet.\nTap "+ Add" to create one.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: t.inkFaint, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      for (int i = 0; i < _customReminders.length; i++) ...[
                        if (i > 0) _Divider(t: t),
                        _CustomReminderTile(
                          reminder: _customReminders[i],
                          onToggle: (v) {
                            setState(() => _customReminders[i]['enabled'] = v);
                            _saveSettings();
                          },
                          onDelete: () {
                            setState(() => _customReminders.removeAt(i));
                            _saveSettings();
                          },
                          t: t,
                        ),
                      ],
                  ],
                ),

                const SizedBox(height: 24),

                // ── Section 5: Live Test Templates ──
                _SectionHeader(
                  title: 'PREVIEW TEMPLATES ON DEVICE',
                  subtitle: 'Send an instant test push to your phone to preview the rich cards.',
                  t: t,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TestButton(
                      label: '7 AM Morning Quote',
                      icon: Icons.wb_sunny_rounded,
                      onPressed: () => _triggerTest('morning_quote', 'Morning Quote'),
                      t: t,
                    ),
                    _TestButton(
                      label: '7 PM Evening Quote',
                      icon: Icons.nightlight_round,
                      onPressed: () => _triggerTest('evening_quote', 'Evening Quote'),
                      t: t,
                    ),
                    _TestButton(
                      label: 'Lunch Check Alert',
                      icon: Icons.lunch_dining_rounded,
                      onPressed: () => _triggerTest('lunch_check', 'Lunch Check'),
                      t: t,
                    ),
                    _TestButton(
                      label: 'Hydration Nudge',
                      icon: Icons.water_drop_rounded,
                      onPressed: () => _triggerTest('hydration_nudge', 'Hydration Nudge'),
                      t: t,
                    ),
                  ],
                ),

                const SizedBox(height: 40),
              ],
            ),
    );
  }
}

// ── Shared Small UI Components ───────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final ZenThemeTokens t;

  const _SectionHeader({required this.title, required this.subtitle, required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.inkFaint, letterSpacing: 0.8),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: t.inkMuted, height: 1.3),
        ),
      ],
    );
  }
}

class _CardContainer extends StatelessWidget {
  final List<Widget> children;
  final ZenThemeTokens t;

  const _CardContainer({required this.children, required this.t});

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

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String time;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ZenThemeTokens t;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.time,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: t.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: t.ink),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: t.surfaceAlt,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        time,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.inkMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: t.ink,
          ),
        ],
      ),
    );
  }
}

class _CustomReminderTile extends StatelessWidget {
  final Map<String, dynamic> reminder;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final ZenThemeTokens t;

  const _CustomReminderTile({
    required this.reminder,
    required this.onToggle,
    required this.onDelete,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final label = reminder['label'] as String? ?? 'Reminder';
    final time = reminder['time'] as String? ?? '08:00';
    final enabled = reminder['enabled'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: t.surfaceAlt, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.alarm_rounded, size: 20, color: t.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: t.ink), overflow: TextOverflow.ellipsis),
                Text(time, style: TextStyle(fontSize: 12, color: t.inkMuted)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: t.inkFaint),
            onPressed: onDelete,
          ),
          Switch.adaptive(value: enabled, onChanged: onToggle, activeColor: t.ink),
        ],
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final ZenThemeTokens t;

  const _TestButton({required this.label, required this.icon, required this.onPressed, required this.t});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: t.ink),
      label: Text(label, style: TextStyle(color: t.ink, fontSize: 12, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: t.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final ZenThemeTokens t;
  const _Divider({required this.t});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, indent: 52, color: t.line);
  }
}
