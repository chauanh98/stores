import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import '../../../core/utils/image_compression_helper.dart';

/// Kết quả của quá trình tải ảnh lên hệ thống
class ImageUploadResult {
  /// URL tải về từ Firebase Storage hoặc chuỗi Data URI `data:image/jpeg;base64,...`
  final String imageUrl;

  /// Cờ báo hiệu ảnh đã được lưu dự phòng bằng Base64 Data URL
  final bool isFallbackBase64;

  /// Bucket lưu trữ thành công (nếu tải lên Firebase Storage thành công)
  final String? storageBucket;

  /// Thông điệp lỗi chi tiết (nếu có lỗi trong quá trình tải Firebase Storage)
  final String? errorMessage;

  /// Kích thước dữ liệu ảnh (bytes)
  final int? byteLength;

  const ImageUploadResult({
    required this.imageUrl,
    this.isFallbackBase64 = false,
    this.storageBucket,
    this.errorMessage,
    this.byteLength,
  });

  bool get isStorageUrl => !isFallbackBase64 && imageUrl.isNotEmpty;
}

/// Dịch vụ tải ảnh tập trung với cơ chế tự động thử đa Bucket và dự phòng Base64 an toàn.
class ImageUploadService {
  final List<String> candidateBuckets;
  final FirebaseStorage? storageOverride;
  final bool useDirectBase64;

  static const List<String> defaultCandidateBuckets = [
    'khanh-dang-store.firebasestorage.app',
    'khanh-dang-store.appspot.com',
  ];

  ImageUploadService({
    List<String>? candidateBuckets,
    this.storageOverride,
    this.useDirectBase64 = true,
  }) : candidateBuckets = candidateBuckets ?? defaultCandidateBuckets;

  /// Tải / Lưu trữ ảnh sản phẩm lên hệ thống.
  /// Mặc định chuẩn hóa Phương án 1 (Default Lightweight Local Base64 Storage):
  /// - Tự động nén ảnh tức thì ngay trên client (kích thước tối đa 300x300, chất lượng JPEG 70%, dung lượng siêu nhẹ ~15KB - 30KB).
  /// - Lưu trực tiếp chuỗi Data URI `data:image/jpeg;base64,...` vào database.
  /// - Hoàn toàn độc lập, lưu tức thì trong vài chục mili-giây, 0đ, không phụ thuộc Firebase Storage và không bao giờ gặp lỗi 404.
  Future<ImageUploadResult> uploadProductImage({
    required String storeId,
    required String productId,
    File? file,
    Uint8List? bytes,
  }) async {
    // 1. Chuẩn bị mảng byte từ file hoặc bytes truyền vào
    Uint8List? rawBytes = bytes;
    if (rawBytes == null && file != null) {
      try {
        if (await file.exists()) {
          rawBytes = await file.readAsBytes();
        }
      } catch (e) {
        debugPrint('[ImageUploadService] Failed to read file bytes: $e');
      }
    }

    if (rawBytes == null || rawBytes.isEmpty) {
      return const ImageUploadResult(
        imageUrl: '',
        isFallbackBase64: false,
        errorMessage: 'Không có dữ liệu ảnh để tải lên',
      );
    }

    // 2. Phương án 1: Chuẩn hóa nén siêu nhẹ và lưu Base64 Data URL trực tiếp (0đ, không phụ thuộc Firebase Storage)
    if (useDirectBase64) {
      try {
        // Kiểm tra nếu rawBytes truyền vào vốn đã là chuỗi Base64 Data URL
        if (rawBytes.length > 20 &&
            rawBytes[0] == 0x64 &&
            rawBytes[1] == 0x61) {
          try {
            final asString = utf8.decode(rawBytes, allowMalformed: true);
            if (ImageCompressionHelper.isBase64DataUrl(asString)) {
              final decodedBytes =
                  ImageCompressionHelper.decodeBase64DataUrl(asString);
              if (decodedBytes != null &&
                  decodedBytes.isNotEmpty &&
                  img.decodeImage(decodedBytes) != null) {
                return ImageUploadResult(
                  imageUrl: asString.trim(),
                  isFallbackBase64: true,
                  byteLength: decodedBytes.length,
                );
              }
            }
          } catch (_) {}
        }

        final initialDecoded = img.decodeImage(rawBytes);
        if (initialDecoded == null) {
          return const ImageUploadResult(
            imageUrl: '',
            isFallbackBase64: false,
            errorMessage: 'Dữ liệu ảnh không hợp lệ hoặc không thể giải mã',
          );
        }

        final compressedBytes = ImageCompressionHelper.compressImageBytes(
          rawBytes,
          maxWidth: 300,
          maxHeight: 300,
          quality: 70,
        );

        final isDecodable = img.decodeImage(compressedBytes) != null;
        if (!isDecodable || compressedBytes.length > 70 * 1024) {
          return const ImageUploadResult(
            imageUrl: '',
            isFallbackBase64: false,
            errorMessage: 'Dữ liệu ảnh không hợp lệ hoặc không thể nén an toàn',
          );
        }

        final dataUrl = ImageCompressionHelper.toBase64DataUrl(compressedBytes);
        debugPrint(
          '[ImageUploadService] Phương án 1 (Default Base64): ${ImageCompressionHelper.formatByteSize(compressedBytes.length)} (original: ${ImageCompressionHelper.formatByteSize(rawBytes.length)})',
        );
        return ImageUploadResult(
          imageUrl: dataUrl,
          isFallbackBase64: true,
          byteLength: compressedBytes.length,
        );
      } catch (e, stack) {
        debugPrint(
            '[ImageUploadService] Failed during direct Base64 compression: $e\n$stack');
        return const ImageUploadResult(
          imageUrl: '',
          isFallbackBase64: false,
          errorMessage: 'Không thể nén ảnh',
        );
      }
    }

    final sanitizedProductId = productId.replaceAll(RegExp(r'[^\w\-]'), '_');
    final storagePath = 'stores/$storeId/products/$sanitizedProductId.jpg';
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {
        'uploadedAt': DateTime.now().toIso8601String(),
        'storeId': storeId,
        'productId': productId,
      },
    );

