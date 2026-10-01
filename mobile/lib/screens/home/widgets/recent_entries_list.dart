// Legacy widget — not used by the v3 home screen, kept for compatibility.
import 'package:flutter/material.dart';
import '../../../../core/theme/zen_colors.dart';
import '../../../../models/log_model.dart';

class RecentEntriesList extends StatelessWidget {
  final List<LogEntryModel> logs;
  final VoidCallback? onSeeAll;

  const RecentEntriesList({
    super.key,
    required this.logs,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Entries', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: t.ink)),
            GestureDetector(
              onTap: onSeeAll,
              child: Text('See all (${logs.length})', style: TextStyle(fontSize: 12, color: t.inkMuted)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (logs.isEmpty)
          Center(child: Text('Nothing logged yet.', style: TextStyle(color: t.inkFaint, fontSize: 14)))
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: logs.length > 4 ? 4 : logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, index) {
              final log = logs[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.line),
                ),
                child: Text(log.text, style: TextStyle(color: t.ink, fontSize: 14, height: 1.4)),
              );
            },
          ),
      ],
    );
  }
}


