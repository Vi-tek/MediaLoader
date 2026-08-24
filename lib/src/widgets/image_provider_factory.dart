import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../core/image_cache_identity.dart';
import '../core/image_source.dart';
import '../core/image_source_cache.dart';
import '../core/image_source_resolver.dart';
import '../cache/image_cache_provider.dart';
import '../cache/image_cache_service.dart';

import 'cached_source_image_provider.dart';
import 'platform_file_image_provider.dart';
import 'svg_source_image_provider.dart';

final class ImageProviderFactory {
  const ImageProviderFactory({
    ImageSourceResolver resolver = const ImageSourceResolver(),
    ImageCacheService? cacheService,
  }) : _resolver = resolver,
       _cacheService = cacheService;

  /// Shared instance for the common case of the app-wide cache service. Avoids
  /// allocating a factory on every image build.
  static const ImageProviderFactory shared = ImageProviderFactory();

  final ImageSourceResolver _resolver;
  final ImageCacheService? _cacheService;

  ImageProvider<Object> imageProvider(
    String source, {
    double scale = 1.0,
    Map<String, String>? headers,
    Duration cacheDuration = const Duration(days: 30),
    int? cacheWidth,
    int? cacheHeight,
    String? cacheKey,
    bool allowStaleOnError = true,
  }) {
    // Identical to `_resolver.resolve` for the default resolver, but memoized.
    final resolved = identical(_resolver, const ImageSourceResolver())
        ? ImageSourceCache.resolve(source)
        : _resolver.resolve(source);
    return imageProviderFromResolved(
      resolved,
      scale: scale,
      headers: headers,
      cacheDuration: cacheDuration,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      cacheKey: cacheKey,
      allowStaleOnError: allowStaleOnError,
    );
  }

  ImageProvider<Object> imageProviderFromResolved(
    ResolvedImageSource source, {
    double scale = 1.0,
    Map<String, String>? headers,
    Duration cacheDuration = const Duration(days: 30),
    int? cacheWidth,
    int? cacheHeight,
    String? cacheKey,
    bool allowStaleOnError = true,
    CachedImageResource? preparedResource,
  }) {
    if (!source.isValid) {
      throw ArgumentError.value(
        source.original,
        'source',
        source.error ?? 'Invalid image source.',
      );
    }
    if (scale <= 0) {
      throw ArgumentError.value(scale, 'scale', 'Scale must be positive.');
    }
    if (cacheWidth != null && cacheWidth <= 0) {
      throw ArgumentError.value(
        cacheWidth,
        'cacheWidth',
        'Decode width must be positive.',
      );
    }
    if (cacheHeight != null && cacheHeight <= 0) {
      throw ArgumentError.value(
        cacheHeight,
        'cacheHeight',
        'Decode height must be positive.',
      );
    }

    final extension = source.extensionHint;
    final hasKnownNonRasterExtension = extension == 'json';
    if (source.mediaHint == ImageMediaKind.lottie ||
        source.mediaHint == ImageMediaKind.dotLottie ||
        hasKnownNonRasterExtension) {
      throw UnsupportedError(
        'This non-raster source requires the ImageLoader widget; '
        'ImageLoader.imageProvider only supports raster images.',
      );
    }

    final service = _cacheService ?? ImageCacheProvider.instance;
    final key = _ProviderKey(
      identity: source.canonicalIdentity,
      mediaHint: source.mediaHint,
      kind: source.kind,
      scale: scale,
      headersIdentity: ImageCacheIdentity.headersIdentity(headers),
      cacheDuration: cacheDuration,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      cacheKey: cacheKey,
      allowStaleOnError: allowStaleOnError,
      preparedGeneration: preparedResource?.generation,
      serviceId: identityHashCode(service),
    );

    final memoized = _lookup(key);
    if (memoized != null) return memoized;

    final provider = _create(
      source,
      service: service,
      scale: scale,
      headers: headers,
      cacheDuration: cacheDuration,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      cacheKey: cacheKey,
      allowStaleOnError: allowStaleOnError,
      preparedResource: preparedResource,
    );
    _remember(key, provider);
    return provider;
  }

