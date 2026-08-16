import 'package:flutter_test/flutter_test.dart';
import 'package:read_later/utils/text_chunker.dart';

void main() {
  group('paragraphs', () {
    test('splits on blank lines and tracks offsets', () {
      final text = 'First paragraph.\n\nSecond paragraph.\n\nThird.';
      final paras = TextChunker.paragraphs(text);
      expect(paras, hasLength(3));
      expect(paras[0].text, 'First paragraph.');
      expect(paras[0].start, 0);
      expect(paras[1].text, 'Second paragraph.');
      expect(paras[2].text, 'Third.');
      expect(paras[2].end, text.length);
    });

    test('returns empty for blank input', () {
      expect(TextChunker.paragraphs('   \n  '), isEmpty);
      expect(TextChunker.paragraphs(''), isEmpty);
    });
  });

  group('chunk', () {
    test('short paragraphs become single segments', () {
      final segments = TextChunker.chunk('One.\n\nTwo words.\n\nThree.');
      expect(segments, hasLength(3));
      expect(segments[0].paragraphIndex, 0);
      expect(segments[1].paragraphIndex, 1);
      expect(segments[2].paragraphIndex, 2);
    });

    test('long paragraphs are split and packed to maxChars', () {
      final longParagraph = List.generate(
        10,
        (i) => 'Sentence number ${i + 1} with some extra words to pad it out.',
      ).join(' ');
      final text = 'Intro.\n\n$longParagraph';
      final segments = TextChunker.chunk(text, maxChars: 100);
      expect(segments.length, greaterThan(2));
      for (final s in segments) {
        expect(s.text.length, lessThanOrEqualTo(100 + 60),
            reason: 'one long sentence may exceed maxChars');
        expect(s.paragraphIndex, inInclusiveRange(0, 1));
      }
      // All text is covered by the segments.
      final joined = segments.map((s) => s.text).join(' ');
      for (final word in ['Sentence', 'number', 'words', 'Intro']) {
        expect(joined, contains(word));
      }
    });

    test('a single huge sentence is emitted whole', () {
      final huge = 'word ' * 500;
      final segments = TextChunker.chunk(huge, maxChars: 50);
      expect(segments, hasLength(1));
      expect(segments.first.text.trim(), huge.trim());
    });

    test('segment offsets are monotonic', () {
      final repeated = 'Beta sentence one. Beta sentence two. ' * 20;
      final text = 'Alpha.\n\n$repeated';
      final segments = TextChunker.chunk(text, maxChars: 80);
      var previous = -1;
      for (final s in segments) {
        expect(s.start, greaterThanOrEqualTo(previous));
        previous = s.start;
      }
    });
  });
}
