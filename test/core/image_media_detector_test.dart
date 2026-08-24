import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_loader/media_loader.dart';

void main() {
  const detector = ImageMediaDetector();

  test('maps extension hints', () {
    expect(detector.fromExtension('PNG'), ImageMediaKind.raster);
    expect(detector.fromExtension('svg'), ImageMediaKind.svg);
    expect(detector.fromExtension('json'), ImageMediaKind.unknown);
    expect(detector.fromExtension('lottie'), ImageMediaKind.dotLottie);
  });

  test('maps MIME types', () {
    expect(detector.fromMimeType('image/jpeg'), ImageMediaKind.raster);
    expect(detector.fromMimeType('image/svg+xml'), ImageMediaKind.svg);
    expect(
      detector.fromMimeType('application/vnd.lottie+zip'),
      ImageMediaKind.dotLottie,
    );
  });

  test('detects PNG, JPEG, WebP, GIF, and BMP signatures', () {
    expect(
      detector.detect(Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10])),
      ImageMediaKind.raster,
    );
    expect(
      detector.detect(Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xdb])),
      ImageMediaKind.raster,
    );
    expect(
      detector.detect(Uint8List.fromList(ascii.encode('RIFF0000WEBP'))),
      ImageMediaKind.raster,
    );
    expect(
      detector.detect(Uint8List.fromList(ascii.encode('GIF89a'))),
      ImageMediaKind.raster,
    );
    expect(
      detector.detect(Uint8List.fromList(<int>[0x42, 0x4d, 0, 0])),
      ImageMediaKind.raster,
    );
  });

  test('detects SVG content', () {
    final bytes = Uint8List.fromList(utf8.encode('<svg viewBox="0 0 1 1"></svg>'));
    expect(detector.detect(bytes), ImageMediaKind.svg);
  });

  test('validates Lottie JSON structure', () {
    final valid = Uint8List.fromList(utf8.encode(
      '{"v":"5.7.0","fr":30,"ip":0,"op":60,"layers":[]}',
    ));
    final ordinaryJson = Uint8List.fromList(utf8.encode('{"hello":"world"}'));
    expect(detector.detect(valid, extensionHint: 'json'), ImageMediaKind.lottie);
    expect(detector.detect(ordinaryJson, extensionHint: 'json'),
        ImageMediaKind.unknown);
  });

  test('detects dotLottie zip only with supporting metadata', () {
    final zip = Uint8List.fromList(<int>[0x50, 0x4b, 0x03, 0x04, 0, 0]);
    expect(
      detector.detect(zip, extensionHint: 'lottie'),
      ImageMediaKind.dotLottie,
    );
  });

  test('returns unknown for corrupt bytes by default', () {
    expect(
      detector.detect(Uint8List.fromList(<int>[1, 2, 3, 4])),
      ImageMediaKind.unknown,
    );
  });
}