  ImageProvider<Object> _create(
    ResolvedImageSource source, {
    required ImageCacheService service,
    required double scale,
    required Map<String, String>? headers,
    required Duration cacheDuration,
    required int? cacheWidth,
    required int? cacheHeight,
    required String? cacheKey,
    required bool allowStaleOnError,
    required CachedImageResource? preparedResource,
  }) {
    if (source.mediaHint == ImageMediaKind.svg) {
      return ResizeImage.resizeIfNeeded(
        cacheWidth,
        cacheHeight,
        SvgSourceImageProvider(
          source: source,
          cacheService: service,
          scale: scale,
          headers: headers,
          cacheDuration: cacheDuration,
          cacheKey: cacheKey,
          allowStaleOnError: allowStaleOnError,
        ),
      );
    }

    final ImageProvider<Object> provider = switch (source.kind) {
      ImageSourceKind.asset => AssetImage(source.normalized),
      ImageSourceKind.file => createPlatformFileImageProvider(
        source.filePath ?? source.normalized,
        scale: scale,
      ),

      //|| ImageSourceKind.firebaseStorage 
      ImageSourceKind.network 
      => CachedSourceImageProvider(
        source: source,
        cacheService: service,
        scale: scale,
        headers: headers,
        cacheDuration: cacheDuration,
        cacheKey: cacheKey,
        allowStaleOnError: allowStaleOnError,
        preparedResource: preparedResource,
      ),
      ImageSourceKind.invalid ||
      ImageSourceKind.unsupported => throw ArgumentError.value(
        source.original,
        'source',
        source.error ?? 'Invalid image source.',
      ),
    };

    return ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, provider);
  }

  // Providers are immutable descriptors, so the same inputs can safely share
  // one instance. Reusing it keeps `Image.didUpdateWidget` on its identity
  // fast path and removes an allocation from every image rebuild.
  static const int _maxMemoizedProviders = 256;
  static final Map<_ProviderKey, ImageProvider<Object>> _providers =
      <_ProviderKey, ImageProvider<Object>>{};

  static ImageProvider<Object>? _lookup(_ProviderKey key) {
    final hit = _providers.remove(key);
    if (hit == null) return null;
    _providers[key] = hit;
    return hit;
  }

  static void _remember(_ProviderKey key, ImageProvider<Object> provider) {
    if (_providers.length >= _maxMemoizedProviders) {
      _providers.remove(_providers.keys.first);
    }
    _providers[key] = provider;
  }

  @visibleForTesting
  static void clearMemoizedProviders() => _providers.clear();
}

@immutable
final class _ProviderKey {
  const _ProviderKey({
    required this.identity,
    required this.mediaHint,
    required this.kind,
    required this.scale,
    required this.headersIdentity,
    required this.cacheDuration,
    required this.cacheWidth,
    required this.cacheHeight,
    required this.cacheKey,
    required this.allowStaleOnError,
    required this.preparedGeneration,
    required this.serviceId,
  });

  final String identity;
  final ImageMediaKind mediaHint;
  final ImageSourceKind kind;
  final double scale;
  final String headersIdentity;
  final Duration cacheDuration;
  final int? cacheWidth;
  final int? cacheHeight;
  final String? cacheKey;
  final bool allowStaleOnError;
  final String? preparedGeneration;
  final int serviceId;

  @override
  bool operator ==(Object other) {
    return other is _ProviderKey &&
        other.identity == identity &&
        other.mediaHint == mediaHint &&
        other.kind == kind &&
        other.scale == scale &&
        other.headersIdentity == headersIdentity &&
        other.cacheDuration == cacheDuration &&
        other.cacheWidth == cacheWidth &&
        other.cacheHeight == cacheHeight &&
        other.cacheKey == cacheKey &&
        other.allowStaleOnError == allowStaleOnError &&
        other.preparedGeneration == preparedGeneration &&
        other.serviceId == serviceId;
  }

  @override
  int get hashCode => Object.hash(
    identity,
    mediaHint,
    kind,
    scale,
    headersIdentity,
    cacheDuration,
    cacheWidth,
    cacheHeight,
    cacheKey,
    allowStaleOnError,
    preparedGeneration,
    serviceId,
  );
}
