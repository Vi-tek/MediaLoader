import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../config.dart';
import '../core/image_source.dart';
import '../cache/image_cache_service.dart';

import 'decoded_media.dart';
import 'image_loader_props.dart';
import 'image_provider_factory.dart';
import 'media_store.dart';

/// Builds the widget shown while media is still resolving.
///
/// Defaults to an inert box rather than a spinner: with [MediaStore] and
/// startup precaching, a placeholder now only appears for genuinely cold remote
/// media, and a progress indicator flashing in and out of a list was the most
/// visible symptom of the old rebuild-from-scratch behaviour. Assign
/// [imagePlaceholderBuilder] once at startup to change this app-wide.
Widget Function(ImageLoaderProps props)? imagePlaceholderBuilder;

Widget buildImagePlaceholder(ImageLoaderProps props) {
  final custom = props.placeholder;
  if (custom != null) {
    return SizedBox(width: props.width, height: props.height, child: custom);
  }
  final builder = imagePlaceholderBuilder;
  if (builder != null) return builder(props);
  return SizedBox(width: props.width, height: props.height);
}

Widget buildRasterImage(
  BuildContext context,
  ImageLoaderProps props,
  ResolvedImageSource source, {
  CachedImageResource? preparedResource,
  ImageCacheService? cacheService,
}) {
  final factory = cacheService == null
      ? ImageProviderFactory.shared
      : ImageProviderFactory(cacheService: cacheService);
  final provider = factory.imageProviderFromResolved(
    source,
    scale: props.resolvedScale,
    headers: props.resolvedHeaders,
    cacheDuration: props.resolvedCacheDuration,
    cacheWidth: props.resolvedCacheWidth,
    cacheHeight: props.resolvedCacheHeight,
    cacheKey: props.resolvedCacheKey,
    allowStaleOnError: props.resolvedAllowStaleOnError,
    preparedResource: preparedResource,
  );

  return Image(
    image: provider,
    width: props.width,
    height: props.height,
    fit: props.fit ?? BoxFit.fitHeight,
    gaplessPlayback: true,
    semanticLabel: props.resolvedSemanticLabel,
    excludeFromSemantics: props.resolvedExcludeFromSemantics,
    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
      if (wasSynchronouslyLoaded || frame != null) return child;
      return buildImagePlaceholder(props);
    },
    errorBuilder: (context, error, stackTrace) =>
        buildImageError(context, props),
  );
}

/// A Lottie composition that was *precached* for [assetPath], if any.
///
/// Deliberately limited to the pinned tier and an optional
/// [legacyCompositionLookup] hook, both of which are filled only by startup
/// precaching. Callers use this to decide whether to play an animation
/// immediately, so widening it to any resident composition would start
/// animating assets that merely happen to still be in memory from an earlier
/// render.
LottieComposition? cachedComposition(String assetPath) {
  final media = MediaStore.instance.peekPinned(
    MediaRequest.assetKey(assetPath),
  );
  if (media is DecodedAnimation) return media.composition;
  return legacyCompositionLookup?.call(assetPath);
}

Widget buildImageError(BuildContext context, ImageLoaderProps props) {
  _reportMissingSource(props.assetPath);
  final errorImage = resolvedErrorImage(props);
  final composition = errorImage == null ? null : cachedComposition(errorImage);
  final Widget child;
  if (composition != null) {
    child = Lottie(
      composition: composition,
      width: props.width,
      height: props.height,
      fit: props.fit,
      animate: props.animate ?? false,
      repeat: props.repeat,
    );
  } else {
    child = SizedBox(
      width: props.width,
      height: props.height,
      child: const Center(child: Icon(Icons.broken_image)),
    );
  }
  return RepaintBoundary(child: applyImageSemantics(child, props));
}

Widget applyImageSemantics(Widget child, ImageLoaderProps props) {
  if (props.resolvedExcludeFromSemantics) return ExcludeSemantics(child: child);
  final label = props.resolvedSemanticLabel;
  if (label == null || label.isEmpty) return child;
  return Semantics(image: true, label: label, child: child);
}

// The error widget is built from build(), so an unconditional log() fired on
// every frame of every broken image. Report each path once, in debug only.
final Set<String> _reportedMissingSources = <String>{};

void _reportMissingSource(String? path) {
  if (!kDebugMode) return;
  final value = path ?? '';
  if (!_reportedMissingSources.add(value)) return;
  log('ImageLoader could not resolve source: "$value"');
}

@visibleForTesting
void resetMissingSourceReports() => _reportedMissingSources.clear();