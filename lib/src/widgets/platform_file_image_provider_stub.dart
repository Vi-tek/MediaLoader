import 'package:flutter/widgets.dart';

ImageProvider<Object> createPlatformFileImageProvider(
  String path, {
  double scale = 1.0,
}) {
  throw UnsupportedError(
    'Local filesystem images are not supported on Flutter web. '
    'Use an asset or a network URL instead.',
  );
}
