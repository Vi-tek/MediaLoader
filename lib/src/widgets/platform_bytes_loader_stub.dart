import 'dart:typed_data';

Future<Uint8List> readPlatformFileBytes(String path) {
  return Future<Uint8List>.error(
    UnsupportedError('Local filesystem images are not supported on web.'),
  );
}
