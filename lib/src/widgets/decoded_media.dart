import 'package:flutter/foundation.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:lottie/lottie.dart';
import '../core/image_source.dart';

/// A fully decoded, ready-to-paint artifact.
///
/// Decoding an SVG or a Lottie composition is the expensive part of showing
/// one, and it does not depend on the widget that shows it. Modelling the
/// decoded result as a value lets [MediaStore] hand the same instance to every
/// widget that asks for the same source, so remounting is free.
@immutable
sealed class DecodedMedia {
  const DecodedMedia();

  ImageMediaKind get kind;

  /// Rough retained cost, used only to bound the store.
  int get weight;
}

final class DecodedVector extends DecodedMedia {
  const DecodedVector(this.image, {required this.weight});

  final ScalableImage image;

  @override
  final int weight;

  @override
  ImageMediaKind get kind => ImageMediaKind.svg;
}

final class DecodedAnimation extends DecodedMedia {
  const DecodedAnimation(
    this.composition, {
    required this.kind,
    required this.weight,
  });

  final LottieComposition composition;

  @override
  final ImageMediaKind kind;

  @override
  final int weight;
}

/// Raster bytes that must be painted from memory rather than through an
/// [ImageProvider] — remote media whose bytes are already resident.
final class DecodedRaster extends DecodedMedia {
  const DecodedRaster(this.bytes);

  final Uint8List bytes;

  @override
  ImageMediaKind get kind => ImageMediaKind.raster;

  @override
  int get weight => bytes.lengthInBytes;
}
