import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Optional hooks for host applications to customize [MediaLoader] behavior
/// without coupling this package to any app-specific type.
///
/// Every hook defaults to null / a neutral fallback, so the package works
/// out of the box with no wiring at all.

/// Resolves a special-cased "color source" string (any encoding an app wants,
/// e.g. `color#RRGGBB`) into a [Color] to paint instead of loading an image.
///
/// Returning null means the string is not a color encoding and normal image
/// source resolution should proceed.
typedef ColorSourceDecoder = Color? Function(String? source);

/// Set once at app startup to let [ImageLoader] short-circuit encoded color
/// backgrounds before running normal image source resolution.
ColorSourceDecoder? colorSourceDecoder;

/// Looks up a legacy pre-decoded Lottie composition for [assetPath], if the
/// host app maintains its own composition cache outside of [MediaStore].
///
/// [MediaStore]'s pinned tier is always checked first; this is consulted only
/// as a fallback.
typedef LegacyCompositionLookup = LottieComposition? Function(String assetPath);

/// Set once at app startup to plug in a legacy composition cache.
LegacyCompositionLookup? legacyCompositionLookup;

/// The asset path shown by [ImageLoader] and [AnimatedImageSwitcher] when no
/// per-widget `errorImage` is supplied and image resolution fails.
///
/// Leave null to fall back to a plain broken-image icon.
String? defaultErrorImage;