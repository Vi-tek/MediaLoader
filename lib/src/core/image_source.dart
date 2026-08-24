import 'package:flutter/foundation.dart';

/// Describes how image bytes are obtained. This is intentionally separate from
/// [ImageMediaKind], which describes how those bytes are rendered.
enum ImageSourceKind {
  invalid,
  asset,
  file,
  network,
  // firebaseStorage,
  unsupported,
}

/// Describes the media contained by an image source.
enum ImageMediaKind {
  raster,
  svg,
  lottie,
  dotLottie,
  unknown,
}

@immutable
final class ResolvedImageSource {
  const ResolvedImageSource({
    required this.original,
    required this.normalized,
    required this.kind,
    required this.extensionHint,
    required this.mediaHint,
    this.uri,
    this.filePath,
    this.error,
  });

  final String original;
  final String normalized;
  final ImageSourceKind kind;
  final String? extensionHint;
  final ImageMediaKind mediaHint;
  final Uri? uri;
  final String? filePath;
  final String? error;

  bool get isValid =>
      kind != ImageSourceKind.invalid && kind != ImageSourceKind.unsupported;

  bool get isRemote =>
      kind == ImageSourceKind.network;
      // || kind == ImageSourceKind.firebaseStorage;

  bool get isLocal =>
      kind == ImageSourceKind.asset || kind == ImageSourceKind.file;

  String get canonicalIdentity {
    switch (kind) {
      case ImageSourceKind.network:
      // case ImageSourceKind.firebaseStorage:
        final parsed = uri;
        if (parsed == null) return normalized;
        return parsed.replace(fragment: '').toString();
      case ImageSourceKind.file:
        return filePath ?? normalized;
      case ImageSourceKind.asset:
        return normalized;
      case ImageSourceKind.invalid:
      case ImageSourceKind.unsupported:
        return original;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is ResolvedImageSource &&
        other.original == original &&
        other.normalized == normalized &&
        other.kind == kind &&
        other.extensionHint == extensionHint &&
        other.mediaHint == mediaHint &&
        other.uri == uri &&
        other.filePath == filePath &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(
        original,
        normalized,
        kind,
        extensionHint,
        mediaHint,
        uri,
        filePath,
        error,
      );
}
