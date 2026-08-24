import 'package:flutter/material.dart';

import '../config.dart';

/// Original compatibility surface. Existing custom implementations continue to
/// compile because new behavior is exposed through [ExtendedImageLoaderProps].
abstract interface class ImageLoaderProps {
  double? get width;
  double? get height;
  BoxFit? get fit;
  bool? get animate;
  bool? get repeat;
  ColorFilter? get colorFilter;
  List<ColorFilter> get colorFilters;
  Widget? get placeholder;
  String? get assetPath;
  String? get errorImage;
}

/// Optional capabilities used by the refactored loader.
abstract interface class ExtendedImageLoaderProps implements ImageLoaderProps {
  String? get semanticLabel;
  bool get excludeFromSemantics;
  Map<String, String>? get headers;
  Duration get cacheDuration;
  int? get cacheWidth;
  int? get cacheHeight;
  String? get cacheKey;
  bool get allowStaleOnError;
  double get scale;
}

/// Backward-compatible defaults for callers that supply only the original
/// [ImageLoaderProps] contract.
extension ImageLoaderPropsDefaults on ImageLoaderProps {
  ExtendedImageLoaderProps? get _extended =>
      this is ExtendedImageLoaderProps ? this as ExtendedImageLoaderProps : null;

  String? get resolvedSemanticLabel => _extended?.semanticLabel;
  bool get resolvedExcludeFromSemantics =>
      _extended?.excludeFromSemantics ?? false;
  Map<String, String>? get resolvedHeaders => _extended?.headers;
  Duration get resolvedCacheDuration =>
      _extended?.cacheDuration ?? const Duration(days: 30);
  int? get resolvedCacheWidth => _extended?.cacheWidth;
  int? get resolvedCacheHeight => _extended?.cacheHeight;
  String? get resolvedCacheKey => _extended?.cacheKey;
  bool get resolvedAllowStaleOnError =>
      _extended?.allowStaleOnError ?? true;
  double get resolvedScale => _extended?.scale ?? 1.0;
}

/// Resolves the effective error image for [props]: its own [errorImage] when
/// set, otherwise the app-wide [defaultErrorImage].
String? resolvedErrorImage(ImageLoaderProps props) {
  return props.errorImage ?? defaultErrorImage;
}