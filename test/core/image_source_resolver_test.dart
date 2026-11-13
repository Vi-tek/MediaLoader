import 'package:flutter_test/flutter_test.dart';
import 'package:media_loader/media_loader.dart';

void main() {
  const resolver = ImageSourceResolver();

  test('classifies empty input as invalid', () {
    final result = resolver.resolve('');
    expect(result.kind, ImageSourceKind.invalid);
  });

  test('treats a relative path as an asset', () {
    final result = resolver.resolve('assets/images/avatar.png');
    expect(result.kind, ImageSourceKind.asset);
    expect(result.mediaHint, ImageMediaKind.raster);
  });

  test('ignores dots in asset directory names', () {
    final result = resolver.resolve('assets/v1.2/images/avatar');
    expect(result.kind, ImageSourceKind.asset);
    expect(result.extensionHint, isNull);
  });

  test('normalizes only the uppercase extension', () {
    final result = resolver.resolve('assets/images/avatar.JPEG');
    expect(result.extensionHint, 'jpeg');
    expect(result.normalized, 'assets/images/avatar.JPEG');
  });

  test('uses URI path and ignores query parameters', () {
    final result = resolver.resolve(
      'https://example.com/avatar.PNG?token=a.b.c#fragment',
    );
    expect(result.kind, ImageSourceKind.network);
    expect(result.extensionHint, 'png');
  });

  test('classifies extensionless HTTPS URL as network unknown', () {
    final result = resolver.resolve(
      'https://lh3.googleusercontent.com/a/abc=s96-c',
    );
    expect(result.kind, ImageSourceKind.network);
    expect(result.extensionHint, isNull);
    expect(result.mediaHint, ImageMediaKind.unknown);
  });

  test('supports http, https, and gs schemes', () {
    expect(resolver.resolve('http://example.com/a').kind,
        ImageSourceKind.network);
    expect(resolver.resolve('https://example.com/a').kind,
        ImageSourceKind.network);
    expect(resolver.resolve('gs://bucket/path/a').kind,
        ImageSourceKind.firebaseStorage);
  });

  test('converts percent-encoded file URI with Uri.toFilePath', () {
    final result = resolver.resolve('file:///tmp/My%20Image.png');
    expect(result.kind, ImageSourceKind.file);
    expect(result.filePath, contains('My Image.png'));
  });

  test('rejects unsupported schemes', () {
    final result = resolver.resolve('ftp://example.com/image.png');
    expect(result.kind, ImageSourceKind.unsupported);
  });

  test('rejects malformed URI', () {
    final result = resolver.resolve('https://[broken');
    expect(result.kind, ImageSourceKind.invalid);
  });

  test('recognizes Windows absolute paths', () {
    final result = resolver.resolve(r'C:\Users\me\avatar.png');
    expect(result.kind, ImageSourceKind.file);
    expect(result.extensionHint, 'png');
  });
}
