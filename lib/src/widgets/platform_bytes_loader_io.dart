import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readPlatformFileBytes(String path) => File(path).readAsBytes();
