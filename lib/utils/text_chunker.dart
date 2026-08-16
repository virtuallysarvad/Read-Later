/// A paragraph of plain article text with its offset in the full text.
class Paragraph {
  final String text;
  final int start;
  final int end;

  Paragraph({required this.text, required this.start, required this.end});
}

/// A chunk of text spoken by the TTS engine as one unit.
class TtsSegment {
  final String text;
  final int paragraphIndex;
  final int start;
  final int end;

  TtsSegment({
    required this.text,
    required this.paragraphIndex,
    required this.start,
    required this.end,
  });
}

/// Splits plain article text into paragraphs and short TTS segments so we can
/// track position, highlight the current paragraph, and skip around like a
/// podcast player.
class TextChunker {
  /// Preferred segment length in characters (a few seconds of speech).
  static const int defaultMaxChars = 350;

  /// Sentence-ending regex used to split long paragraphs (no lookbehind, so it
  /// works on the Dart VM). Trailing punctuation quotes are absorbed by the
  /// leading group.
  static final RegExp _sentenceRegex = RegExp(r'[^.!?]+[.!?]+ *');

  static List<Paragraph> paragraphs(String text) {
    final result = <Paragraph>[];
    if (text.trim().isEmpty) return result;

    final re = RegExp(r'\n\s*\n');
    int start = 0;
    for (final match in re.allMatches(text)) {
      final paraText = text.substring(start, match.start).trim();
      if (paraText.isNotEmpty) {
        result.add(Paragraph(text: paraText, start: start, end: match.start));
      }
      start = match.end;
    }
    final last = text.substring(start).trim();
    if (last.isNotEmpty) {
      result.add(
        Paragraph(text: last, start: text.length - last.length, end: text.length),
      );
    }
    return result;
  }

  /// Splits [text] into segments, each at most [maxChars] long.
  ///
  /// Short paragraphs become a single segment. Long paragraphs are split on
  /// sentence boundaries and packed greedily.
  static List<TtsSegment> chunk(String text, {int maxChars = defaultMaxChars}) {
    final paras = paragraphs(text);
    final segments = <TtsSegment>[];

    for (var i = 0; i < paras.length; i++) {
      final para = paras[i];
      // Offset of the paragraph within the whole text for progress reporting.
      final paraOffsetInText = para.start;

      if (para.text.length <= maxChars) {
        segments.add(
          TtsSegment(
            text: para.text,
            paragraphIndex: i,
            start: paraOffsetInText,
            end: paraOffsetInText + para.text.length,
          ),
        );
        continue;
      }

      // Long paragraph: split into sentences and pack them.
      final sentences = <(String, int)>[]; // (sentence, offset within paragraph)
      var sentenceStart = 0;
      for (final m in _sentenceRegex.allMatches(para.text)) {
        sentences.add((m.group(0)!, sentenceStart));
        sentenceStart = m.end;
      }
      if (sentenceStart < para.text.length) {
        final rest = para.text.substring(sentenceStart).trim();
        if (rest.isNotEmpty) {
          sentences.add((rest, para.text.length - rest.length));
        }
      }

      var buffer = StringBuffer();
      var bufferStart = 0;
      for (final (sentence, offsetInPara) in sentences) {
        if (buffer.isEmpty && sentence.length > maxChars) {
          // One very long sentence: emit it whole rather than dropping it.
          segments.add(
            TtsSegment(
              text: sentence.trim(),
              paragraphIndex: i,
              start: paraOffsetInText + offsetInPara,
              end: paraOffsetInText + offsetInPara + sentence.length,
            ),
          );
          continue;
        }
        if (buffer.isNotEmpty && buffer.length + sentence.length > maxChars) {
          segments.add(
            TtsSegment(
              text: buffer.toString().trim(),
              paragraphIndex: i,
              start: paraOffsetInText + bufferStart,
              end: paraOffsetInText + bufferStart + buffer.length,
            ),
          );
          buffer = StringBuffer();
          bufferStart = offsetInPara;
        }
        if (buffer.isEmpty) {
          bufferStart = offsetInPara;
        }
        buffer.write(sentence);
      }
      if (buffer.isNotEmpty) {
        segments.add(
          TtsSegment(
            text: buffer.toString().trim(),
            paragraphIndex: i,
            start: paraOffsetInText + bufferStart,
            end: paraOffsetInText + bufferStart + buffer.length,
          ),
        );
      }
    }
    return segments;
  }
}
