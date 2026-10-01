import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/zen_colors.dart';

/// Non-dismissible time picker dialog for Pop-up 1 ("What time did you sleep last night?")
/// and Pop-up 2 ("What time did you wake up this morning?").
class SleepWakeTimeDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final TimeOfDay initialTime;
  final String confirmLabel;
  final String? Function(TimeOfDay selectedTime)? validator;
  final ValueChanged<TimeOfDay> onConfirmed;

  const SleepWakeTimeDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.initialTime,
    this.confirmLabel = 'Confirm',
    this.validator,
    required this.onConfirmed,
  });

  static Future<TimeOfDay?> show({
    required BuildContext context,
    required String title,
    required String subtitle,
    required TimeOfDay initialTime,
    String confirmLabel = 'Confirm',
    String? Function(TimeOfDay selectedTime)? validator,
  }) {
    return showDialog<TimeOfDay>(
      context: context,
      barrierDismissible: false, // Cannot dismiss by tapping outside
      builder: (ctx) => PopScope(
        canPop: false, // Cannot dismiss via back button
        child: SleepWakeTimeDialog(
          title: title,
          subtitle: subtitle,
          initialTime: initialTime,
          confirmLabel: confirmLabel,
          validator: validator,
          onConfirmed: (time) => Navigator.of(ctx).pop(time),
        ),
      ),
    );
  }

  @override
  State<SleepWakeTimeDialog> createState() => _SleepWakeTimeDialogState();
}

class _SleepWakeTimeDialogState extends State<SleepWakeTimeDialog> {
  late TimeOfDay _selectedTime;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedTime = widget.initialTime;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        final t = context.zen;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: t.ink,
              onPrimary: t.onInk,
              surface: t.surface,
              onSurface: t.ink,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
        _errorMessage = null;
      });
    }
  }

  void _submit() {
    if (widget.validator != null) {
      final err = widget.validator!(_selectedTime);
      if (err != null) {
        setState(() => _errorMessage = err);
        return;
      }
    }
    widget.onConfirmed(_selectedTime);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    final period = _selectedTime.period == DayPeriod.am ? 'AM' : 'PM';
    final hourOfPeriod = _selectedTime.hourOfPeriod == 0 ? 12 : _selectedTime.hourOfPeriod;
    final timeStr =
        '${hourOfPeriod.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')} $period';

    return Dialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: t.line, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon Pill
            Align(
              alignment: Alignment.centerLeft,
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
                    Icons.access_time_filled_rounded,
                    color: t.ink,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              widget.title,
              style: GoogleFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: t.ink,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),

            // Subtitle
            Text(
              widget.subtitle,
              style: TextStyle(
                color: t.inkMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // Time Selector Box
            GestureDetector(
              onTap: _pickTime,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: t.surfaceAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _errorMessage != null ? t.dangerFill : t.line),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      timeStr,
                      style: GoogleFonts.fraunces(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: t.ink,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Change',
                        style: TextStyle(
                          color: t.onInk,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Validation Error if any
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, size: 16, color: t.dangerFill),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: t.dangerFill,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Confirm Button
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.ink,
                foregroundColor: t.onInk,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
                widget.confirmLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Night Confirmation Modal for Feature 2: "Submit Today's Report"
/// Options:
/// - "Yes, I'm going to sleep now" -> sleepTime = DateTime.now(), sleepPending = false
/// - "No, ask me tomorrow morning" -> sleepTime = null, sleepPending = true
class NightConfirmationModal extends StatelessWidget {
  final VoidCallback onSleepNow;
  final VoidCallback onAskTomorrow;

  const NightConfirmationModal({
    super.key,
    required this.onSleepNow,
    required this.onAskTomorrow,
  });

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PopScope(
        canPop: false,
        child: NightConfirmationModal(
          onSleepNow: () => Navigator.of(ctx).pop(true),
          onAskTomorrow: () => Navigator.of(ctx).pop(false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: t.line, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: t.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.line),
                ),
                child: Center(
                  child: Icon(Icons.nightlight_round, color: t.ink, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'End of Day Review',
                  style: GoogleFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Are you going to sleep right now, or should ZenLog ask for your sleep time tomorrow morning?',
            style: TextStyle(
              color: t.inkMuted,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),

          // Option A: Sleep Now
          ElevatedButton(
            onPressed: onSleepNow,
            style: ElevatedButton.styleFrom(
              backgroundColor: t.ink,
              foregroundColor: t.onInk,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bedtime_outlined, size: 18),
                SizedBox(width: 8),
                Text(
                  "Yes, I'm going to sleep now",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Option B: Ask Me Tomorrow
          OutlinedButton(
            onPressed: onAskTomorrow,
            style: OutlinedButton.styleFrom(
              foregroundColor: t.ink,
              side: BorderSide(color: t.line, width: 1.5),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wb_sunny_outlined, size: 18),
                SizedBox(width: 8),
                Text(
                  'No, ask me tomorrow morning',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
