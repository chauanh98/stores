import 'dart:typed_data';

import 'file_saver_io.dart' if (dart.library.html) 'file_saver_web.dart'
    as platform;

/// Cross-platform helper to save/download an Excel file.
/// On Web: Triggers direct browser file download via Blob and AnchorElement click.
/// On Mobile/Desktop: Writes to temporary directory and opens system share sheet.
Future<void> saveExcelFile(Uint8List bytes, String fileName) =>
    platform.saveExcelFile(bytes, fileName);
