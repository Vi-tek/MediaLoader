import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import 'image_cache_service.dart';
import 'image_cache_service_native.dart';

/// Native compatibility surface for call sites that used the previous
/// file-returning cache API. New code should use [resolveRemote] and
/// [readBytes] so media metadata is not lost.
extension LegacyImageCacheServiceApi on ImageCacheService {
  File? getCachedFileSync(String source) {
    final service = this;
    return service is NativeImageCacheService
        ? service.getCachedFileSync(source)
        : null;
  }

  Future<File> getImageFromUrl(String source) {
    final service = this;
    if (service is NativeImageCacheService) {
      return service.getImageFromUrl(source);
    }
    return Future<File>.error(
      UnsupportedError('The active image cache is not filesystem-backed.'),
    );
  }

  Future<File> getImageFromFirebase(Reference reference) {
    final service = this;
    if (service is NativeImageCacheService) {
      return service.getImageFromFirebase(reference);
    }
    return Future<File>.error(
      UnsupportedError('The active image cache is not filesystem-backed.'),
    );
  }

  Future<File?> revalidateFirebaseImage(Reference reference) {
    final service = this;
    if (service is NativeImageCacheService) {
      return service.revalidateFirebaseImage(reference);
    }
    return Future<File?>.error(
      UnsupportedError('The active image cache is not filesystem-backed.'),
    );
  }
}