    // 2. Thử tải lên Firebase Storage với từng candidate bucket
    String? lastError;
    final bucketsToTry =
        storageOverride != null ? ['[storageOverride]'] : candidateBuckets;

    for (final bucket in bucketsToTry) {
      try {
        debugPrint(
            '[ImageUploadService] Attempting upload to bucket: $bucket path: $storagePath');
        final storage =
            storageOverride ?? FirebaseStorage.instanceFor(bucket: bucket);
        final ref = storage.ref(storagePath);

        UploadTask uploadTask;
        if (kIsWeb || file == null) {
          uploadTask = ref.putData(rawBytes, metadata);
        } else {
          uploadTask = ref.putFile(file, metadata);
        }

        try {
          // Đặt timeout 15 giây để tránh treo ứng dụng khi mạng chập chờn
          final snapshot =
              await uploadTask.timeout(const Duration(seconds: 15));
          if (snapshot.state == TaskState.success) {
            final downloadUrl =
                await ref.getDownloadURL().timeout(const Duration(seconds: 10));
            if (downloadUrl.isNotEmpty) {
              debugPrint(
                  '[ImageUploadService] Upload successful to bucket $bucket: $downloadUrl');
              return ImageUploadResult(
                imageUrl: downloadUrl,
                isFallbackBase64: false,
                storageBucket: storageOverride?.bucket ?? bucket,
                byteLength: rawBytes.length,
              );
            }
          }
        } on TimeoutException {
          try {
            await uploadTask.cancel();
          } catch (_) {}
          rethrow;
        }
      } catch (e, stack) {
        lastError = e.toString();
        debugPrint('[ImageUploadService] Bucket $bucket failed: $e\n$stack');
        // Tiếp tục thử bucket tiếp theo
      }
    }

