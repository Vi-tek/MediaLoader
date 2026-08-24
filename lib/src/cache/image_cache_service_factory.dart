import 'image_cache_service.dart';
import 'image_cache_service_web.dart'
    if (dart.library.io) 'image_cache_service_native.dart' as implementation;

ImageCacheService createDefaultImageCacheService() {
  return implementation.createImageCacheService();
}
