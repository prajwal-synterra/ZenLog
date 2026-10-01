import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/services/quote_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DailyQuote 3-Step Offline-First Architecture Tests', () {
    const testDate = '2026-10-05';

    test('Step 1 & 2: Remote fetch saves to local phone cache (zen_quote_YYYY-MM-DD)', () async {
      int remoteCalls = 0;
      Future<Map<String, dynamic>?> mockRemote(String date) async {
        remoteCalls++;
        return {
          'quote': 'The secret of getting ahead is getting started.',
          'author': 'Mark Twain',
          'source': 'rapidapi',
        };
      }

      // First call: cache is empty, calls remote
      final result1 = await QuoteStorage.getOrFetchQuote(testDate, fetchRemote: mockRemote);

      expect(remoteCalls, 1);
      expect(result1.quote, 'The secret of getting ahead is getting started.');
      expect(result1.author, 'Mark Twain');
      expect(result1.date, testDate);

      // Verify it was persisted in SharedPreferences under key "zen_quote_2026-10-05"
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('zen_quote_$testDate'), isTrue);

      // Step 1: Subsequent call finds in local cache and renders immediately (0 remote calls)
      final result2 = await QuoteStorage.getOrFetchQuote(testDate, fetchRemote: mockRemote);

      expect(remoteCalls, 1, reason: 'Remote fetcher must NOT be called when local cache is present (offline first)');
      expect(result2.quote, 'The secret of getting ahead is getting started.');
      expect(result2.author, 'Mark Twain');
    });

    test('Step 1: Direct local cache hit returns 100% offline ready quote', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'zen_quote_$testDate',
        '{"quote":"Perseverance is not a long race; it is many short races one after another.","author":"Walter Bagehot","date":"$testDate","source":"cached"}',
      );

      bool remoteCalled = false;
      final quote = await QuoteStorage.getOrFetchQuote(
        testDate,
        fetchRemote: (d) async {
          remoteCalled = true;
          return null;
        },
      );

      expect(remoteCalled, isFalse);
      expect(quote.quote, contains('Perseverance is not a long race'));
      expect(quote.author, 'Walter Bagehot');
    });

    test('Step 3: If remote fails/limit reached, returns fallback quote & saves to cache', () async {
      Future<Map<String, dynamic>?> failingRemote(String date) async {
        throw Exception('RapidAPI 429 Rate Limit Exceeded or Network Offline');
      }

      final fallbackQuote = await QuoteStorage.getOrFetchQuote(testDate, fetchRemote: failingRemote);

      expect(fallbackQuote.quote.isNotEmpty, isTrue);
      expect(fallbackQuote.author.isNotEmpty, isTrue);
      expect(fallbackQuote.source, 'local_fallback');

      // Verify fallback was cached in SharedPreferences for this date
      final cached = await QuoteStorage.getLocalQuote(testDate);
      expect(cached, isNotNull);
      expect(cached!.quote, fallbackQuote.quote);
      expect(cached.author, fallbackQuote.author);
    });

    test('Deterministic fallback produces identical quote for same date', () {
      final q1 = QuoteStorage.getLocalFallback('2026-10-05');
      final q2 = QuoteStorage.getLocalFallback('2026-10-05');

      expect(q1.quote, q2.quote);
      expect(q1.author, q2.author);
    });

    test('Serialization and Deserialization round-trip', () {
      const original = DailyQuote(
        quote: 'Do what you can, with what you have, where you are.',
        author: 'Theodore Roosevelt',
        date: '2026-10-05',
        source: 'rapidapi',
      );

      final json = original.toJson();
      final reconstructed = DailyQuote.fromJson(json);

      expect(reconstructed.quote, original.quote);
      expect(reconstructed.author, original.author);
      expect(reconstructed.date, original.date);
      expect(reconstructed.source, original.source);
    });
  });
}
