/// `double.tryParse` accepts "NaN", "Infinity" and "-Infinity" (and huge
/// exponents). Those poison every downstream calculation (`ceil()`, `round()`
/// and `toInt()` throw on them). User-entered amounts must always be finite.
double? tryParseFinite(String? source) {
  if (source == null) return null;
  final v = double.tryParse(source);
  if (v == null || v.isNaN || v.isInfinite) return null;
  return v;
}
