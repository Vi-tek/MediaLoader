import 'package:flutter/foundation.dart';

import 'image_cache_service.dart';
import 'image_cache_service_factory.dart';

final class ImageCacheProvider {
  ImageCacheProvider._();

  static ImageCacheService _instance = createDefaultImageCacheService();

  static ImageCacheService get instance => _instance;

  @visibleForTesting
  static set instance(ImageCacheService value) {
    _instance = value;
  }

  @visibleForTesting
  static void reset() {
    _instance.close();
    _instance = createDefaultImageCacheService();
  }
}
