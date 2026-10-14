/// First visible character of [text] (upper-cased) for avatar badges.
///
/// Safe for empty / whitespace-only strings and for characters outside the BMP
/// (emoji): `text[0]` would split a surrogate pair and make `Text` throw
/// "string is not well-formed".
String initialOf(String? text, [String fallback = '?']) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return fallback;
  return String.fromCharCode(t.runes.first).toUpperCase();
}
