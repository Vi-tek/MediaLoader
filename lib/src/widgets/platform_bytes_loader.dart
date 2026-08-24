import 'dart:typed_data';

import 'platform_bytes_loader_stub.dart'
    if (dart.library.io) 'platform_bytes_loader_io.dart' as implementation;

Future<Uint8List> readPlatformFileBytes(String path) {
  return implementation.readPlatformFileBytes(path);
}
