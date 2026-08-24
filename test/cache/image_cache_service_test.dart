import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_loader/media_loader.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late FakeImageDownloader downloader;
  late DateTime now;
  late NativeImageCacheService service;
  late Uint8List jpegBytes;
  const resolver = ImageSourceResolver();
  final source = resolver.resolve(
    'https://lh3.googleusercontent.com/a/'
    'ACg8ocIrDCCrOtC7558ethE4buBFoymwz7ipOW8cF58VX6QP-I86t4i5=s96-c',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('image-cache-test-');
    downloader = FakeImageDownloader();
    now = DateTime.utc(2026, 7, 21, 12);
    service = NativeImageCacheService(
      downloader: downloader,
      cacheDirectoryProvider: () async => directory,
      clock: () => now,
    );
    jpegBytes = await File('test/fixtures/red.jpg').readAsBytes();
  });

  tearDown(() async {
    service.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  DownloadedImage successfulJpeg() => DownloadedImage(
    notModified: false,
    statusCode: 200,
    finalUri: source.uri,
    contentType: 'image/jpeg',
    etag: 'etag-1',
    lastModified: 'Tue, 21 Jul 2026 12:00:00 GMT',
    remoteGeneration: null,
    bytes: jpegBytes,
  );

  test('extensionless response is detected, cached, and reused', () async {
    downloader.responses.add(successfulJpeg());

    final first = await service.resolveRemote(source);
    expect(first.mediaKind, ImageMediaKind.raster);
    expect(first.contentType, 'image/jpeg');
    expect(await service.readBytes(first), jpegBytes);
    expect(downloader.callCount, 1);

    final second = await service.resolveRemote(source);
    expect(second.generation, first.generation);
    expect(downloader.callCount, 1);
  });

  test('cacheDuration controls expiry and 304 refresh', () async {
    downloader.responses
      ..add(successfulJpeg())
      ..add(
        DownloadedImage(
          notModified: true,
          statusCode: 304,
          finalUri: source.uri,
          contentType: 'image/jpeg',
          etag: 'etag-1',
          lastModified: 'Tue, 21 Jul 2026 12:00:00 GMT',
          remoteGeneration: null,
        ),
      );

    final first = await service.resolveRemote(
      source,
      cacheDuration: const Duration(minutes: 5),
    );
    now = now.add(const Duration(minutes: 6));
    final refreshed = await service.resolveRemote(
      source,
      cacheDuration: const Duration(minutes: 5),
    );

    expect(refreshed.generation, first.generation);
    expect(refreshed.validatedAt, now);
    expect(downloader.callCount, 2);
    expect(downloader.requests.last.ifNoneMatch, 'etag-1');
  });

  test('failed refresh returns stale bytes when allowed', () async {
    downloader.responses.add(successfulJpeg());
    final first = await service.resolveRemote(
      source,
      cacheDuration: const Duration(minutes: 1),
    );
    now = now.add(const Duration(minutes: 2));
    downloader.errors.add(StateError('offline'));

    final stale = await service.resolveRemote(
      source,
      cacheDuration: const Duration(minutes: 1),
      allowStaleOnError: true,
    );

    expect(stale.stale, isTrue);
    expect(stale.generation, first.generation);
    expect(await service.readBytes(stale), jpegBytes);
  });

  test('failed refresh throws when stale fallback is disabled', () async {
    downloader.responses.add(successfulJpeg());
    await service.resolveRemote(
      source,
      cacheDuration: const Duration(minutes: 1),
    );
    now = now.add(const Duration(minutes: 2));
    downloader.errors.add(StateError('offline'));

    expect(
      service.resolveRemote(
        source,
        cacheDuration: const Duration(minutes: 1),
        allowStaleOnError: false,
      ),
      throwsStateError,
    );
  });

  test('concurrent identical misses perform one download', () async {
    final completer = downloader.completer = Completer<DownloadedImage>();
    final first = service.resolveRemote(source);
    final second = service.resolveRemote(source);
    await Future<void>.delayed(Duration.zero);
    expect(downloader.callCount, 1);

    completer.complete(successfulJpeg());
    final results = await Future.wait(<Future<Object>>[first, second]);
    expect(results[0], isA<CachedImageResource>());
    expect(results[1], isA<CachedImageResource>());
    expect(downloader.callCount, 1);
  });

  test('successful refresh atomically switches to a new generation', () async {
    downloader.responses.add(successfulJpeg());
    final first = await service.resolveRemote(
      source,
      cacheDuration: const Duration(minutes: 1),
    );

    final pngBytes = await File('test/fixtures/green.png').readAsBytes();
    now = now.add(const Duration(minutes: 2));
    downloader.responses.add(
      DownloadedImage(
        notModified: false,
        statusCode: 200,
        finalUri: source.uri,
        contentType: 'image/png',
        etag: 'etag-2',
        lastModified: 'Tue, 21 Jul 2026 12:02:00 GMT',
        remoteGeneration: null,
        bytes: pngBytes,
      ),
    );

    final second = await service.resolveRemote(
      source,
      cacheDuration: const Duration(minutes: 1),
    );
    expect(second.generation, isNot(first.generation));
    expect(await service.readBytes(second), pngBytes);

    final metadataFile = File(
      '${directory.path}${Platform.pathSeparator}${second.cacheId}.json',
    );
    final metadata =
        jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
    expect(metadata['storageToken'], second.storageToken);
    expect(
      File(
        '${directory.path}${Platform.pathSeparator}${second.storageToken}',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${directory.path}${Platform.pathSeparator}${first.storageToken}',
      ).existsSync(),
      isFalse,
    );
  });

  test('fresh metadata and bytes survive a service restart', () async {
    downloader.responses.add(successfulJpeg());
    final first = await service.resolveRemote(source);
    service.close();

    final secondDownloader = FakeImageDownloader();
    service = NativeImageCacheService(
      downloader: secondDownloader,
      cacheDirectoryProvider: () async => directory,
      clock: () => now,
    );
    final restored = await service.resolveRemote(source);

    expect(restored.generation, first.generation);
    expect(restored.fromPersistentCache, isTrue);
    expect(secondDownloader.callCount, 0);
    expect(await service.readBytes(restored), jpegBytes);
  });

  test('failed cache miss leaves no temporary files', () async {
    downloader.errors.add(StateError('offline'));
    await expectLater(service.resolveRemote(source), throwsStateError);
    final files = await directory
        .list()
        .where((entity) => entity.path.endsWith('.tmp'))
        .toList();
    expect(files, isEmpty);
  });

  test('different request headers use different cache identities', () async {
    downloader.responses
      ..add(successfulJpeg())
      ..add(successfulJpeg());

    final first = await service.resolveRemote(
      source,
      headers: const <String, String>{'Authorization': 'Bearer one'},
    );
    final second = await service.resolveRemote(
      source,
      headers: const <String, String>{'Authorization': 'Bearer two'},
    );

    expect(first.cacheId, isNot(second.cacheId));
    expect(downloader.callCount, 2);
  });
}
