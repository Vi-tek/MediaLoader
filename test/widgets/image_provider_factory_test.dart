import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_loader/media_loader.dart';

import '../support/fakes.dart';

void main() {
  const resolver = ImageSourceResolver();

  test('maps raster assets to AssetImage', () {
    final provider = ImageProviderFactory(
      cacheService: FakeImageCacheService(),
    ).imageProvider('assets/images/avatar.png');
    expect(provider, isA<AssetImage>());
  });

  test('maps local files to FileImage on IO platforms', () {
    final provider = ImageProviderFactory(
      cacheService: FakeImageCacheService(),
    ).imageProvider(File('test/fixtures/green.png').absolute.path);
    expect(provider, isA<FileImage>());
  });

  test('maps extensionless network source to cached provider', () {
    final provider = ImageProviderFactory(
      cacheService: FakeImageCacheService(),
    ).imageProvider('https://example.com/avatar=s96-c');
    expect(provider, isA<CachedSourceImageProvider>());
  });

  test('applies ResizeImage for decode-size hints', () {
    final provider = ImageProviderFactory(cacheService: FakeImageCacheService())
        .imageProvider(
          'assets/images/avatar.png',
          cacheWidth: 64,
          cacheHeight: 64,
        );
    expect(provider, isA<ResizeImage>());
  });

  test('supports SVG and rejects unsupported non-raster format hints', () {
    final factory = ImageProviderFactory(cacheService: FakeImageCacheService());
    expect(
      () => factory.imageProvider('assets/animation.json'),
      throwsUnsupportedError,
    );
    expect(
      factory.imageProvider('assets/icon.svg'),
      isA<SvgSourceImageProvider>(),
    );
    expect(
      () => factory.imageProvider('assets/animation.lottie'),
      throwsUnsupportedError,
    );
  });

  test('extensionless remote SVG content resolves to a provider key', () async {
    final service = FakeImageCacheService();
    final source = resolver.resolve('https://example.com/resource');
    service.resolved[source.canonicalIdentity] = CachedImageResource(
      cacheId: 'svg-cache',
      storageToken: 'svg-token',
      generation: 'svg-generation',
      sourceKind: ImageSourceKind.network,
      mediaKind: ImageMediaKind.svg,
      validatedAt: DateTime.utc(2026, 7, 21),
      contentLength: 20,
      contentType: 'image/svg+xml',
    );
    final provider =
        ImageProviderFactory(
              cacheService: service,
            ).imageProvider(source.original)
            as CachedSourceImageProvider;

    await expectLater(
      provider.obtainKey(const ImageConfiguration()),
      completes,
    );
  });

  test('resolved keys include byte generation in equality', () {
    CachedImageResource resource(String generation) => CachedImageResource(
      cacheId: 'cache-id',
      storageToken: generation,
      generation: generation,
      sourceKind: ImageSourceKind.network,
      mediaKind: ImageMediaKind.raster,
      validatedAt: DateTime.utc(2026, 7, 21),
      contentLength: 10,
    );

    final first = CachedSourceImageKey(
      cacheId: 'cache-id',
      generation: 'one',
      scale: 1,
      resource: resource('one'),
    );
    final same = CachedSourceImageKey(
      cacheId: 'cache-id',
      generation: 'one',
      scale: 1,
      resource: resource('one'),
    );
    final refreshed = CachedSourceImageKey(
      cacheId: 'cache-id',
      generation: 'two',
      scale: 1,
      resource: resource('two'),
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(refreshed));
  });

  test('cached provider equality and hashCode are stable', () {
    final service = FakeImageCacheService();
    final source = resolver.resolve('https://example.com/avatar');
    final first = CachedSourceImageProvider(
      source: source,
      cacheService: service,
      headers: const <String, String>{'B': '2', 'A': '1'},
    );
    final second = CachedSourceImageProvider(
      source: source,
      cacheService: service,
      headers: const <String, String>{'A': '1', 'B': '2'},
    );
    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}
