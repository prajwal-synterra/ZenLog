import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  final String text;
  final double confidence;
  final bool isHighConfidence;
  final List<String> matchedKeywords;

  const OcrResult({
    required this.text,
    required this.confidence,
    required this.isHighConfidence,
    required this.matchedKeywords,
  });
}

class OcrService {
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal();

  TextRecognizer? _textRecognizer;

  TextRecognizer get _recognizer {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _textRecognizer!;
  }

  static const List<String> _nutritionKeywords = [
    'nutrition',
    'nutritional',
    'energy',
    'kcal',
    'calories',
    'protein',
    'carbohydrate',
    'carbs',
    'total fat',
    'saturated fat',
    'fat',
    'sugar',
    'sugars',
    'dietary fiber',
    'fibre',
    'fiber',
    'sodium',
    'serving',
    'per 100g',
    'per 100ml',
    'per 100 g',
    'per 100 ml',
  ];

  /// Runs on-device OCR using ML Kit.
  /// Evaluates whether the recognized text contains enough structured nutrition
  /// keywords to qualify as high-confidence OCR.
  Future<OcrResult> processLabelImage(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await _recognizer.processImage(inputImage);
      final rawText = recognizedText.text.trim();

      if (rawText.isEmpty) {
        return const OcrResult(
          text: '',
          confidence: 0.0,
          isHighConfidence: false,
          matchedKeywords: [],
        );
      }

      final lower = rawText.toLowerCase();
      final matched = <String>[];
      for (final kw in _nutritionKeywords) {
        if (lower.contains(kw)) {
          matched.add(kw);
        }
      }

      // Check if numeric values appear in the text (nutrition facts have numbers)
      final hasNumbers = RegExp(r'\d+(\.\d+)?').hasMatch(lower);

      // Scoring heuristic:
      // - 4+ keywords with numbers -> confidence 0.85+ (High)
      // - 3 keywords with numbers -> confidence 0.75 (High)
      // - 2 keywords -> confidence 0.50 (Low / borderline)
      // - 0-1 keywords -> confidence 0.20 (Low -> fallback to Gemini vision)
      double confidence = 0.0;
      if (matched.length >= 4 && hasNumbers) {
        confidence = 0.90;
      } else if (matched.length >= 3 && hasNumbers) {
        confidence = 0.78;
      } else if (matched.length >= 2) {
        confidence = 0.55;
      } else if (matched.isNotEmpty) {
        confidence = 0.35;
      } else {
        confidence = 0.10;
      }

      final isHigh = confidence >= 0.75;

      return OcrResult(
        text: rawText,
        confidence: confidence,
        isHighConfidence: isHigh,
        matchedKeywords: matched,
      );
    } catch (e) {
      if (kDebugMode) {
        print('OcrService error: $e');
      }
      return const OcrResult(
        text: '',
        confidence: 0.0,
        isHighConfidence: false,
        matchedKeywords: [],
      );
    }
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
