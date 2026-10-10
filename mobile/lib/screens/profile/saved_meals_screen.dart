import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/zen_colors.dart';
import '../../state/zen_state.dart';

class SavedMealsScreen extends StatefulWidget {
  final ZenState state;

  const SavedMealsScreen({super.key, required this.state});

  @override
  State<SavedMealsScreen> createState() => _SavedMealsScreenState();
}

class _SavedMealsScreenState extends State<SavedMealsScreen> {
  @override
  void initState() {
    super.initState();
    widget.state.loadSavedMeals();
  }

  void _showAddEditDialog({Map<String, dynamic>? meal}) {
    final t = context.zen;
    final isEdit = meal != null;
    final nameCtrl = TextEditingController(text: meal?['name'] as String? ?? '');
    final textCtrl = TextEditingController(text: meal?['raw_text'] as String? ?? '');

    final extracted = (meal?['extracted'] as Map?) ?? {};
    final proteinCtrl = TextEditingController(
      text: (extracted['protein_g'] as num?)?.toString() ?? '',
    );
    final calCtrl = TextEditingController(
      text: (extracted['calories'] as num?)?.toString() ??
          (extracted['calories_kcal'] as num?)?.toString() ??
          '',
    );
    final carbsCtrl = TextEditingController(
      text: (extracted['carbs_g'] as num?)?.toString() ?? '',
    );
    final fatCtrl = TextEditingController(
      text: (extracted['fat_g'] as num?)?.toString() ?? '',
    );
    bool isPinned = meal?['pinned'] == true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
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
                          decoration: BoxDecoration(
                            color: t.line,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(
                        isEdit ? 'Edit Favorite Meal' : 'Add Favorite Meal',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.ink),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Meal Name',
                          hintText: 'e.g. Whey Shake & Banana',
                          filled: true,
                          fillColor: t.surfaceAlt,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.line)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: textCtrl,
                        decoration: InputDecoration(
                          labelText: 'Description / Ingredients',
                          hintText: 'e.g. 1 scoop whey, 1 medium banana',
                          filled: true,
                          fillColor: t.surfaceAlt,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.line)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Macros', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.inkMuted)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: proteinCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Protein (g)',
                                filled: true,
                                fillColor: t.surfaceAlt,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.line)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: calCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Calories (kcal)',
                                filled: true,
                                fillColor: t.surfaceAlt,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.line)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: carbsCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Carbs (g)',
                                filled: true,
                                fillColor: t.surfaceAlt,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.line)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: fatCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Fat (g)',
                                filled: true,
                                fillColor: t.surfaceAlt,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.line)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Checkbox(
                            value: isPinned,
                            onChanged: (v) => setSheetState(() => isPinned = v ?? false),
                            activeColor: t.ink,
                          ),
                          Expanded(
                            child: Text('Pin to quick-action bar', style: TextStyle(color: t.ink, fontSize: 14)),
                          ),
                        ],
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
                              onPressed: () async {
                                final name = nameCtrl.text.trim();
                                if (name.isEmpty) return;
                                final p = double.tryParse(proteinCtrl.text.trim()) ?? 0.0;
                                final cal = double.tryParse(calCtrl.text.trim()) ?? 0.0;
                                final c = double.tryParse(carbsCtrl.text.trim());
                                final f = double.tryParse(fatCtrl.text.trim());

                                final newExtracted = <String, dynamic>{
                                  'protein_g': p,
                                  'calories': cal.toInt(),
                                  if (c != null) 'carbs_g': c,
                                  if (f != null) 'fat_g': f,
                                };

                                if (isEdit) {
                                  await widget.state.updateSavedMeal(
                                    meal['id'] as String,
                                    name: name,
                                    rawText: textCtrl.text.trim(),
                                    extracted: newExtracted,
                                    pinned: isPinned,
                                  );
                                } else {
                                  await widget.state.createSavedMealManual(
                                    name: name,
                                    rawText: textCtrl.text.trim(),
                                    extracted: newExtracted,
                                    pinned: isPinned,
                                  );
                                }
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.ink,
                                foregroundColor: t.onInk,
                              ),
                              child: Text(isEdit ? 'Update' : 'Save'),
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

    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final meals = widget.state.savedMeals;

        return Scaffold(
          backgroundColor: t.bg,
          appBar: AppBar(
            title: Text(
              'Saved Meals',
              style: TextStyle(color: t.ink, fontWeight: FontWeight.w600, fontSize: 18),
            ),
            backgroundColor: t.surface,
            elevation: 0,
            iconTheme: IconThemeData(color: t.ink),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Add Favorite Meal',
                onPressed: () => _showAddEditDialog(),
              ),
            ],
          ),
          body: widget.state.isLoadingSavedMeals && meals.isEmpty
              ? Center(child: CircularProgressIndicator(color: t.ink))
              : meals.isEmpty
                  ? _buildEmptyState(t)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: meals.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, i) {
                        final meal = meals[i];
                        return _buildMealCard(meal, t);
                      },
                    ),
        );
      },
    );
  }

  Widget _buildEmptyState(ZenThemeTokens t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border_rounded, size: 56, color: t.inkFaint),
            const SizedBox(height: 16),
            Text(
              'No Saved Meals Yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Save your frequent breakfasts, shakes, or recipes to log them in 1 tap without calling AI.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.inkMuted, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddEditDialog(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Favorite Meal'),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.ink,
                foregroundColor: t.onInk,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealCard(Map<String, dynamic> meal, ZenThemeTokens t) {
    final id = meal['id'] as String? ?? '';
    final name = meal['name'] as String? ?? 'Meal';
    final rawText = meal['raw_text'] as String? ?? '';
    final extracted = (meal['extracted'] as Map?) ?? {};
    final isPinned = meal['pinned'] == true;
    final useCount = (meal['use_count'] as int?) ?? 0;

    final protein = (extracted['protein_g'] as num?)?.toDouble();
    final calories = (extracted['calories'] as num?)?.toInt() ?? (extracted['calories_kcal'] as num?)?.toInt();
    final carbs = (extracted['carbs_g'] as num?)?.toDouble();
    final fat = (extracted['fat_g'] as num?)?.toDouble();

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isPinned ? t.ink : t.line, width: isPinned ? 1.5 : 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: t.ink),
                ),
              ),
              IconButton(
                icon: Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 20,
                  color: isPinned ? t.ink : t.inkFaint,
                ),
                tooltip: isPinned ? 'Unpin' : 'Pin to bar',
                onPressed: () => widget.state.updateSavedMeal(id, pinned: !isPinned),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 20, color: t.inkMuted),
                onSelected: (val) {
                  if (val == 'edit') {
                    _showAddEditDialog(meal: meal);
                  } else if (val == 'delete') {
                    _confirmDelete(id, name);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                ],
              ),
            ],
          ),
          if (rawText.isNotEmpty && rawText != name) ...[
            const SizedBox(height: 2),
            Text(
              rawText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (protein != null)
                _Chip(label: '${protein.toStringAsFixed(0)}g protein', t: t, isPrimary: true),
              if (calories != null)
                _Chip(label: '$calories kcal', t: t),
              if (carbs != null)
                _Chip(label: '${carbs.toStringAsFixed(0)}g carbs', t: t),
              if (fat != null)
                _Chip(label: '${fat.toStringAsFixed(0)}g fat', t: t),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Logged $useCount ${useCount == 1 ? 'time' : 'times'}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.inkFaint),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  final ok = await widget.state.logSavedMeal(id);
                  if (mounted && ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Logged "$name" to today'),
                        backgroundColor: t.ink,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Log 1×'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.surfaceAlt,
                  foregroundColor: t.ink,
                  elevation: 0,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: t.line),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text('Past logs using this favorite will not be affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dlgCtx);
              widget.state.deleteSavedMeal(id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final ZenThemeTokens t;
  final bool isPrimary;

  const _Chip({required this.label, required this.t, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPrimary ? t.ink : t.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isPrimary ? t.ink : t.line),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isPrimary ? t.onInk : t.ink,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
