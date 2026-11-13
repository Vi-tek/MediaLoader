import 'package:firebase_storage/firebase_storage.dart';

import 'image_cache_service.dart';

/// The previous API returned dart:io Files and therefore has no web equivalent.
extension LegacyImageCacheServiceApi on ImageCacheService {
  Never getCachedFileSync(String source) {
    throw UnsupportedError('Filesystem image caching is unavailable on web.');
  }

  Future<Never> getImageFromUrl(String source) {
    return Future<Never>.error(
      UnsupportedError('Filesystem image caching is unavailable on web.'),
    );
  }

  Future<Never> getImageFromFirebase(Reference reference) {
    return Future<Never>.error(
      UnsupportedError('Filesystem image caching is unavailable on web.'),
    );
  }

  Future<Never> revalidateFirebaseImage(Reference reference) {
    return Future<Never>.error(
      UnsupportedError('Filesystem image caching is unavailable on web.'),
    );
  }
}
