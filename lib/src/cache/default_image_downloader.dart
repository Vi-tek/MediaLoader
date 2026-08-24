import 'dart:async';
import 'dart:typed_data';

// import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import '../core/image_source.dart';

import 'image_download.dart';
import 'image_downloader.dart';

final class DefaultImageDownloader implements ImageDownloader {
  DefaultImageDownloader({
    http.Client? httpClient,
    // FirebaseStorage? firebaseStorage,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;
  // _firebaseStorage = firebaseStorage;

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  // final FirebaseStorage? _firebaseStorage;

  @override
  Future<DownloadedImage> download(
    ResolvedImageSource source,
    ImageDownloadRequest request,
  ) {
    switch (source.kind) {
      case ImageSourceKind.network:
        return _downloadHttp(source, request);
      // case ImageSourceKind.firebaseStorage:
      //   return _downloadFirebase(source, request);
      case ImageSourceKind.invalid:
      case ImageSourceKind.asset:
      case ImageSourceKind.file:
      case ImageSourceKind.unsupported:
        throw ArgumentError.value(
          source.original,
          'source',
          'Only HTTP(S) and gs:// sources can be downloaded.',
        );
    }
  }

  Future<DownloadedImage> _downloadHttp(
    ResolvedImageSource source,
    ImageDownloadRequest request,
  ) async {
    final uri = source.uri;
    if (uri == null) {
      throw const ImageDownloadException('Resolved HTTP source has no URI.');
    }

    final httpRequest = http.Request('GET', uri)
      ..followRedirects = true
      ..maxRedirects = 5
      ..headers.addAll(request.headers);
    final ifNoneMatch = request.ifNoneMatch;
    if (ifNoneMatch != null) {
      httpRequest.headers['if-none-match'] = ifNoneMatch;
    }
    final ifModifiedSince = request.ifModifiedSince;
    if (ifModifiedSince != null) {
      httpRequest.headers['if-modified-since'] = ifModifiedSince;
    }

    final response = await _httpClient
        .send(httpRequest)
        .timeout(request.timeout);

    if (response.statusCode == 304) {
      await response.stream.drain<void>();
      return DownloadedImage(
        notModified: true,
        statusCode: response.statusCode,
        finalUri: response.request?.url,
        contentType: _contentType(response.headers['content-type']),
        etag: response.headers['etag'],
        lastModified: response.headers['last-modified'],
        remoteGeneration: null,
        declaredContentLength: response.contentLength,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw ImageDownloadException(
        'The image server returned a non-success status.',
        statusCode: response.statusCode,
      );
    }

    final declaredLength = response.contentLength;
    if (declaredLength != null && declaredLength > request.maxBytes) {
      await response.stream.listen(null).cancel();
      throw ImageDownloadException(
        'Image exceeds the configured ${request.maxBytes}-byte limit.',
      );
    }

    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.stream.timeout(request.timeout)) {
      received += chunk.length as int;
      if (received > request.maxBytes) {
        throw ImageDownloadException(
          'Image exceeds the configured ${request.maxBytes}-byte limit.',
        );
      }
      builder.add(chunk);
    }

    return DownloadedImage(
      notModified: false,
      statusCode: response.statusCode,
      finalUri: response.request?.url,
      contentType: _contentType(response.headers['content-type']),
      etag: response.headers['etag'],
      lastModified: response.headers['last-modified'],
      remoteGeneration: null,
      declaredContentLength: response.contentLength,
      bytes: builder.takeBytes(),
    );
  }

  // Future<DownloadedImage> _downloadFirebase(
  //   ResolvedImageSource source,
  //   ImageDownloadRequest request,
  // ) async {
  //   final storage = _firebaseStorage ?? FirebaseStorage.instance;
  //   final reference = storage.refFromURL(source.normalized);
  //   final metadata = await reference.getMetadata().timeout(request.timeout);
  //   final generation = metadata.generation;

  //   if (generation != null && generation == request.firebaseGeneration) {
  //     return DownloadedImage(
  //       notModified: true,
  //       statusCode: 304,
  //       finalUri: source.uri,
  //       contentType: metadata.contentType,
  //       etag: metadata.md5Hash,
  //       lastModified: metadata.updated?.toUtc().toIso8601String(),
  //       remoteGeneration: generation,
  //       declaredContentLength: metadata.size,
  //     );
  //   }

  //   final declaredSize = metadata.size;
  //   if (declaredSize != null && declaredSize > request.maxBytes) {
  //     throw ImageDownloadException(
  //       'Image exceeds the configured ${request.maxBytes}-byte limit.',
  //     );
  //   }

  //   final bytes = await reference
  //       .getData(request.maxBytes)
  //       .timeout(request.timeout);
  //   if (bytes == null) {
  //     throw const ImageDownloadException(
  //       'Firebase Storage returned no image bytes.',
  //     );
  //   }

  //   return DownloadedImage(
  //     notModified: false,
  //     statusCode: 200,
  //     finalUri: source.uri,
  //     contentType: metadata.contentType,
  //     etag: metadata.md5Hash,
  //     lastModified: metadata.updated?.toUtc().toIso8601String(),
  //     remoteGeneration: generation,
  //     declaredContentLength: metadata.size,
  //     bytes: Uint8List.fromList(bytes),
  //   );
  // }

  String? _contentType(String? header) {
    return header?.split(';').first.trim().toLowerCase();
  }

  @override
  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
