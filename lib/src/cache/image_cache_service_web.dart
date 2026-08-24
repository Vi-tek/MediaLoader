import 'dart:typed_data';

import '../core/image_cache_identity.dart';
import '../core/image_media_detector.dart';
import '../core/image_source.dart';

import 'default_image_downloader.dart';
import 'image_cache_service.dart';
import 'image_download.dart';
import 'image_downloader.dart';

ImageCacheService createImageCacheService() => WebImageCacheService();

/// Web fallback. Flutter's decoded cache is still used, but persistent browser
/// storage is deliberately not added here. HTTP loading remains subject to CORS.
final class WebImageCacheService implements ImageCacheService {
  WebImageCacheService({
    ImageDownloader? downloader,
    DateTime Function()? clock,
    ImageMediaDetector mediaDetector = const ImageMediaDetector(),
  }) : _downloader = downloader ?? DefaultImageDownloader(),
       _clock = clock ?? DateTime.now,
       _mediaDetector = mediaDetector;

  final ImageDownloader _downloader;
  final DateTime Function() _clock;
  final ImageMediaDetector _mediaDetector;
  final Map<String, CachedImageResource> _resources =
      <String, CachedImageResource>{};
  final Map<String, Uint8List> _bytes = <String, Uint8List>{};
  final Map<String, Future<CachedImageResource>> _inFlight =
      <String, Future<CachedImageResource>>{};

  @override
  CachedImageResource? peekRemote(
    ResolvedImageSource source, {
    Map<String, String>? headers,
    String? cacheKey,
    Duration cacheDuration = const Duration(days: 30),
    bool includeStale = false,
  }) {
    _validateRemote(source);
    final id = ImageCacheIdentity.cacheId(
      source,
      headers: headers,
      explicitCacheKey: cacheKey,
    );
    final resource = _resources[id];
    if (resource == null) return null;
    final fresh = resource.isFresh(cacheDuration, _clock());
    if (!fresh && !includeStale) return null;
    return resource.copyWith(stale: !fresh);
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
    _validateRemote(source);
    if (cacheDuration.isNegative) {
      throw ArgumentError.value(
        cacheDuration,
        'cacheDuration',
        'Cache duration cannot be negative.',
      );
    }
    if (maxDownloadBytes <= 0) {
      throw ArgumentError.value(
        maxDownloadBytes,
        'maxDownloadBytes',
        'Maximum download size must be positive.',
      );
    }
    final id = ImageCacheIdentity.cacheId(
      source,
      headers: headers,
      explicitCacheKey: cacheKey,
    );
    final current = _resources[id];
    if (current != null && current.isFresh(cacheDuration, _clock())) {
      return Future<CachedImageResource>.value(current);
    }
    final requestId =
        '$id|${cacheDuration.inMicroseconds}|'
        '$allowStaleOnError|${requestTimeout.inMicroseconds}|$maxDownloadBytes';
    final pending = _inFlight[requestId];
    if (pending != null) return pending;
    final future = _resolve(
      id,
      source,
      current,
      headers ?? const <String, String>{},
      allowStaleOnError,
      requestTimeout,
      maxDownloadBytes,
    );
    _inFlight[requestId] = future;
    future.then<void>(
      (_) {
        _inFlight.remove(requestId);
      },
      onError: (Object _, StackTrace _) {
        _inFlight.remove(requestId);
      },
    );
    return future;
  }

  Future<CachedImageResource> _resolve(
    String id,
    ResolvedImageSource source,
    CachedImageResource? existing,
    Map<String, String> headers,
    bool allowStaleOnError,
    Duration timeout,
    int maxBytes,
  ) async {
    try {
      final downloaded = await _downloader.download(
        source,
        ImageDownloadRequest(
          headers: headers,
          timeout: timeout,
          maxBytes: maxBytes,
          ifNoneMatch: existing?.etag,
          ifModifiedSince: existing?.lastModified,
          // firebaseGeneration: existing?.remoteGeneration,
        ),
      );
      final now = _clock().toUtc();
      if (downloaded.notModified) {
        if (existing == null) {
          throw const ImageDownloadException(
            'Not-modified response has no matching memory entry.',
          );
        }
        final refreshed = existing.copyWith(
          validatedAt: now,
          stale: false,
          etag: downloaded.etag ?? existing.etag,
          lastModified: downloaded.lastModified ?? existing.lastModified,
          remoteGeneration:
              downloaded.remoteGeneration ?? existing.remoteGeneration,
        );
        _resources[id] = refreshed;
        return refreshed;
      }
      final data = downloaded.bytes;
      if (data == null || data.isEmpty) {
        throw const ImageDownloadException('Downloaded image is empty.');
      }
      final media = _mediaDetector.detect(
        data,
        mimeType: downloaded.contentType,
        extensionHint: source.extensionHint,
        fallbackUnknownBinaryToRaster: true,
      );
      if (media == ImageMediaKind.unknown) {
        throw const ImageDownloadException('Unsupported image content.');
      }
      final generation = ImageCacheIdentity.bytesGeneration(data);
      final storageToken = '$id:$generation';
      _bytes[storageToken] = data;
      final resource = CachedImageResource(
        cacheId: id,
        storageToken: storageToken,
        generation: generation,
        sourceKind: source.kind,
        mediaKind: media,
        validatedAt: now,
        contentLength: data.length,
        contentType: downloaded.contentType,
        etag: downloaded.etag,
        lastModified: downloaded.lastModified,
        remoteGeneration: downloaded.remoteGeneration,
      );
      final old = _resources[id];
      _resources[id] = resource;
      if (old != null && old.storageToken != storageToken) {
        _bytes.remove(old.storageToken);
      }
      return resource;
    } on Object {
      if (allowStaleOnError && existing != null) {
        return existing.copyWith(stale: true);
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List> readBytes(CachedImageResource resource) async {
    final data = _bytes[resource.storageToken];
    if (data == null) {
      throw StateError('Cached image bytes are no longer available.');
    }
    return data;
  }

  @override
  Future<void> remove(CachedImageResource resource) async {
    _resources.remove(resource.cacheId);
    _bytes.remove(resource.storageToken);
  }

  void _validateRemote(ResolvedImageSource source) {
    if (!source.isRemote) {
      throw ArgumentError.value(
        source.original,
        'source',
        'Only HTTP(S) and gs:// sources use the remote image cache.',
      );
    }
  }

  @override
  void close() {
    _downloader.close();
    _resources.clear();
    _bytes.clear();
  }
}
