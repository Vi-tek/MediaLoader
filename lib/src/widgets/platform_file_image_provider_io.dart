import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider<Object> createPlatformFileImageProvider(
  String path, {
  double scale = 1.0,
}) {
  return FileImage(File(path), scale: scale);
}
