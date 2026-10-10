import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/zen_colors.dart';
import '../../services/api_service.dart';
import '../../services/ocr_service.dart';
import '../../state/zen_state.dart';
import '../foods/my_products_screen.dart';

class LabelScanScreen extends StatefulWidget {
  final ZenState state;

  const LabelScanScreen({super.key, required this.state});

  static Future<void> push(BuildContext context, ZenState state) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LabelScanScreen(state: state)),
    );
  }

  @override
  State<LabelScanScreen> createState() => _LabelScanScreenState();
}

class _LabelScanScreenState extends State<LabelScanScreen> {
  final ImagePicker _picker = ImagePicker();
  final OcrService _ocrService = OcrService();
  final ApiService _api = ApiService();

  File? _imageFile;
  bool _isProcessing = false;
  String _statusText = '';
  String? _errorMessage;

  // Scan result state
  Map<String, dynamic>? _scanData;
  double _servings = 1.0;
  double? _customGrams;
  Map<String, dynamic>? _dayImpact;
  bool _isSavingProduct = false;
  bool _isLogging = false;

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;

      final file = File(picked.path);
      setState(() {
        _imageFile = file;
        _scanData = null;
        _dayImpact = null;
        _errorMessage = null;
        _isProcessing = true;
        _statusText = 'Running on-device OCR...';
      });

      // Step 1: On-device OCR check
      final ocrResult = await _ocrService.processLabelImage(file);

      if (ocrResult.isHighConfidence) {
        setState(() {
          _statusText = 'Label text recognized! Analyzing nutrition profile...';
        });
      } else {
        setState(() {
          _statusText = 'Enhancing with Gemini multimodal vision...';
        });
      }

      // Step 2: Call backend /api/foods/scan with hybrid approach
      final res = await _api.scanFoodLabel(
        images: [file],
        ocrText: ocrResult.isHighConfidence ? ocrResult.text : null,
      );

