import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../core/image_cache_identity.dart';
import '../core/image_source.dart';
import '../cache/image_cache_service.dart';

import 'svg_source_image_provider.dart';

@immutable
final class CachedSourceImageKey {
  const CachedSourceImageKey({
    required this.cacheId,
    required this.generation,
    required this.scale,
    required this.resource,
  });

  final String cacheId;
  final String generation;
  final double scale;
  final CachedImageResource resource;

  @override
  bool operator ==(Object other) {
    return other is CachedSourceImageKey &&
        other.cacheId == cacheId &&
        other.generation == generation &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(cacheId, generation, scale);
}

final class CachedSourceImageProvider
    extends ImageProvider<CachedSourceImageKey> {
  const CachedSourceImageProvider({
    required this.source,
    required this.cacheService,
    this.scale = 1.0,
    this.headers,
    this.cacheDuration = const Duration(days: 30),
    this.cacheKey,
    this.allowStaleOnError = true,
    this.preparedResource,
  });

  final ResolvedImageSource source;
  final ImageCacheService cacheService;
  final double scale;
  final Map<String, String>? headers;
  final Duration cacheDuration;
  final String? cacheKey;
  final bool allowStaleOnError;
  final CachedImageResource? preparedResource;

  @override
  Future<CachedSourceImageKey> obtainKey(ImageConfiguration configuration) {
    final prepared = preparedResource;
    if (prepared != null) {
      return SynchronousFuture<CachedSourceImageKey>(_keyFor(prepared));
    }

    final memory = cacheService.peekRemote(
      source,
      headers: headers,
      cacheKey: cacheKey,
      cacheDuration: cacheDuration,
    );
    if (memory != null) {
      return SynchronousFuture<CachedSourceImageKey>(_keyFor(memory));
    }

    return cacheService
        .resolveRemote(
          source,
          headers: headers,
          cacheKey: cacheKey,
          cacheDuration: cacheDuration,
          allowStaleOnError: allowStaleOnError,
        )
        .then(_keyFor);
  }

  CachedSourceImageKey _keyFor(CachedImageResource resource) {
    if (resource.mediaKind == ImageMediaKind.lottie ||
        resource.mediaKind == ImageMediaKind.dotLottie) {
      throw UnsupportedError(
        '${resource.mediaKind.name} sources require the ImageLoader widget; '
        'ImageLoader.imageProvider supports raster and SVG images.',
      );
    }
    return CachedSourceImageKey(
      cacheId: resource.cacheId,
      generation: resource.generation,
      scale: scale,
      resource: resource,
    );
  }

  @override
  ImageStreamCompleter loadImage(
    CachedSourceImageKey key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: 'cached-image:${_short(key.cacheId)}',
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<String>('Cache ID', _short(key.cacheId)),
        DiagnosticsProperty<String>('Generation', _short(key.generation)),
        DiagnosticsProperty<ImageSourceKind>('Source kind', source.kind),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    CachedSourceImageKey key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await cacheService.readBytes(key.resource);
      if (bytes.isEmpty) {
        throw StateError('Cached image contains no bytes.');
      }
      if (key.resource.mediaKind == ImageMediaKind.svg) {
        return SvgSourceImageProvider.decodeSvg(bytes, decode);
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } on Object {
      // Do not let corrupt or incomplete bytes become a persistent failure.
      // Flutter removes failed decoded entries from its own ImageCache; remove
      // the corresponding persistent entry as well so the next resolution can
      // fetch a clean copy.
      try {
        await cacheService.remove(key.resource);
      } on Object {
        // Preserve the original decode/read error.
      }
      rethrow;
    }
  }

  String _short(String value) {
    return value.length <= 12 ? value : value.substring(0, 12);
  }

  @override
  bool operator ==(Object other) {
    return other is CachedSourceImageProvider &&
        other.source.canonicalIdentity == source.canonicalIdentity &&
        other.scale == scale &&
        other.cacheDuration == cacheDuration &&
        other.cacheKey == cacheKey &&
        other.allowStaleOnError == allowStaleOnError &&
        ImageCacheIdentity.headersIdentity(other.headers) ==
            ImageCacheIdentity.headersIdentity(headers) &&
        other.preparedResource?.generation == preparedResource?.generation &&
        identical(other.cacheService, cacheService);
  }

  @override
  int get hashCode => Object.hash(
    source.canonicalIdentity,
    scale,
    cacheDuration,
    cacheKey,
    allowStaleOnError,
    ImageCacheIdentity.headersIdentity(headers),
    preparedResource?.generation,
    identityHashCode(cacheService),
  );
}
