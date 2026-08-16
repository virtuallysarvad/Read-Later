import 'package:flutter_test/flutter_test.dart';
import 'package:read_later/utils/fuzzy_search.dart';

void main() {
  group('fuzzyScore', () {
    test('matches exact substrings case-insensitively', () {
      expect(fuzzyScore('read', 'Reading later'), isNotNull);
      expect(fuzzyScore('READ', 'reading later'), isNotNull);
      expect(fuzzyScore('the new york', 'The New York Times'), isNotNull);
    });

    test('matches subsequences (skips allowed, order kept)', () {
      expect(fuzzyScore('nyt', 'The New York Times'), isNotNull);
      expect(fuzzyScore('rdltr', 'Read Later'), isNotNull);
      // Order matters: reversed characters are not a subsequence.
      expect(fuzzyScore('ynt', 'The New York Times'), isNull);
    });

    test('tolerates a few typos', () {
      expect(fuzzyScore('reidng', 'reading'), isNotNull);
      expect(fuzzyScore('aplle', 'apple'), isNotNull);
      expect(fuzzyScore('teh', 'the'), isNotNull);
    });

    test('rejects clear non-matches', () {
      expect(fuzzyScore('xyz', 'hello world'), isNull);
      expect(fuzzyScore('bookmarks', 'hello world'), isNull);
      // A short query must not match a long unrelated text.
      expect(fuzzyScore('zz', 'the quick brown fox jumps over the lazy dog'),
          isNull);
    });

    test('scores substring matches better than fuzzy ones', () {
      final exact = fuzzyScore('read', 'Reading list');
      final typo = fuzzyScore('read', 'Reed article');
      expect(exact, isNotNull);
      expect(typo, isNotNull);
      expect(exact!, lessThan(typo!));
    });

    test('prefers earlier substring occurrences', () {
      final early = fuzzyScore('read', 'Read this');
      final late = fuzzyScore('read', 'Please read this');
      expect(early!, lessThan(late!));
    });

    test('scores title matches above excerpt matches', () {
      final inTitle = fuzzyScore('pocket', 'Pocket the app');
      final inExcerpt = fuzzyScore('pocket', 'Put it in your pocket');
      expect(inTitle, isNotNull);
      expect(inExcerpt, isNotNull);
      expect(inTitle!, lessThan(inExcerpt!));
    });

    test('handles empty or whitespace queries and targets', () {
      expect(fuzzyScore('', 'anything'), isNull);
      expect(fuzzyScore('   ', 'anything'), isNull);
      expect(fuzzyScore('anything', ''), isNull);
    });
  });
}