      if (res.ok && res.data != null) {
        setState(() {
          _scanData = res.data;
          _isProcessing = false;
          _statusText = '';
        });
        _evaluateDayImpact();
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage = res.error ?? 'Could not read nutrition table. Please retake photo clearly.';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Error processing label: $e';
      });
    }
  }

  Future<void> _evaluateDayImpact() async {
    final scanId = _scanData?['scan_id'] as String?;
    if (scanId == null) return;

    final product = (_scanData?['product'] as Map?) ?? {};
    final servingSizeG = (product['serving_size_g'] as num?)?.toDouble() ?? 100.0;
    final portionGrams = _customGrams ?? (servingSizeG * _servings);

    final res = await _api.evaluateFoodScan(
      scanId,
      grams: portionGrams,
      day: widget.state.selectedDate,
    );

    if (res != null && mounted) {
      setState(() {
        _dayImpact = res;
      });
    }
  }

  Future<void> _saveToMyProducts() async {
    if (_scanData == null) return;
    setState(() => _isSavingProduct = true);

    final product = (_scanData!['product'] as Map?) ?? {};
    final per100 = (_scanData!['per_100g'] as Map?) ?? {};
    final ingredients = (_scanData!['ingredients'] as List?)?.map((e) => e.toString()).toList() ?? [];

    final payload = {
      'name': product['name'] ?? 'Packaged Product',
      'brand': product['brand'],
      'pack_size_g': product['pack_size_g'],
      'serving_size_g': product['serving_size_g'] ?? 100.0,
      'per_100g': per100,
      'ingredients': ingredients,
    };

    final saved = await _api.saveProduct(payload);
    if (mounted) {
      setState(() => _isSavingProduct = false);
      if (saved != null) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product['name'] ?? 'Product'} saved to My Products!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _logScanToDay() async {
    final scanId = _scanData?['scan_id'] as String?;
    if (scanId == null) return;

    setState(() => _isLogging = true);
    final product = (_scanData?['product'] as Map?) ?? {};
    final servingSizeG = (product['serving_size_g'] as num?)?.toDouble() ?? 100.0;
    final portionGrams = _customGrams ?? (servingSizeG * _servings);

    final ok = await widget.state.logFoodScan(
      scanId,
      grams: portionGrams,
    );

    if (mounted) {
      setState(() => _isLogging = false);
      if (ok) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logged ${product['name'] ?? 'product'} to today!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to log product.')),
        );
      }
    }
  }

  void _editNutritionValue(String field, String label, num? currentVal) {
    final ctrl = TextEditingController(text: currentVal != null ? currentVal.toString() : '');
    showDialog(
      context: context,
      builder: (dlgCtx) {
        final t = context.zen;
        return AlertDialog(
          backgroundColor: t.surface,
          title: Text('Edit $label', style: TextStyle(color: t.ink)),
          content: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: '$label per 100g',
              suffixText: field.endsWith('_mg') ? 'mg' : field.endsWith('_kcal') ? 'kcal' : 'g',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final val = double.tryParse(ctrl.text.trim());
                Navigator.pop(dlgCtx);
                if (val != null && _scanData != null) {
                  final scanId = _scanData!['scan_id'] as String;
                  final per100 = Map<String, dynamic>.from((_scanData!['per_100g'] as Map?) ?? {});
                  per100[field] = val;

                  final updated = await _api.updateFoodScan(scanId, {
                    'per_100g': per100,
                  });

                  if (updated != null && mounted) {
                    setState(() {
                      _scanData = updated;
                    });
                    _evaluateDayImpact();
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: t.ink,
                foregroundColor: t.onInk,
              ),
              child: const Text('Save & Re-score'),
            ),
          ],
        );
      },
    );
  }

  Color _getScoreColor(int score, ZenThemeTokens t) {
    if (score >= 70) return t.successFill;
    if (score >= 50) return t.infoFill;
    if (score >= 30) return t.warnFill;
    return t.dangerFill;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;

    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(
        backgroundColor: t.surface,
        elevation: 0,
        title: Text(
          'Packaged Food Scanner',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: t.ink),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.bookmark_outline_rounded, color: t.ink),
            tooltip: 'My Products',
            onPressed: () => MyProductsScreen.push(context, widget.state),
          ),
        ],
      ),
      body: _buildBody(t),
    );
  }

  Widget _buildBody(ZenThemeTokens t) {
    if (_isProcessing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(strokeWidth: 3, color: t.accent),
              ),
              const SizedBox(height: 20),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: t.ink),
              ),
              const SizedBox(height: 8),
              Text(
                'Analyzing nutrients, flags, and portion impact…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (_scanData == null) {
      return _buildPickerState(t);
    }

    return _buildResultView(t);
  }

  Widget _buildPickerState(ZenThemeTokens t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 30),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              shape: BoxShape.circle,
              border: Border.all(color: t.line, width: 2),
            ),
            child: Icon(Icons.qr_code_scanner_rounded, size: 40, color: t.accent),
          ),
          const SizedBox(height: 20),
          Text(
            'Scan Nutrition Label',
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: t.ink),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Photograph the nutrition table and ingredients list on any packaged snack, drink, or protein bar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: t.inkMuted, height: 1.4),
            ),
          ),
          const SizedBox(height: 32),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.dangerTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.dangerFill.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: t.dangerFill),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(fontSize: 13, color: t.dangerText),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.ink,
                      foregroundColor: t.onInk,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.ink,
                      side: BorderSide(color: t.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),
          // My products quick shortcut
          GestureDetector(
            onTap: () => MyProductsScreen.push(context, widget.state),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.bookmark_added_rounded, color: t.accent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Saved Products',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink),
                        ),
                        Text(
                          'Log previously scanned foods in 1 tap without AI calls',
                          style: TextStyle(fontSize: 12, color: t.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: t.inkMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultView(ZenThemeTokens t) {
    final product = (_scanData!['product'] as Map?) ?? {};
    final per100 = (_scanData!['per_100g'] as Map?) ?? {};
    final score = (_scanData!['score'] as Map?) ?? {};
    final validation = (_scanData!['validation'] as Map?) ?? {};
    final flags = (_scanData!['flags'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final reasons = (score['reasons'] as List?)?.map((e) => e.toString()).toList() ?? [];

    final scoreVal = (score['value'] as num?)?.toInt() ?? 50;
    final grade = score['grade']?.toString() ?? 'Okay';
    final scoreColor = _getScoreColor(scoreVal, t);

    final warnings = (validation['warnings'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            children: [
              // Product Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_imageFile != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(_imageFile!, width: 44, height: 44, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product['name']?.toString() ?? 'Packaged Food',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: t.ink,
                          ),
                        ),
                        if (product['brand'] != null)
                          Text(
                            product['brand'].toString(),
                            style: TextStyle(fontSize: 13, color: t.inkMuted),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.bookmark_add_outlined,
                      color: _isSavingProduct ? t.inkFaint : t.ink,
                    ),
                    tooltip: 'Save to My Products',
                    onPressed: _isSavingProduct ? null : _saveToMyProducts,
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: t.inkMuted),
                    tooltip: 'Scan another',
                    onPressed: () => setState(() => _scanData = null),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Score Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.surfaceAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.line),
                ),
                child: Row(
                  children: [
                    // Score Circle
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: scoreColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: scoreColor, width: 2.5),
                      ),
                      child: Center(
                        child: Text(
                          '$scoreVal',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: scoreColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: scoreColor,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              child: Text(
                                grade.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'ZenLog Goal-Aware Rating',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t.ink,
                          ),
                        ),
                        Text(
                          'Heuristic rating · Not medical advice',
                          style: TextStyle(fontSize: 11, color: t.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Top reasons
            if (reasons.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: reasons.map((r) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: t.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.line),
                    ),
                    child: Text(
                      r,
                      style: TextStyle(fontSize: 12, color: t.ink, fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
            ],

            // Flags / Ultra-processed ingredients
            if (flags.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.warnTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.warnFill.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: t.warnText),
                        const SizedBox(width: 6),
                        Text(
                          'Additives & Processed Ingredients Flagged:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.warnText),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: flags.map((f) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            f,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.warnText),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Sanity warnings
            if (warnings.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.dangerTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.dangerFill.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: t.dangerFill),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Label sanity check: ${warnings.join(', ')}. Tap numbers below to correct.',
                        style: TextStyle(fontSize: 12, color: t.dangerText),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Nutrition Table (per 100g)
            Text(
              'NUTRITION FACTS PER 100g (TAP TO EDIT)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: t.inkMuted,
              ),
            ),
            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.line),
              ),
              child: Column(
                children: [
                  _buildNutritionRow('Energy', per100['energy_kcal'], 'kcal', 'energy_kcal', t),
                  const Divider(height: 1),
                  _buildNutritionRow('Protein', per100['protein_g'], 'g', 'protein_g', t),
                  const Divider(height: 1),
                  _buildNutritionRow('Carbohydrates', per100['carbs_g'], 'g', 'carbs_g', t),
                  const Divider(height: 1),
                  _buildNutritionRow('Sugars', per100['sugar_g'], 'g', 'sugar_g', t),
                  const Divider(height: 1),
                  _buildNutritionRow('Total Fat', per100['fat_g'], 'g', 'fat_g', t),
                  const Divider(height: 1),
                  _buildNutritionRow('Saturated Fat', per100['sat_fat_g'], 'g', 'sat_fat_g', t),
                  const Divider(height: 1),
                  _buildNutritionRow('Dietary Fiber', per100['fiber_g'], 'g', 'fiber_g', t),
                  const Divider(height: 1),
                  _buildNutritionRow('Sodium', per100['sodium_mg'], 'mg', 'sodium_mg', t),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Portion Evaluator
            Text(
              'PORTION TO EAT & DAY IMPACT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: t.inkMuted,
              ),
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Serving Size: ${product['serving_size_g'] ?? 100}g',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.ink),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: _servings > 0.5
                                ? () {
                                    setState(() {
                                      _servings = (_servings - 0.5).clamp(0.5, 10.0);
                                      _customGrams = null;
                                    });
                                    _evaluateDayImpact();
                                  }
                                : null,
                          ),
                          Text(
                            '${_servings.toStringAsFixed(1)} serv',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: t.ink),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              setState(() {
                                _servings = (_servings + 0.5).clamp(0.5, 10.0);
                                _customGrams = null;
                              });
                              _evaluateDayImpact();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),

                  if (_dayImpact != null) ...[
                    const Divider(height: 16),
                    Text(
                      _dayImpact!['summary']?.toString() ?? '',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (_dayImpact!['pct_remaining_protein'] != null)
                          Text(
                            '${(_dayImpact!['pct_remaining_protein'] as num).toStringAsFixed(0)}% of remaining protein · ',
                            style: TextStyle(fontSize: 12, color: t.successText, fontWeight: FontWeight.w600),
                          ),
                        if (_dayImpact!['pct_daily_calories'] != null)
                          Text(
                            '${(_dayImpact!['pct_daily_calories'] as num).toStringAsFixed(0)}% of calorie budget',
                            style: TextStyle(fontSize: 12, color: t.inkMuted),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),

      // Bottom Bar
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
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLogging ? null : _logScanToDay,
            style: ElevatedButton.styleFrom(
              backgroundColor: t.ink,
              foregroundColor: t.onInk,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLogging
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: t.onInk),
                  )
                : Text(
                    'Log to Today (${(_dayImpact?['portion_macros']?['protein_g'] ?? 0)}g protein)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    ],
  );
}

  Widget _buildNutritionRow(String name, num? value, String unit, String field, ZenThemeTokens t) {
    return InkWell(
      onTap: () => _editNutritionValue(field, name, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name, style: TextStyle(fontSize: 13, color: t.ink)),
            Row(
              children: [
                Text(
                  value != null ? '$value $unit' : '—',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: value != null ? t.ink : t.inkFaint,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.edit_outlined, size: 14, color: t.inkMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
