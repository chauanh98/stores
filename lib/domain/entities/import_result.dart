class ImportResult {
  final int total;
  final int added;
  final int updated;
  final int skipped;
  final int errors;
  final List<String> errorMessages;

  const ImportResult({
    this.total = 0,
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = 0,
    this.errorMessages = const [],
  });

  bool get isSuccess => errors == 0;
  bool get hasErrors => errors > 0 || errorMessages.isNotEmpty;

  String toSummaryString() =>
      'Tổng số dòng: $total | Thêm mới: $added | Cập nhật: $updated | Bỏ qua: $skipped | Lỗi: $errors';

  String get summaryMessage => toSummaryString();

  ImportResult copyWith({
    int? total,
    int? added,
    int? updated,
    int? skipped,
    int? errors,
    List<String>? errorMessages,
  }) {
    return ImportResult(
      total: total ?? this.total,
      added: added ?? this.added,
      updated: updated ?? this.updated,
      skipped: skipped ?? this.skipped,
      errors: errors ?? this.errors,
      errorMessages: errorMessages ?? this.errorMessages,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportResult &&
          runtimeType == other.runtimeType &&
          total == other.total &&
          added == other.added &&
          updated == other.updated &&
          skipped == other.skipped &&
          errors == other.errors &&
          _listEquals(errorMessages, other.errorMessages);

  @override
  int get hashCode =>
      total.hashCode ^
      added.hashCode ^
      updated.hashCode ^
      skipped.hashCode ^
      errors.hashCode ^
      errorMessages.length.hashCode;

  @override
  String toString() =>
      'ImportResult(total: $total, added: $added, updated: $updated, skipped: $skipped, errors: $errors, errorMessages: $errorMessages)';

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
