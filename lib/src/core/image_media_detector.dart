import 'dart:convert';
import 'dart:typed_data';

import 'image_source.dart';

/// Small, side-effect-free media detector.
///
/// It only inspects a bounded prefix for text formats and signatures. Callers
/// that already own the full downloaded bytes can pass them directly.
final class ImageMediaDetector {
  const ImageMediaDetector();

  static const int _textInspectionLimit = 64 * 1024;

  ImageMediaKind fromExtension(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
      case 'bmp':
      case 'wbmp':
      case 'ico':
      case 'avif':
      case 'heic':
      case 'heif':
        return ImageMediaKind.raster;
      case 'svg':
        return ImageMediaKind.svg;
      case 'json':
        // JSON is only a candidate. Its structure must be inspected before it
        // is classified as a Lottie composition.
        return ImageMediaKind.unknown;
      case 'lottie':
        return ImageMediaKind.dotLottie;
      default:
        return ImageMediaKind.unknown;
    }
  }

  ImageMediaKind fromMimeType(String? mimeType) {
    final normalized = mimeType?.split(';').first.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return ImageMediaKind.unknown;
    }
    if (normalized == 'image/svg+xml') return ImageMediaKind.svg;
    if (normalized == 'application/vnd.lottie+zip') {
      return ImageMediaKind.dotLottie;
    }
    if (normalized == 'application/json' ||
        normalized == 'application/lottie+json') {
      return ImageMediaKind.lottie;
    }
    if (normalized.startsWith('image/')) return ImageMediaKind.raster;
    return ImageMediaKind.unknown;
  }

  ImageMediaKind detect(
    Uint8List bytes, {
    String? mimeType,
    String? extensionHint,
    bool fallbackUnknownBinaryToRaster = false,
  }) {
    final mimeHint = fromMimeType(mimeType);
    final extension = extensionHint?.toLowerCase();

    if (_hasPngSignature(bytes) ||
        _hasJpegSignature(bytes) ||
        _hasWebpSignature(bytes) ||
        _hasGifSignature(bytes) ||
        _hasBmpSignature(bytes)) {
      return ImageMediaKind.raster;
    }

    if (_hasZipSignature(bytes) &&
        (mimeHint == ImageMediaKind.dotLottie ||
            extension == 'lottie' ||
            _looksLikeDotLottieArchive(bytes))) {
      return ImageMediaKind.dotLottie;
    }

    final text = _decodeTextPrefix(bytes);
    if (text != null) {
      if (_looksLikeSvg(text)) return ImageMediaKind.svg;
      if (_looksLikeLottieJson(text)) return ImageMediaKind.lottie;
    }

    if (mimeHint == ImageMediaKind.svg ||
        mimeHint == ImageMediaKind.dotLottie) {
      return mimeHint;
    }
    if (mimeHint == ImageMediaKind.raster) {
      return ImageMediaKind.raster;
    }

    final extensionKind = fromExtension(extension);
    if (extensionKind == ImageMediaKind.raster ||
        extensionKind == ImageMediaKind.svg ||
        extensionKind == ImageMediaKind.dotLottie) {
      return extensionKind;
    }

    // A .json suffix is only a candidate. Do not call it Lottie unless the
    // document structure passed the validation above.
    if (fallbackUnknownBinaryToRaster && text == null) {
      return ImageMediaKind.raster;
    }
    return ImageMediaKind.unknown;
  }

  bool _hasPngSignature(Uint8List bytes) {
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    return _startsWith(bytes, signature);
  }

  bool _hasJpegSignature(Uint8List bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
  }

  bool _hasWebpSignature(Uint8List bytes) {
    return bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
  }

  bool _hasGifSignature(Uint8List bytes) {
    if (bytes.length < 6) return false;
    final value = ascii.decode(bytes.sublist(0, 6), allowInvalid: true);
    return value == 'GIF87a' || value == 'GIF89a';
  }

  bool _hasBmpSignature(Uint8List bytes) {
    return bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4d;
  }

  bool _hasZipSignature(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        ((bytes[2] == 0x03 && bytes[3] == 0x04) ||
            (bytes[2] == 0x05 && bytes[3] == 0x06) ||
            (bytes[2] == 0x07 && bytes[3] == 0x08));
  }

  bool _startsWith(Uint8List bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index += 1) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  String? _decodeTextPrefix(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final length = bytes.length < _textInspectionLimit
        ? bytes.length
        : _textInspectionLimit;
    final prefix = Uint8List.sublistView(bytes, 0, length);

    // NUL bytes are a strong signal that this is binary, not SVG/JSON text.
    if (prefix.contains(0)) return null;
    try {
      return utf8.decode(prefix, allowMalformed: false);
    } on FormatException {
      return null;
    }
  }

  bool _looksLikeSvg(String text) {
    final normalized = text
        .replaceFirst('\ufeff', '')
        .replaceFirst(RegExp(r'^\s*<\?xml[^>]*>\s*'), '')
        .replaceFirst(RegExp(r'^\s*<!--.*?-->\s*', dotAll: true), '')
        .trimLeft()
        .toLowerCase();
    return normalized.startsWith('<svg') || normalized.contains('<svg ');
  }

  bool _looksLikeLottieJson(String text) {
    final normalized = text.replaceFirst('\ufeff', '').trimLeft();
    if (!normalized.startsWith('{')) return false;
    return RegExp(r'"v"\s*:\s*"[^"]+"').hasMatch(normalized) &&
        RegExp(r'"layers"\s*:\s*\[').hasMatch(normalized) &&
        RegExp(r'"fr"\s*:\s*-?\d').hasMatch(normalized) &&
        RegExp(r'"ip"\s*:\s*-?\d').hasMatch(normalized) &&
        RegExp(r'"op"\s*:\s*-?\d').hasMatch(normalized);
  }

  bool _looksLikeDotLottieArchive(Uint8List bytes) {
    final prefixLength = bytes.length < _textInspectionLimit
        ? bytes.length
        : _textInspectionLimit;
    final suffixStart = bytes.length <= _textInspectionLimit
        ? 0
        : bytes.length - _textInspectionLimit;
    final prefix = latin1.decode(
      Uint8List.sublistView(bytes, 0, prefixLength),
      allowInvalid: true,
    );
    final suffix = latin1.decode(
      Uint8List.sublistView(bytes, suffixStart, bytes.length),
      allowInvalid: true,
    );
    final names = '$prefix\n$suffix'.toLowerCase();
    return names.contains('manifest.json') && names.contains('animations/');
  }
}
