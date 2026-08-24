import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:media_loader/media_loader.dart';

import '../support/fakes.dart';

const String _svgSource =
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
    '<rect width="10" height="10" fill="#ff0000"/></svg>';

// ScalableImageWidget is abstract with a factory constructor, so find.byType
// (which matches the exact runtimeType) never matches its private subclass.
final Finder _scalableImage = find.byWidgetPredicate(
  (widget) => widget is ScalableImageWidget,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MediaStore originalStore;

  setUp(() {
    originalStore = MediaStore.instance;
    MediaStore.instance = MediaStore();
    ImageSourceCache.clear();
  });

  tearDown(() {
    MediaStore.instance = originalStore;
  });

  Uint8List svgBytes() => Uint8List.fromList(utf8.encode(_svgSource));

  group('MediaStore', () {
    test('decodes an SVG once and serves later reads synchronously', () async {
      var reads = 0;
      final request = MediaRequest(
        key: 'test:icon.svg',
        kindHint: ImageMediaKind.svg,
        readBytes: () async {
          reads += 1;
          return svgBytes();
        },
      );

      expect(MediaStore.instance.peek(request.key), isNull);

      final first = await MediaStore.instance.load(request);
      expect(first, isA<DecodedVector>());
      expect(reads, 1);

      // A warm key resolves without touching the byte source at all.
      final peeked = MediaStore.instance.peek(request.key);
      expect(peeked, same(first));

      final second = await MediaStore.instance.load(request);
      expect(second, same(first));
      expect(reads, 1);
    });

    test('concurrent loads of one key share a single decode', () async {
      var reads = 0;
      final request = MediaRequest(
        key: 'test:shared.svg',
        kindHint: ImageMediaKind.svg,
        readBytes: () async {
          reads += 1;
          await Future<void>.delayed(Duration.zero);
          return svgBytes();
        },
      );

      final results = await Future.wait(<Future<DecodedMedia>>[
        MediaStore.instance.load(request),
        MediaStore.instance.load(request),
        MediaStore.instance.load(request),
      ]);

      expect(reads, 1);
      expect(results[1], same(results[0]));
      expect(results[2], same(results[0]));
    });

    test('remembers a failure instead of re-reading a broken source', () async {
      var reads = 0;
      final request = MediaRequest(
        key: 'test:broken',
        readBytes: () async {
          reads += 1;
          throw StateError('missing');
        },
      );

      await expectLater(MediaStore.instance.load(request), throwsStateError);
      expect(MediaStore.instance.peekFailure(request.key), isNotNull);

      await expectLater(MediaStore.instance.load(request), throwsStateError);
      expect(reads, 1);
    });

    test('pinned entries survive eviction pressure', () async {
      final store = MediaStore(maxWeight: 1);
      MediaStore.instance = store;

      final pinned = MediaRequest(
        key: 'test:pinned.svg',
        kindHint: ImageMediaKind.svg,
        readBytes: () async => svgBytes(),
      );
      await store.pin(pinned);

      for (var index = 0; index < 5; index += 1) {
        await store.load(
          MediaRequest(
            key: 'test:transient-$index.svg',
            kindHint: ImageMediaKind.svg,
            readBytes: () async => svgBytes(),
          ),
        );
      }

      expect(store.peek(pinned.key), isNotNull);
      expect(store.pinnedCount, 1);
    });

    test('peekPinned ignores media that is merely resident', () async {
      final request = MediaRequest(
        key: 'test:resident.svg',
        kindHint: ImageMediaKind.svg,
        readBytes: () async => svgBytes(),
      );

      await MediaStore.instance.load(request);
      // Callers keyed on "was this precached?" must not see a plain cache hit:
      // AnimatedImageSwitcher starts an endless animation for precached
      // compositions, so widening this would animate anything still in memory.
      expect(MediaStore.instance.peek(request.key), isNotNull);
      expect(MediaStore.instance.peekPinned(request.key), isNull);

      await MediaStore.instance.pin(request);
      expect(MediaStore.instance.peekPinned(request.key), isNotNull);
    });

    test('rejects empty content rather than caching a broken decode', () async {
      final request = MediaRequest(
        key: 'test:empty',
        kindHint: ImageMediaKind.svg,
        readBytes: () async => Uint8List(0),
      );

      await expectLater(
        MediaStore.instance.load(request),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ImageSourceCache', () {
    test('returns the identical resolution for a repeated source', () {
      const path = 'assets/svg/icon/star.svg';
      final first = ImageSourceCache.resolve(path);
      final second = ImageSourceCache.resolve(path);

      expect(second, same(first));
      expect(first.kind, ImageSourceKind.asset);
      expect(first.mediaHint, ImageMediaKind.svg);
    });

    test('distinguishes different sources', () {
      final asset = ImageSourceCache.resolve('assets/a.png');
      final remote = ImageSourceCache.resolve('https://example.com/b.png');

      expect(asset.kind, ImageSourceKind.asset);
      expect(remote.kind, ImageSourceKind.network);
    });
  });

  group('ImageLoader with a warm store', () {
    testWidgets('paints a precached SVG on the first frame', (tester) async {
      const path = 'assets/test/icon.svg';
      final bundle = MemoryAssetBundle(<String, Uint8List>{
        path: svgBytes(),
      });

      await MediaStore.instance.pin(
        MediaRequest.asset(path, bundle: bundle, kindHint: ImageMediaKind.svg),
      );

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: bundle,
          child: const MaterialApp(
            home: ImageLoader(path, width: 24, height: 24),
          ),
        ),
      );

      // No settle: a warm store must resolve during the first build.
      expect(_scalableImage, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('remounting a warm SVG does not re-read the bundle', (
      tester,
    ) async {
      const path = 'assets/test/remount.svg';
      final bundle = _CountingAssetBundle(<String, Uint8List>{
        path: svgBytes(),
      });

      Widget app() => DefaultAssetBundle(
        bundle: bundle,
        child: const MaterialApp(
          home: ImageLoader(path, width: 24, height: 24),
        ),
      );

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(_scalableImage, findsOneWidget);
      expect(bundle.loads, 1);

      // Tear the subtree down and rebuild it, the way a list scroll does.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app());

      expect(_scalableImage, findsOneWidget);
      expect(bundle.loads, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('ImageProviderFactory', () {
    test('memoizes providers for identical raster requests', () {
      const path = 'assets/test/green.png';
      final first = ImageLoader.imageProvider(path);
      final second = ImageLoader.imageProvider(path);

      expect(second, same(first));
    });
  });
}

final class _CountingAssetBundle extends CachingAssetBundle {
  _CountingAssetBundle(this.assets);

  final Map<String, Uint8List> assets;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    final value = assets[key];
    if (value == null) throw StateError('Missing test asset: $key');
    loads += 1;
    return ByteData.sublistView(value);
  }
}
