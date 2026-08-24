import 'dart:async';

import 'package:flutter/services.dart';

import 'package:media_loader/media_loader.dart';

final class FakeImageDownloader implements ImageDownloader {
  final List<DownloadedImage> responses = <DownloadedImage>[];
  final List<Object> errors = <Object>[];
  final List<ImageDownloadRequest> requests = <ImageDownloadRequest>[];
  int callCount = 0;
  Completer<DownloadedImage>? completer;

  @override
  Future<DownloadedImage> download(
    ResolvedImageSource source,
    ImageDownloadRequest request,
  ) async {
    callCount += 1;
    requests.add(request);
    final pending = completer;
    if (pending != null) return pending.future;
    if (errors.isNotEmpty) throw errors.removeAt(0);
    if (responses.isEmpty) {
      throw StateError('FakeImageDownloader has no queued response.');
    }
    return responses.removeAt(0);
  }

  @override
  void close() {}
}

final class FakeImageCacheService implements ImageCacheService {
  final Map<String, CachedImageResource> resolved =
      <String, CachedImageResource>{};
  final Map<String, Uint8List> bytes = <String, Uint8List>{};
  final Map<String, Completer<CachedImageResource>> pending =
      <String, Completer<CachedImageResource>>{};
  final List<String> readTokens = <String>[];
  int resolveCallCount = 0;

  @override
  CachedImageResource? peekRemote(
    ResolvedImageSource source, {
    Map<String, String>? headers,
    String? cacheKey,
    Duration cacheDuration = const Duration(days: 30),
    bool includeStale = false,
  }) {
    return resolved[source.canonicalIdentity];
  }

  @override
  Future<CachedImageResource> resolveRemote(
    ResolvedImageSource source, {
    Map<String, String>? headers,
    String? cacheKey,
    Duration cacheDuration = const Duration(days: 30),
    bool allowStaleOnError = true,
    Duration requestTimeout = const Duration(seconds: 20),
    int maxDownloadBytes = 32 * 1024 * 1024,
  }) {
    resolveCallCount += 1;
    final cached = resolved[source.canonicalIdentity];
    if (cached != null) return Future<CachedImageResource>.value(cached);
    return pending
        .putIfAbsent(
          source.canonicalIdentity,
          Completer<CachedImageResource>.new,
        )
        .future;
  }

  @override
  Future<Uint8List> readBytes(CachedImageResource resource) async {
    readTokens.add(resource.storageToken);
    final data = bytes[resource.storageToken];
    if (data == null) throw StateError('Missing fake bytes.');
    return data;
  }

  @override
  Future<void> remove(CachedImageResource resource) async {
    resolved.removeWhere((key, value) => value == resource);
    bytes.remove(resource.storageToken);
  }

  @override
  void close() {}
}

final class MemoryAssetBundle extends CachingAssetBundle {
  MemoryAssetBundle(this.assets);

  final Map<String, Uint8List> assets;

  @override
  Future<ByteData> load(String key) async {
    final value = assets[key];
    if (value == null) {
      throw StateError('Missing test asset: $key');
    }
    return ByteData.sublistView(value);
  }
}
