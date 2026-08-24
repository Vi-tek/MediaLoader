import 'image_media_detector.dart';
import 'image_source.dart';

final class ImageSourceResolver {
  const ImageSourceResolver({
    this.mediaDetector = const ImageMediaDetector(),
  });

  final ImageMediaDetector mediaDetector;

  static final RegExp _windowsAbsolutePath = RegExp(r'^[a-zA-Z]:[\\/]');
  static final RegExp _windowsUncPath = RegExp(r'^\\\\[^\\]+\\[^\\]+');

  ResolvedImageSource resolve(String? source) {
    final original = source ?? '';
    final trimmed = original.trim();
    if (trimmed.isEmpty) {
      return ResolvedImageSource(
        original: original,
        normalized: '',
        kind: ImageSourceKind.invalid,
        extensionHint: null,
        mediaHint: ImageMediaKind.unknown,
        error: 'Image source is empty.',
      );
    }

    if (_isNativeAbsolutePath(trimmed)) {
      return _filePath(original, trimmed);
    }

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } on FormatException catch (error) {
      return ResolvedImageSource(
        original: original,
        normalized: trimmed,
        kind: ImageSourceKind.invalid,
        extensionHint: null,
        mediaHint: ImageMediaKind.unknown,
        error: 'Malformed image URI: $error',
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme.isEmpty) {
      return _asset(original, trimmed);
    }

    switch (scheme) {
      case 'file':
        try {
          final path = uri.toFilePath();
          return _filePath(original, path, uri: uri);
        } on Object catch (error) {
          return ResolvedImageSource(
            original: original,
            normalized: trimmed,
            kind: ImageSourceKind.invalid,
            extensionHint: _extensionFromUri(uri),
            mediaHint: ImageMediaKind.unknown,
            uri: uri,
            error: 'Invalid file URI: $error',
          );
        }
      case 'http':
      case 'https':
        if (!uri.hasAuthority || uri.host.isEmpty) {
          return ResolvedImageSource(
            original: original,
            normalized: trimmed,
            kind: ImageSourceKind.invalid,
            extensionHint: _extensionFromUri(uri),
            mediaHint: ImageMediaKind.unknown,
            uri: uri,
            error: 'HTTP image URI must include a host.',
          );
        }
        return _remote(original, uri, ImageSourceKind.network);
      case 'gs':
        if (!uri.hasAuthority || uri.host.isEmpty) {
          return ResolvedImageSource(
            original: original,
            normalized: trimmed,
            kind: ImageSourceKind.invalid,
            extensionHint: _extensionFromUri(uri),
            mediaHint: ImageMediaKind.unknown,
            uri: uri,
            error: 'Firebase Storage URI must include a bucket.',
          );
        }
        return _remote(original, uri, ImageSourceKind.firebaseStorage);
      default:
        return ResolvedImageSource(
          original: original,
          normalized: trimmed,
          kind: ImageSourceKind.unsupported,
          extensionHint: _extensionFromUri(uri),
          mediaHint: ImageMediaKind.unknown,
          uri: uri,
          error: 'Unsupported image URI scheme: $scheme',
        );
    }
  }

  ResolvedImageSource _asset(String original, String path) {
    final extension = _extensionFromPath(path);
    return ResolvedImageSource(
      original: original,
      normalized: path,
      kind: ImageSourceKind.asset,
      extensionHint: extension,
      mediaHint: mediaDetector.fromExtension(extension),
    );
  }

  ResolvedImageSource _filePath(
    String original,
    String path, {
    Uri? uri,
  }) {
    final extension = _extensionFromPath(path);
    return ResolvedImageSource(
      original: original,
      normalized: path,
      kind: ImageSourceKind.file,
      extensionHint: extension,
      mediaHint: mediaDetector.fromExtension(extension),
      uri: uri ?? Uri.file(path),
      filePath: path,
    );
  }

  ResolvedImageSource _remote(
    String original,
    Uri uri,
    ImageSourceKind kind,
  ) {
    final extension = _extensionFromUri(uri);
    return ResolvedImageSource(
      original: original,
      normalized: uri.toString(),
      kind: kind,
      extensionHint: extension,
      mediaHint: mediaDetector.fromExtension(extension),
      uri: uri,
    );
  }

  bool _isNativeAbsolutePath(String source) {
    return source.startsWith('/') ||
        _windowsAbsolutePath.hasMatch(source) ||
        _windowsUncPath.hasMatch(source);
  }

  String? _extensionFromUri(Uri uri) => _extensionFromPath(uri.path);

  String? _extensionFromPath(String path) {
    if (path.isEmpty) return null;
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    final lastDot = name.lastIndexOf('.');
    if (lastDot <= 0 || lastDot == name.length - 1) return null;
    return name.substring(lastDot + 1).toLowerCase();
  }
}
