import 'package:flutter/foundation.dart';

@immutable
final class ImageDownloadRequest {
  const ImageDownloadRequest({
    required this.headers,
    required this.timeout,
    required this.maxBytes,
    this.ifNoneMatch,
    this.ifModifiedSince,
    this.firebaseGeneration,
  });

  final Map<String, String> headers;
  final Duration timeout;
  final int maxBytes;
  final String? ifNoneMatch;
  final String? ifModifiedSince;
  final String? firebaseGeneration;
}

@immutable
final class DownloadedImage {
  const DownloadedImage({
    required this.notModified,
    required this.statusCode,
    required this.finalUri,
    required this.contentType,
    required this.etag,
    required this.lastModified,
    required this.remoteGeneration,
    this.declaredContentLength,
    this.bytes,
  });

  final bool notModified;
  final int statusCode;
  final Uri? finalUri;
  final String? contentType;
  final String? etag;
  final String? lastModified;
  final String? remoteGeneration;
  final int? declaredContentLength;
  final Uint8List? bytes;
}

final class ImageDownloadException implements Exception {
  const ImageDownloadException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'ImageDownloadException: $message'
      : 'ImageDownloadException($statusCode): $message';
}
