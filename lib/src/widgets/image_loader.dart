import 'package:flutter/material.dart';
import '../config.dart';
import '../core/image_source.dart';
import '../core/image_source_cache.dart';
import '../cache/image_cache_service.dart';

import 'cached_image_loader.dart';
import 'decoded_media_view.dart';
import 'image_loader_props.dart';
import 'image_provider_factory.dart';
import 'image_render.dart';

export '../core/image_media_detector.dart';
export '../core/image_source.dart';
export '../core/image_source_cache.dart';
export '../core/image_source_resolver.dart';
export '../config.dart';
export 'decoded_media.dart';
export 'image_loader_props.dart';
export 'image_precacher.dart';
export 'image_render.dart';
export 'media_store.dart';

/// Renders any supported image source — asset, file, network, Firebase Storage
/// — in raster, SVG, Lottie or dotLottie form.
///
/// The build path is deliberately allocation-light: source resolution is
/// memoized by [ImageSourceCache], decoded vector and animation media is shared
/// through [MediaStore], and raster media goes through an [ImageProvider] whose
/// `==` lets `Image` skip re-resolving on rebuild. A rebuild of an already
/// resolved image therefore does no I/O, no parsing and no decoding.
final class ImageLoader extends StatelessWidget
    implements ExtendedImageLoaderProps {
  const ImageLoader(
    this.assetPath, {
    this.width,
    this.colorFilter,
    this.colorFilters = const <ColorFilter>[],
    this.placeholder,
    this.grayScale,
    this.height,
    this.fit,
    this.animate,
    this.repeat,
    this.errorImage,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.headers,
    this.cacheDuration = const Duration(days: 30),
    this.cacheWidth,
    this.cacheHeight,
    this.cacheKey,
    this.allowStaleOnError = true,
    this.scale = 1.0,
    super.key,
  });

  @override
  final String? assetPath;
  @override
  final double? width;
  @override
  final double? height;
  @override
  final BoxFit? fit;
  @override
  final bool? animate;
  @override
  final bool? repeat;
  @override
  final String? errorImage;
  @override
  final ColorFilter? colorFilter;
  @override
  final List<ColorFilter> colorFilters;
  @override
  final Widget? placeholder;
  final bool? grayScale;
  @override
  final String? semanticLabel;
  @override
  final bool excludeFromSemantics;
  @override
  final Map<String, String>? headers;
  @override
  final Duration cacheDuration;
  @override
  final int? cacheWidth;
  @override
  final int? cacheHeight;
  @override
  final String? cacheKey;
  @override
  final bool allowStaleOnError;
  @override
  final double scale;

  static const ColorFilter _grayScaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 0.5, 0, //
  ]);

  static ImageProvider<Object> imageProvider(
    String source, {
    double scale = 1.0,
    Map<String, String>? headers,
    Duration cacheDuration = const Duration(days: 30),
    int? cacheWidth,
    int? cacheHeight,
    String? cacheKey,
    bool allowStaleOnError = true,
    ImageCacheService? cacheService,
  }) {
    return ImageProviderFactory(cacheService: cacheService).imageProvider(
      source,
      scale: scale,
      headers: headers,
      cacheDuration: cacheDuration,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      cacheKey: cacheKey,
      allowStaleOnError: allowStaleOnError,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _applyFilters(_buildSource(context));
  }

  Widget _buildSource(BuildContext context) {
    final path = assetPath;

    // A host app may register a decoder for special-cased, non-image source
    // strings (e.g. an encoded solid color) via [colorSourceDecoder]. Checked
    // before any resolution work happens.
    final decoder = colorSourceDecoder;
    if (path != null && decoder != null) {
      final color = decoder(path);
      if (color != null) {
        return SizedBox(
          width: width,
          height: height,
          child: ColoredBox(color: color),
        );
      }
    }

    final source = ImageSourceCache.resolve(path);
    if (!source.isValid) return buildImageError(context, this);

    switch (source.kind) {
      case ImageSourceKind.asset:
      case ImageSourceKind.file:
        if (source.mediaHint == ImageMediaKind.raster) {
          return buildRasterImage(context, this, source);
        }
        return LocalMediaView(
          key: ValueKey<String>(source.canonicalIdentity),
          source: source,
          props: this,
        );
      case ImageSourceKind.network:
      // case ImageSourceKind.firebaseStorage:
        return CachedImageLoader(
          key: ValueKey<String>(source.canonicalIdentity),
          source: source,
          props: this,
        );
      case ImageSourceKind.invalid:
      case ImageSourceKind.unsupported:
        return buildImageError(context, this);
    }
  }

  Widget _applyFilters(Widget image) {
    // The common case is no filters at all; avoid building a list for it.
    final extra = colorFilters;
    if (extra.isNotEmpty) {
      for (var index = extra.length - 1; index >= 0; index -= 1) {
        image = ColorFiltered(colorFilter: extra[index], child: image);
      }
    }
    final primary = colorFilter;
    if (primary != null) {
      image = ColorFiltered(colorFilter: primary, child: image);
    }
    if (grayScale ?? false) {
      image = ColorFiltered(colorFilter: _grayScaleFilter, child: image);
    }
    return image;
  }
}