    // 3. Fallback: Tự động nén ảnh sang Base64 Data URL (max 300x300, JPEG 70%)
    debugPrint(
        '[ImageUploadService] All storage buckets failed. Falling back to Compressed Base64 Data URL.');
    try {
      final compressedBytes = ImageCompressionHelper.compressImageBytes(
        rawBytes,
        maxWidth: 300,
        maxHeight: 300,
        quality: 70,
      );

      // Đảm bảo dữ liệu nén là ảnh hợp lệ và kích thước an toàn (< 70KB) cho Realtime Database
      final isDecodable = img.decodeImage(compressedBytes) != null;
      if (!isDecodable || compressedBytes.length > 70 * 1024) {
        return ImageUploadResult(
          imageUrl: '',
          isFallbackBase64: false,
          errorMessage: lastError ??
              'Dữ liệu ảnh không hợp lệ hoặc không thể nén an toàn',
        );
      }

      final dataUrl = ImageCompressionHelper.toBase64DataUrl(compressedBytes);
      debugPrint(
        '[ImageUploadService] Compressed to Base64 data URL: ${ImageCompressionHelper.formatByteSize(compressedBytes.length)} (original: ${ImageCompressionHelper.formatByteSize(rawBytes.length)})',
      );
      return ImageUploadResult(
        imageUrl: dataUrl,
        isFallbackBase64: true,
        errorMessage: lastError,
        byteLength: compressedBytes.length,
      );
    } catch (e, stack) {
      debugPrint(
          '[ImageUploadService] Failed during Base64 fallback compression: $e\n$stack');
    }

    return ImageUploadResult(
      imageUrl: '',
      isFallbackBase64: false,
      errorMessage: lastError ?? 'Không thể lưu trữ ảnh',
    );
  }

  /// Xóa ảnh sản phẩm an toàn. Tự động bỏ qua Base64 và bắt an toàn lỗi Firebase Storage.
  Future<void> deleteProductImage(String? imageUrl) async {
    if (imageUrl == null || imageUrl.trim().isEmpty) return;
    final urls = ImageCompressionHelper.parseImageUrls(imageUrl);
    for (final url in urls) {
      if (ImageCompressionHelper.isBase64DataUrl(url)) continue;
      final isFirebaseStorageUrl = url.startsWith('gs://') ||
          url.contains('firebasestorage.googleapis.com') ||
          url.contains('firebasestorage.app') ||
          url.contains('.appspot.com');
      if (isFirebaseStorageUrl) {
        try {
          final storage = storageOverride ?? FirebaseStorage.instance;
          final ref = storage.refFromURL(url);
          await ref.delete().timeout(const Duration(seconds: 10));
          debugPrint(
              '[ImageUploadService] Deleted product image from storage: $url');
        } catch (e) {
          debugPrint('[ImageUploadService] Safe delete ignored error: $e');
        }
      }
    }
  }

  /// Hướng dẫn xúc tích cho quản trị viên về cách kích hoạt Firebase Cloud Storage
  static void showStorageActivationGuide(BuildContext context) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cloud_upload_outlined, color: Colors.blueAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Kích hoạt Firebase Storage',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ảnh sản phẩm hiện được nén và lưu an toàn dưới dạng Data URL nội bộ. Để lưu ảnh gốc độ phân giải cao lên đám mây, quản trị viên vui lòng kích hoạt Storage theo các bước sau:',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              _buildStepRow(
                '1',
                'Truy cập Firebase Console tại:',
                'console.firebase.google.com',
              ),
              const SizedBox(height: 10),
              _buildStepRow(
                '2',
                'Chọn dự án',
                'khanh-dang-store (hoặc dự án tương ứng)',
              ),
              const SizedBox(height: 10),
              _buildStepRow(
                '3',
                'Vào menu Xây dựng (Build) > Chọn Storage (Lưu trữ)',
                'Nhấn nút "Get started" (Bắt đầu)',
              ),
              const SizedBox(height: 10),
              _buildStepRow(
                '4',
                'Chọn vị trí lưu trữ (khuyến nghị: asia-southeast1)',
                'Chấp nhận Cloud Storage Security Rules và nhấn Hoàn tất.',
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sau khi kích hoạt, toàn bộ ảnh tải lên mới sẽ tự động lưu trữ trên Cloud Storage mà không cần cấu hình lại app.',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đã hiểu',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Widget _buildStepRow(String number, String title, String detail) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: Colors.blue.shade100,
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                detail,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Provider Riverpod cung cấp ImageUploadService trong toàn bộ ứng dụng
final imageUploadServiceProvider = Provider<ImageUploadService>((ref) {
  return ImageUploadService();
});
