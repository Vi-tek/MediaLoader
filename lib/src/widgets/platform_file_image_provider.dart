import 'package:flutter/widgets.dart';

import 'platform_file_image_provider_stub.dart'
    if (dart.library.io) 'platform_file_image_provider_io.dart' as implementation;

ImageProvider<Object> createPlatformFileImageProvider(
  String path, {
  double scale = 1.0,
}) {
  return implementation.createPlatformFileImageProvider(path, scale: scale);
}
