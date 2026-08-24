import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:jovial_svg/jovial_svg.dart';
import '../core/image_source.dart';
import '../cache/image_cache_service.dart';
import 'platform_bytes_loader.dart';

@immutable
final class SvgSourceImageKey {
  const SvgSourceImageKey({
    required this.identity,
    required this.generation,
    required this.scale,
  });

  final String identity;
  final String generation;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is SvgSourceImageKey &&
      identity == other.identity &&
      generation == other.generation &&
      scale == other.scale;

  @override
  int get hashCode => Object.hash(identity, generation, scale);
}

/// Rasterizes SVG sources for callers that require an [ImageProvider].
final class SvgSourceImageProvider extends ImageProvider<SvgSourceImageKey> {
  SvgSourceImageProvider({
    required this.source,
    required this.cacheService,
    this.scale = 1.0,
    this.headers,
    this.cacheDuration = const Duration(days: 30),
    this.cacheKey,
    this.allowStaleOnError = true,
  });

  final ResolvedImageSource source;
  final ImageCacheService cacheService;
  final double scale;
  final Map<String, String>? headers;
  final Duration cacheDuration;
  final String? cacheKey;
  final bool allowStaleOnError;

  @override
  Future<SvgSourceImageKey> obtainKey(ImageConfiguration configuration) async {
    if (!source.isRemote) {
      return SvgSourceImageKey(
        identity: source.canonicalIdentity,
        generation: source.canonicalIdentity,
        scale: scale,
      );
    }

    final resource = await cacheService.resolveRemote(
      source,
      headers: headers,
      cacheKey: cacheKey,
      cacheDuration: cacheDuration,
      allowStaleOnError: allowStaleOnError,
    );
    if (resource.mediaKind != ImageMediaKind.svg) {
      throw UnsupportedError(
        'Expected an SVG source, got ${resource.mediaKind.name}.',
      );
    }
    return SvgSourceImageKey(
      identity: resource.cacheId,
      generation: resource.generation,
      scale: scale,
    );
  }

  @override
  ImageStreamCompleter loadImage(
    SvgSourceImageKey key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: key.scale,
      debugLabel: 'svg:${key.identity}',
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    return decodeSvg(await _readBytes(), decode);
  }

  static Future<ui.Codec> decodeSvg(
    Uint8List bytes,
    ImageDecoderCallback decode,
  ) async {
    final svg = await Future<ScalableImage>(
      () => ScalableImage.fromSvgString(utf8.decode(bytes), warnF: (_) {}),
    );
    final viewport = svg.viewport;
    final width = viewport.width.ceil().clamp(1, 4096).toInt();
    final height = viewport.height.ceil().clamp(1, 4096).toInt();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(width / viewport.width, height / viewport.height);
    svg.paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('SVG rasterization produced no bytes.');
      }
      return decode(
        await ui.ImmutableBuffer.fromUint8List(data.buffer.asUint8List()),
      );
    } finally {
      image.dispose();
    }
  }

  Future<Uint8List> _readBytes() async {
    switch (source.kind) {
      case ImageSourceKind.asset:
        final data = await rootBundle.load(source.normalized);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      case ImageSourceKind.file:
        return readPlatformFileBytes(source.filePath ?? source.normalized);
      case ImageSourceKind.network:
      case ImageSourceKind.firebaseStorage:
        final resource = await cacheService.resolveRemote(
          source,
          headers: headers,
          cacheKey: cacheKey,
          cacheDuration: cacheDuration,
          allowStaleOnError: allowStaleOnError,
        );
        return cacheService.readBytes(resource);
      case ImageSourceKind.invalid:
      case ImageSourceKind.unsupported:
        throw ArgumentError.value(
          source.original,
          'source',
          'Invalid SVG source.',
        );
    }
  }
}
