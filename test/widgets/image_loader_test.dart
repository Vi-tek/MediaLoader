import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:media_loader/media_loader.dart';

import '../support/fakes.dart';

const String _lottieJson =
    '{"v":"5.7.0","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[]}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeImageCacheService fakeCache;
  late ImageCacheService originalCache;
  late MediaStore originalStore;
  late List<int> redBytes;
  late List<int> greenBytes;
  const resolver = ImageSourceResolver();

  setUp(() async {
    originalCache = ImageCacheProvider.instance;
    fakeCache = FakeImageCacheService();
    ImageCacheProvider.instance = fakeCache;
    originalStore = MediaStore.instance;
    MediaStore.instance = MediaStore();
    PaintingBinding.instance.imageCache.clear();
    redBytes = await File('test/fixtures/red.jpg').readAsBytes();
    greenBytes = await File('test/fixtures/green.png').readAsBytes();
  });

  tearDown(() {
    ImageCacheProvider.instance = originalCache;
    MediaStore.instance = originalStore;
  });

  CachedImageResource resource(String token, String generation, int length) {
    return CachedImageResource(
      cacheId: 'cache-$token',
      storageToken: token,
      generation: generation,
      sourceKind: ImageSourceKind.network,
      mediaKind: ImageMediaKind.raster,
      validatedAt: DateTime.utc(2026, 7, 21),
      contentLength: length,
      contentType: token == 'old' ? 'image/jpeg' : 'image/png',
    );
  }

  testWidgets('renders a raster asset with dimensions and fit', (tester) async {
    final bundle = MemoryAssetBundle(<String, Uint8List>{
      'assets/test/green.png': Uint8List.fromList(greenBytes),
    });

    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: bundle,
        child: const MaterialApp(
          home: ImageLoader(
            'assets/test/green.png',
            width: 23,
            height: 17,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 23);
    expect(image.height, 17);
    expect(image.fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a source resolved by colorSourceDecoder', (
    tester,
  ) async {
    const encodedColor = 'color#ECE7AD';
    colorSourceDecoder = (source) {
      if (source == null || !source.startsWith('color#')) return null;
      final hex = source.substring('color#'.length);
      return Color(int.parse('FF$hex', radix: 16));
    };
    addTearDown(() => colorSourceDecoder = null);

    await tester.pumpWidget(
      const MaterialApp(home: ImageLoader(encodedColor, width: 23, height: 17)),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xFFECE7AD),
      ),
      findsOneWidget,
    );
    expect(find.byType(SizedBox), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a native local raster file', (tester) async {
    final file = File('test/fixtures/green.png').absolute;
    await tester.pumpWidget(
      MaterialApp(home: ImageLoader(file.path, width: 20, height: 20)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending remote media never shows a progress spinner', (
    tester,
  ) async {
    const url = 'https://example.com/pending';
    await tester.pumpWidget(
      const MaterialApp(home: ImageLoader(url, width: 20, height: 20)),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a supplied placeholder is shown while resolution is pending', (
    tester,
  ) async {
    const url = 'https://example.com/pending-with-placeholder';
    await tester.pumpWidget(
      const MaterialApp(
        home: ImageLoader(
          url,
          width: 20,
          height: 20,
          placeholder: Text('loading', textDirection: TextDirection.ltr),
        ),
      ),
    );

    expect(find.text('loading'), findsOneWidget);
  });

  testWidgets('decodes the exact extensionless Google regression source', (
    tester,
  ) async {
    const url =
        'https://lh3.googleusercontent.com/a/'
        'ACg8ocIrDCCrOtC7558ethE4buBFoymwz7ipOW8cF58VX6QP-I86t4i5=s96-c';
    final identity = resolver.resolve(url).canonicalIdentity;

    await tester.pumpWidget(
      const MaterialApp(home: ImageLoader(url, width: 20, height: 20)),
    );
    await tester.pump();

    final cached = resource(
      'google-jpeg',
      'google-generation',
      redBytes.length,
    );
    fakeCache.bytes[cached.storageToken] = Uint8List.fromList(redBytes);
    fakeCache.resolved[identity] = cached;
    fakeCache.pending[identity]!.complete(cached);

    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);

    final readsAfterFirstDecode = fakeCache.readTokens.length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      const MaterialApp(home: ImageLoader(url, width: 20, height: 20)),
    );
    await tester.pumpAndSettle();
    // The coordinator may re-check freshness, but Flutter should reuse the
    // decoded provider key and avoid reading/decoding the same generation.
    expect(fakeCache.readTokens.length, readsAfterFirstDecode);
  });

  testWidgets('obsolete request cannot replace a newer source', (tester) async {
    const oldUrl = 'https://example.com/old';
    const newUrl = 'https://example.com/new';
    final oldSource = resolver.resolve(oldUrl).canonicalIdentity;
    final newSource = resolver.resolve(newUrl).canonicalIdentity;

    await tester.pumpWidget(
      const MaterialApp(home: ImageLoader(oldUrl, width: 20, height: 20)),
    );
    await tester.pump();

    await tester.pumpWidget(
      const MaterialApp(home: ImageLoader(newUrl, width: 20, height: 20)),
    );
    await tester.pump();

    final oldResource = resource('old', 'generation-old', redBytes.length);
    final newResource = resource('new', 'generation-new', greenBytes.length);
    fakeCache.bytes['old'] = Uint8List.fromList(redBytes);
    fakeCache.bytes['new'] = Uint8List.fromList(greenBytes);

    fakeCache.pending[oldSource]!.complete(oldResource);
    await tester.pump();
    expect(fakeCache.readTokens, isNot(contains('old')));

    fakeCache.pending[newSource]!.complete(newResource);
    await tester.pumpAndSettle();
    expect(fakeCache.readTokens, contains('new'));
    expect(fakeCache.readTokens, isNot(contains('old')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not call setState after disposal', (tester) async {
    const url = 'https://example.com/disposed';
    final identity = resolver.resolve(url).canonicalIdentity;

    await tester.pumpWidget(
      const MaterialApp(home: ImageLoader(url, width: 20, height: 20)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    final cached = resource('disposed', 'disposed-generation', redBytes.length);
    fakeCache.bytes[cached.storageToken] = Uint8List.fromList(redBytes);
    fakeCache.pending[identity]!.complete(cached);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(fakeCache.readTokens, isNot(contains('disposed')));
  });

  testWidgets('missing error animation falls back to broken-image icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ImageLoader(null, errorImage: 'not-in-lottie-cache'),
      ),
    );
    expect(find.byIcon(Icons.broken_image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a precached Lottie background without a load frame', (
    tester,
  ) async {
    const asset = 'assets/test/animation.json';
    final bytes = Uint8List.fromList(utf8.encode(_lottieJson));

    // AnimatedImageSwitcher.cachedComposition looks up MediaStore's pinned
    // tier under the default-bundle asset key, so pin under that same key
    // directly rather than routing through a custom AssetBundle.
    await MediaStore.instance.pin(
      MediaRequest(
        key: MediaRequest.assetKey(asset),
        kindHint: ImageMediaKind.lottie,
        readBytes: () async => bytes,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: AnimatedImageSwitcher(asset)),
    );

    expect(find.byType(Lottie), findsOneWidget);
  });

  testWidgets('preserves color-filter composition and grayscale matrix', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ImageLoader(
          null,
          errorImage: 'not-in-lottie-cache',
          grayScale: true,
          colorFilter: ColorFilter.mode(Colors.red, BlendMode.srcIn),
        ),
      ),
    );
    expect(find.byType(ColorFiltered), findsNWidgets(2));
  });
}