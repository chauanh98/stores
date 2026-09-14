/// Vietnamese NLP utility for diacritics stripping, normalization,
/// tokenization, and word-boundary keyword matching.
class VietnameseTextHelper {
  static const Map<String, String> _vietnameseCharMap = {
    'a': 'aàáảãạăằắẳẵặâầấẩẫậ',
    'A': 'AÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ',
    'd': 'dđ',
    'D': 'DĐ',
    'e': 'eèéẻẽẹêềếểễệ',
    'E': 'EÈÉẺẼẸÊỀẾỂỄỆ',
    'i': 'iìíỉĩị',
    'I': 'IÌÍỈĨỊ',
    'o': 'oòóỏõọôồốổỗộơờớởỡợ',
    'O': 'OÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ',
    'u': 'uùúủũụưừứửữự',
    'U': 'UÙÚỦŨỤƯỪỨỬỮỰ',
    'y': 'yỳýỷỹỵ',
    'Y': 'YỲÝỶỸỴ',
  };

  /// Strip all Vietnamese accents and diacritics, returning ASCII equivalent.
  static String removeDiacritics(String str) {
    if (str.isEmpty) return str;
    var result = str;
    for (final entry in _vietnameseCharMap.entries) {
      final baseChar = entry.key;
      final variants = entry.value;
      for (int i = 0; i < variants.length; i++) {
        final variant = variants[i];
        if (variant != baseChar) {
          result = result.replaceAll(variant, baseChar);
        }
      }
    }
    return result;
  }

  /// Normalize string: lowercase, collapse multiple whitespaces and underscores, and trim.
  static String normalize(String str) {
    if (str.isEmpty) return '';
    return str.toLowerCase().replaceAll(RegExp(r'[\s_]+'), ' ').trim();
  }

  /// Strip diacritics and normalize string to lowercase trimmed ASCII.
  static String normalizeUnaccented(String str) {
    return removeDiacritics(normalize(str));
  }

  /// Tokenize text into normalized lowercase words.
  static List<String> tokenize(String str, {bool stripDiacritics = false}) {
    final cleaned = stripDiacritics ? normalizeUnaccented(str) : normalize(str);
    if (cleaned.isEmpty) return const [];
    return cleaned
        .split(RegExp(r'[^a-zA-Z0-9à-ỹÀ-Ỹ]+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  /// Boundary-safe word check (prevents false positives like "ăn" in "khăn", "áo" in "báo cáo").
  static bool containsWord(String source, String word) {
    if (source.isEmpty || word.isEmpty) return false;
    final normSource = normalize(source);
    final normWord = normalize(word);
    if (normSource.isEmpty || normWord.isEmpty) return false;

    // Pattern matches word surrounded by start/end or non-alphanumeric chars (including Vietnamese letters)
    final pattern = RegExp(
      '(?<=^|[^a-zA-Z0-9à-ỹÀ-Ỹ])${RegExp.escape(normWord)}(?=[^a-zA-Z0-9à-ỹÀ-Ỹ]|\$)',
      caseSensitive: false,
    );
    return pattern.hasMatch(normSource);
  }

  /// Boundary-safe word check on unaccented normalized text.
  static bool containsWordUnaccented(String source, String word) {
    if (source.isEmpty || word.isEmpty) return false;
    final unaccSource = normalizeUnaccented(source);
    final unaccWord = normalizeUnaccented(word);
    if (unaccSource.isEmpty || unaccWord.isEmpty) return false;

    final pattern = RegExp(
      '(?<=^|[^a-zA-Z0-9])${RegExp.escape(unaccWord)}(?=[^a-zA-Z0-9]|\$)',
      caseSensitive: false,
    );
    return pattern.hasMatch(unaccSource);
  }

  /// Checks if [source] contains the multi-word [phrase] with boundary safety.
  static bool containsPhrase(String source, String phrase, {bool unaccented = false}) {
    if (source.isEmpty || phrase.isEmpty) return false;
    final s = unaccented ? normalizeUnaccented(source) : normalize(source);
    final p = unaccented ? normalizeUnaccented(phrase) : normalize(phrase);
    if (s.isEmpty || p.isEmpty) return false;

    final charClass = unaccented ? 'a-zA-Z0-9' : 'a-zA-Z0-9à-ỹÀ-Ỹ';
    final pattern = RegExp(
      '(?<=^|[^$charClass])${RegExp.escape(p)}(?=[^$charClass]|\$)',
      caseSensitive: false,
    );
    return pattern.hasMatch(s);
  }
}
