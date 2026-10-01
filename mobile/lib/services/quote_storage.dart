import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a daily motivational quote with 24-hour persistence.
class DailyQuote {
  final String quote;
  final String author;
  final String date;
  final String source; // 'local_cache' | 'backend_db' | 'rapidapi' | 'fallback'

  const DailyQuote({
    required this.quote,
    required this.author,
    required this.date,
    this.source = 'local_cache',
  });

  Map<String, dynamic> toJson() => {
        'quote': quote,
        'author': author,
        'date': date,
        'source': source,
      };

  factory DailyQuote.fromJson(Map<String, dynamic> json, {String defaultDate = ''}) {
    return DailyQuote(
      quote: json['quote'] as String? ?? 'Consistency beats intensity. What you do every day matters more than what you do once in a while.',
      author: json['author'] as String? ?? 'James Clear',
      date: (json['date'] as String?) ?? defaultDate,
      source: (json['source'] as String?) ?? 'local_cache',
    );
  }
}

/// Persistent local cache and offline-first resolver for daily quotes.
///
/// Follows the architecture:
/// 1. Check Phone Local Cache (Offline First: SharedPreferences: zen_quote_YYYY-MM-DD).
///    - If found: return immediately (100% offline ready).
/// 2. If not found: call backend DB cache (which in turn queries RapidAPI or DB fallback).
///    - On response: save to phone local cache for that date and return.
/// 3. If offline / network error: pick from local curated fallback pool, save to cache, and return.
class QuoteStorage {
  static const String _prefix = 'zen_quote_';

  /// Curated fallback pool for 100% offline edge cases
  static const List<Map<String, String>> _localFallbackPool = [
    {
      'quote': 'Consistency beats intensity. What you do every day matters more than what you do once in a while.',
      'author': 'James Clear',
    },
    {
      'quote': 'If you are going through hell, keep going.',
      'author': 'Winston Churchill',
    },
    {
      'quote': 'We do not rise to the level of our expectations, we fall to the level of our training.',
      'author': 'Archilochus',
    },
    {
      'quote': 'Waste no more time arguing about what a good man should be. Be one.',
      'author': 'Marcus Aurelius',
    },
    {
      'quote': 'Small disciplines repeated with consistency every day lead to great achievements gained slowly over time.',
      'author': 'John C. Maxwell',
    },
    {
      'quote': 'It is not the mountain we conquer, but ourselves.',
      'author': 'Sir Edmund Hillary',
    },
    {
      'quote': 'Discipline is choosing between what you want now and what you want most.',
      'author': 'Abraham Lincoln',
    },
    {
      'quote': 'Do not pray for an easy life, pray for the strength to endure a difficult one.',
      'author': 'Bruce Lee',
    },
    {
      'quote': 'Action is the foundational key to all success.',
      'author': 'Pablo Picasso',
    },
    {
      'quote': 'The body achieves what the mind believes.',
      'author': 'Napoleon Hill',
    },
    {
      'quote': 'You do not have to be extreme, just consistent.',
      'author': 'Unknown',
    },
    {
      'quote': 'He who has a why to live can bear almost any how.',
      'author': 'Friedrich Nietzsche',
    },
  ];

  /// Reads quote from phone local cache (SharedPreferences: zen_quote_YYYY-MM-DD).
  static Future<DailyQuote?> getLocalQuote(String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$date');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return DailyQuote.fromJson(decoded, defaultDate: date);
      }
    } catch (_) {}
    return null;
  }

  /// Writes quote to phone local cache (SharedPreferences: zen_quote_YYYY-MM-DD).
  static Future<void> saveLocalQuote(DailyQuote quote) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefix${quote.date}',
        jsonEncode(quote.toJson()),
      );
    } catch (_) {}
  }

  /// Picks deterministic fallback quote based on date string hash for 100% offline edge cases.
  static DailyQuote getLocalFallback(String date) {
    int hash = 0;
    for (int i = 0; i < date.length; i++) {
      hash = (hash * 31 + date.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final item = _localFallbackPool[hash % _localFallbackPool.length];
    return DailyQuote(
      quote: item['quote']!,
      author: item['author']!,
      date: date,
      source: 'local_fallback',
    );
  }

  /// Complete 3-step offline-first resolution pipeline:
  /// 1. Check local cache (zen_quote_YYYY-MM-DD). If found -> return immediately.
  /// 2. If not found, call remote fetcher. If successful -> save to local cache & return.
  /// 3. If remote fails/offline -> use deterministic local fallback -> save to local cache & return.
  static Future<DailyQuote> getOrFetchQuote(
    String date, {
    Future<Map<String, dynamic>?> Function(String date)? fetchRemote,
  }) async {
    // Step 1: Check phone local cache (Offline First)
    final local = await getLocalQuote(date);
    if (local != null) {
      return local;
    }

    // Step 2: Call backend DB cache / RapidAPI
    if (fetchRemote != null) {
      try {
        final remote = await fetchRemote(date);
        if (remote != null && remote['quote'] != null) {
          final quote = DailyQuote(
            quote: (remote['quote'] as String).trim(),
            author: ((remote['author'] as String?) ?? 'Unknown').trim(),
            date: date,
            source: (remote['source'] as String?) ?? 'backend',
          );
          await saveLocalQuote(quote);
          return quote;
        }
      } catch (_) {}
    }

    // Step 3: Local fallback if backend unavailable
    final fallback = getLocalFallback(date);
    await saveLocalQuote(fallback);
    return fallback;
  }
}
