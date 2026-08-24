import 'package:flutter/foundation.dart';
import '../core/image_source.dart';

export 'image_cache_service_legacy_stub.dart'
    if (dart.library.io) 'image_cache_service_legacy_io.dart';

@immutable
final class CachedImageResource {
  const CachedImageResource({
    required this.cacheId,
    required this.storageToken,
    required this.generation,
    required this.sourceKind,
    required this.mediaKind,
    required this.validatedAt,
    required this.contentLength,
    this.contentType,
    this.etag,
    this.lastModified,
    this.remoteGeneration,
    this.fromPersistentCache = false,
    this.stale = false,
  });

  final String cacheId;
  final String storageToken;
  final String generation;
  final ImageSourceKind sourceKind;
  final ImageMediaKind mediaKind;
  final DateTime validatedAt;
  final int contentLength;
  final String? contentType;
  final String? etag;
  final String? lastModified;
  final String? remoteGeneration;
  final bool fromPersistentCache;
  final bool stale;

  bool isFresh(Duration duration, DateTime now) {
    if (duration == Duration.zero) return false;
    if (now.isBefore(validatedAt)) return true;
    return now.difference(validatedAt) < duration;
  }

  CachedImageResource copyWith({
    String? storageToken,
    String? generation,
    ImageMediaKind? mediaKind,
    DateTime? validatedAt,
    int? contentLength,
    String? contentType,
    String? etag,
    String? lastModified,
    String? remoteGeneration,
    bool? fromPersistentCache,
    bool? stale,
  }) {
    return CachedImageResource(
      cacheId: cacheId,
      storageToken: storageToken ?? this.storageToken,
      generation: generation ?? this.generation,
      sourceKind: sourceKind,
      mediaKind: mediaKind ?? this.mediaKind,
      validatedAt: validatedAt ?? this.validatedAt,
      contentLength: contentLength ?? this.contentLength,
      contentType: contentType ?? this.contentType,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      remoteGeneration: remoteGeneration ?? this.remoteGeneration,
      fromPersistentCache: fromPersistentCache ?? this.fromPersistentCache,
      stale: stale ?? this.stale,
    );
  }
}

abstract interface class ImageCacheService {
  CachedImageResource? peekRemote(
    ResolvedImageSource source, {
    Map<String, String>? headers,
    String? cacheKey,
    Duration cacheDuration = const Duration(days: 30),
    bool includeStale = false,
  });

  Future<CachedImageResource> resolveRemote(
    ResolvedImageSource source, {
    Map<String, String>? headers,
    String? cacheKey,
    Duration cacheDuration = const Duration(days: 30),
    bool allowStaleOnError = true,
    Duration requestTimeout = const Duration(seconds: 20),
    int maxDownloadBytes = 32 * 1024 * 1024,
  });

  Future<Uint8List> readBytes(CachedImageResource resource);

  Future<void> remove(CachedImageResource resource);

  void close();
}
