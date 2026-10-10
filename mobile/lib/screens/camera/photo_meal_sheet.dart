import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/zen_colors.dart';
import '../../state/zen_state.dart';

class PhotoMealReviewSheet extends StatefulWidget {
  final ZenState state;
  final File imageFile;
  final Map<String, dynamic> draftData;

  const PhotoMealReviewSheet({
    super.key,
    required this.state,
    required this.imageFile,
    required this.draftData,
  });

  static Future<bool?> show(
    BuildContext context, {
    required ZenState state,
    required File imageFile,
    required Map<String, dynamic> draftData,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PhotoMealReviewSheet(
        state: state,
        imageFile: imageFile,
        draftData: draftData,
      ),
    );
  }

  @override
  State<PhotoMealReviewSheet> createState() => _PhotoMealReviewSheetState();
}

class _PhotoMealReviewSheetState extends State<PhotoMealReviewSheet> {
  late List<Map<String, dynamic>> _items;
  double _portionMultiplier = 1.0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final rawItems = (widget.draftData['items'] as List?) ?? [];
    _items = rawItems.map((it) {
      if (it is Map) {
        return Map<String, dynamic>.from(it);
      }
      return <String, dynamic>{};
    }).toList();
  }

  double get _totalProtein {
    double sum = 0;
    for (final it in _items) {
      final p = (it['protein_g'] as num?)?.toDouble() ?? 0.0;
      sum += p;
    }
    return sum * _portionMultiplier;
  }

  int get _totalCalories {
    double sum = 0;
    for (final it in _items) {
      final c = (it['calories'] as num?)?.toDouble() ?? 0.0;
      sum += c;
    }
    return (sum * _portionMultiplier).round();
  }

  double get _totalCarbs {
    double sum = 0;
    for (final it in _items) {
      final c = (it['carbs_g'] as num?)?.toDouble() ?? 0.0;
      sum += c;
    }
    return sum * _portionMultiplier;
  }

  double get _totalFat {
    double sum = 0;
    for (final it in _items) {
      final f = (it['fat_g'] as num?)?.toDouble() ?? 0.0;
      sum += f;
    }
    return sum * _portionMultiplier;
  }

  void _editItem(int index) {
    final it = _items[index];
    final nameCtrl = TextEditingController(text: it['name']?.toString() ?? '');
    final portionCtrl = TextEditingController(text: it['portion']?.toString() ?? '');
    final proteinCtrl = TextEditingController(text: (it['protein_g'] ?? 0).toString());
    final calCtrl = TextEditingController(text: (it['calories'] ?? 0).toString());
    final carbsCtrl = TextEditingController(text: (it['carbs_g'] ?? 0).toString());
    final fatCtrl = TextEditingController(text: (it['fat_g'] ?? 0).toString());

    showDialog(
      context: context,
      builder: (dlgCtx) {
        final t = context.zen;
        return AlertDialog(
          backgroundColor: t.surface,
          title: Text('Edit Item', style: TextStyle(color: t.ink)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Food Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portionCtrl,
                  decoration: const InputDecoration(labelText: 'Portion (e.g. 1 bowl)'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: proteinCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Protein (g)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: calCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Calories (kcal)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: carbsCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Carbs (g)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: fatCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Fat (g)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _items[index] = {
                    ...it,
                    'name': nameCtrl.text.trim().isEmpty ? 'Food item' : nameCtrl.text.trim(),
                    'portion': portionCtrl.text.trim(),
                    'protein_g': double.tryParse(proteinCtrl.text.trim()) ?? 0.0,
                    'calories': int.tryParse(calCtrl.text.trim()) ?? 0,
                    'carbs_g': double.tryParse(carbsCtrl.text.trim()) ?? 0.0,
                    'fat_g': double.tryParse(fatCtrl.text.trim()) ?? 0.0,
                  };
                });
                Navigator.pop(dlgCtx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: t.ink,
                foregroundColor: t.onInk,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _addNewItem() {
    final nameCtrl = TextEditingController();
    final portionCtrl = TextEditingController(text: '1 serving');
    final proteinCtrl = TextEditingController(text: '10');
    final calCtrl = TextEditingController(text: '150');

    showDialog(
      context: context,
      builder: (dlgCtx) {
        final t = context.zen;
        return AlertDialog(
          backgroundColor: t.surface,
          title: Text('Add Item', style: TextStyle(color: t.ink)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Food Name (e.g. Boiled egg)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: portionCtrl,
                decoration: const InputDecoration(labelText: 'Portion'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: proteinCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Protein (g)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: calCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Calories (kcal)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  setState(() {
                    _items.add({
                      'name': name,
                      'portion': portionCtrl.text.trim(),
                      'protein_g': double.tryParse(proteinCtrl.text.trim()) ?? 0.0,
                      'calories': int.tryParse(calCtrl.text.trim()) ?? 0,
                      'carbs_g': 0.0,
                      'fat_g': 0.0,
                    });
                  });
                }
                Navigator.pop(dlgCtx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: t.ink,
                foregroundColor: t.onInk,
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logMeal() async {
    if (_items.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      final names = _items.map((i) => i['name']?.toString() ?? '').where((s) => s.isNotEmpty).join(', ');
      final portionText = _portionMultiplier != 1.0 ? ' (${_portionMultiplier.toStringAsFixed(1)}x portion)' : '';
      final logText = 'Photo meal: $names$portionText';

      final extracted = {
        'meal_type': 'Meal',
        'protein_g': double.parse(_totalProtein.toStringAsFixed(1)),
        'calories': _totalCalories,
        'calories_kcal': _totalCalories,
        'carbs_g': double.parse(_totalCarbs.toStringAsFixed(1)),
        'fat_g': double.parse(_totalFat.toStringAsFixed(1)),
        'confidence': 0.9,
      };

      final meta = {
        'source': 'photo',
        'estimate': true,
        'portion_multiplier': _portionMultiplier,
        'items': _items,
      };

      final ok = await widget.state.addStructuredLog(
        text: logText,
        extracted: extracted,
        source: 'photo',
        meta: meta,
      );

      if (mounted) {
        setState(() => _isSaving = false);
        if (ok) {
          HapticFeedback.mediumImpact();
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save meal log. Try again.')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    final notes = widget.draftData['notes']?.toString();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    widget.imageFile,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Review Plate Analysis',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.ink,
                        ),
                      ),
                      Text(
                        'Visual AI estimate · Tap numbers to edit',
                        style: TextStyle(fontSize: 12, color: t.inkMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: t.inkFaint),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              children: [
                // Portion multiplier chips
                Text(
                  'PORTION ADJUSTMENT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: t.inkMuted,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [0.5, 0.75, 1.0, 1.25, 1.5].map((mult) {
                      final isSel = (_portionMultiplier - mult).abs() < 0.05;
                      final label = mult == 0.5
                          ? 'Ate half (0.5x)'
                          : mult == 1.0
                              ? 'Full plate (1.0x)'
                              : '${mult}x';
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: isSel,
                          onSelected: (_) {
                            setState(() => _portionMultiplier = mult);
                          },
                          selectedColor: t.ink,
                          labelStyle: TextStyle(
                            color: isSel ? t.onInk : t.ink,
                            fontSize: 12,
                            fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                          ),
                          backgroundColor: t.surfaceAlt,
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 16),

                // AI Notes if present
                if (notes != null && notes.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.infoTint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.line),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome, size: 16, color: t.infoText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            notes,
                            style: TextStyle(fontSize: 12.5, color: t.ink, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Items list
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'DETECTED ITEMS (${_items.length})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: t.inkMuted,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addNewItem,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add item', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: t.ink,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                ..._items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final name = item['name']?.toString() ?? 'Item';
                  final portion = item['portion']?.toString() ?? '';
                  final prot = ((item['protein_g'] as num?)?.toDouble() ?? 0.0) * _portionMultiplier;
                  final cal = (((item['calories'] as num?)?.toDouble() ?? 0.0) * _portionMultiplier).round();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.line),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: t.ink,
                                ),
                              ),
                              if (portion.isNotEmpty)
                                Text(
                                  portion,
                                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                                ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                children: [
                                  Text(
                                    '${prot.toStringAsFixed(1)}g protein',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: t.successText,
                                    ),
                                  ),
                                  Text(
                                    '$cal kcal',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: t.inkMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit_outlined, size: 18, color: t.inkMuted),
                          onPressed: () => _editItem(idx),
                          tooltip: 'Edit item',
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: t.dangerFill),
                          onPressed: () {
                            setState(() {
                              _items.removeAt(idx);
                            });
                          },
                          tooltip: 'Remove',
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          // Total Bar & Log Button
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: BoxDecoration(
              color: t.surface,
              border: Border(top: BorderSide(color: t.line)),
              boxShadow: [
                BoxShadow(
                  color: t.ink.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL ESTIMATE',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: t.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '${_totalProtein.toStringAsFixed(1)}g',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: t.successText,
                              ),
                            ),
                            Text(
                              ' protein  ·  $_totalCalories kcal',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: t.ink,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSaving || _items.isEmpty ? null : _logMeal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.ink,
                      foregroundColor: t.onInk,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.onInk,
                            ),
                          )
                        : Text(
                            'Log Meal (${_totalProtein.toStringAsFixed(0)}g protein)',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
