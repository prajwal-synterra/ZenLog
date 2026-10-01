import 'package:flutter/material.dart';
import '../../../../core/theme/zen_colors.dart';

class QuickLogBar extends StatefulWidget {
  final Function(String) onSubmitted;

  const QuickLogBar({
    super.key,
    required this.onSubmitted,
  });

  @override
  State<QuickLogBar> createState() => _QuickLogBarState();
}

class _QuickLogBarState extends State<QuickLogBar> {
  final TextEditingController _controller = TextEditingController();

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.onSubmitted(text);
      _controller.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: ZenColors2.forestDark.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: ZenColors2.forestDark.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.edit_note_rounded,
            color: ZenColors2.forestMedium,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                fontSize: 14,
                color: ZenColors2.forestDark,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Log a meal, workout, or reflection...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: ZenColors2.textSubtle,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          GestureDetector(
            onTap: _submit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: ZenColors2.forestDark,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text(
                'Log +',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


