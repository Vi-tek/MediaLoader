import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../core/image_cache_identity.dart';
import '../core/image_media_detector.dart';
import '../core/image_source.dart';
import '../core/image_source_resolver.dart';

import 'default_image_downloader.dart';
import 'image_cache_service.dart';
import 'image_download.dart';
import 'image_downloader.dart';

ImageCacheService createImageCacheService() => NativeImageCacheService();

final class NativeImageCacheService implements ImageCacheService {
  NativeImageCacheService({
    ImageDownloader? downloader,
    Future<Directory> Function()? cacheDirectoryProvider,
    DateTime Function()? clock,
    ImageMediaDetector mediaDetector = const ImageMediaDetector(),
  }) : _downloader = downloader ?? DefaultImageDownloader(),
       _cacheDirectoryProvider =
           cacheDirectoryProvider ?? _defaultCacheDirectory,
       _clock = clock ?? DateTime.now,
       _mediaDetector = mediaDetector;

  final ImageDownloader _downloader;
  final Future<Directory> Function() _cacheDirectoryProvider;
  final DateTime Function() _clock;
  final ImageMediaDetector _mediaDetector;

  final Map<String, CachedImageResource> _memoryIndex =
      <String, CachedImageResource>{};
  final Map<String, Future<CachedImageResource>> _inFlight =
      <String, Future<CachedImageResource>>{};

  Directory? _directory;

  static Future<Directory> _defaultCacheDirectory() async {
    final base = await getApplicationCacheDirectory();
    return Directory('${base.path}${Platform.pathSeparator}uptalk_images');
  }

  @override
  CachedImageResource? peekRemote(
    ResolvedImageSource source, {
    Map<String, String>? headers,
    String? cacheKey,
    Duration cacheDuration = const Duration(days: 30),
    bool includeStale = false,
  }) {
    _validateRemote(source);
    final id = ImageCacheIdentity.cacheId(
      source,
      headers: headers,
      explicitCacheKey: cacheKey,
    );
    final cached = _memoryIndex[id];
    if (cached == null) return null;
    final fresh = cached.isFresh(cacheDuration, _clock());
    if (!fresh && !includeStale) return null;
    return cached.copyWith(stale: !fresh);
  }

  @override
  Future<CachedImageResource> resolveRemote(
    ResolvedImageSource source, {
    Map<String, String>? headers,
    String? cacheKey,
    Duration cacheDuration = const Duration(days: 30),
    bool allowStaleOnError = true,
    Duration requestTimeout = const Duration(seconds: 20),
    int maxDownloadBytes = 32 * 1024 * 1024,
  }) {
    _validateRemote(source);
    if (cacheDuration.isNegative) {
      throw ArgumentError.value(
        cacheDuration,
        'cacheDuration',
        'Cache duration cannot be negative.',
      );
    }
    if (maxDownloadBytes <= 0) {
      throw ArgumentError.value(
        maxDownloadBytes,
        'maxDownloadBytes',
        'Maximum download size must be positive.',
      );
    }

    final id = ImageCacheIdentity.cacheId(
      source,
      headers: headers,
      explicitCacheKey: cacheKey,
    );
    final memory = _memoryIndex[id];
    if (memory != null && memory.isFresh(cacheDuration, _clock())) {
      return Future<CachedImageResource>.value(memory.copyWith(stale: false));
    }

    final requestId =
        '$id|${cacheDuration.inMicroseconds}|'
        '$allowStaleOnError|${requestTimeout.inMicroseconds}|$maxDownloadBytes';
    final existingRequest = _inFlight[requestId];
    if (existingRequest != null) return existingRequest;

    final future = _resolve(
      id,
      source,
      headers: headers ?? const <String, String>{},
      cacheDuration: cacheDuration,
      allowStaleOnError: allowStaleOnError,
      requestTimeout: requestTimeout,
      maxDownloadBytes: maxDownloadBytes,
    );
    _inFlight[requestId] = future;
    future.then<void>(
      (_) {
        _inFlight.remove(requestId);
      },
      onError: (Object _, StackTrace _) {
        _inFlight.remove(requestId);
      },
    );
    return future;
  }

  Future<CachedImageResource> _resolve(
    String cacheId,
    ResolvedImageSource source, {
    required Map<String, String> headers,
    required Duration cacheDuration,
    required bool allowStaleOnError,
    required Duration requestTimeout,
    required int maxDownloadBytes,
  }) async {
    final directory = await _cacheDirectory();
    var existing = _memoryIndex[cacheId];
    existing ??= await _readMetadata(directory, cacheId, source.kind);
    if (existing != null) {
      _memoryIndex[cacheId] = existing;
      if (existing.isFresh(cacheDuration, _clock())) {
        return existing.copyWith(fromPersistentCache: true, stale: false);
      }
    }

    try {
      return await _refresh(
        directory,
        cacheId,
        source,
        existing: existing,
        headers: headers,
        requestTimeout: requestTimeout,
        maxDownloadBytes: maxDownloadBytes,
      );
    } on Object {
      if (allowStaleOnError && existing != null) {
        return existing.copyWith(fromPersistentCache: true, stale: true);
      }
      rethrow;
    }
  }

  Future<CachedImageResource> _refresh(
    Directory directory,
    String cacheId,
    ResolvedImageSource source, {
    required CachedImageResource? existing,
    required Map<String, String> headers,
    required Duration requestTimeout,
    required int maxDownloadBytes,
  }) async {
    final downloaded = await _downloader.download(
      source,
      ImageDownloadRequest(
        headers: headers,
        timeout: requestTimeout,
        maxBytes: maxDownloadBytes,
        ifNoneMatch: existing?.etag,
        ifModifiedSince: existing?.lastModified,
        firebaseGeneration: existing?.remoteGeneration,
      ),
    );

    final now = _clock().toUtc();
    if (downloaded.notModified) {
      if (existing == null) {
        throw const ImageDownloadException(
          'Server returned not-modified without a cached entry.',
        );
      }
      final refreshed = existing.copyWith(
        validatedAt: now,
        contentType: downloaded.contentType ?? existing.contentType,
        etag: downloaded.etag ?? existing.etag,
        lastModified: downloaded.lastModified ?? existing.lastModified,
        remoteGeneration:
            downloaded.remoteGeneration ?? existing.remoteGeneration,
        fromPersistentCache: true,
        stale: false,
      );
      await _writeMetadata(directory, refreshed);
      _memoryIndex[cacheId] = refreshed;
      return refreshed;
    }

    final bytes = downloaded.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const ImageDownloadException('Downloaded image is empty.');
    }

    final mediaKind = _mediaDetector.detect(
      bytes,
      mimeType: downloaded.contentType,
      extensionHint: source.extensionHint,
      fallbackUnknownBinaryToRaster: true,
    );
    if (mediaKind == ImageMediaKind.unknown) {
      throw const ImageDownloadException(
        'Downloaded resource is not a supported image format.',
      );
    }

    final generation = ImageCacheIdentity.bytesGeneration(bytes);
    final dataFileName = '${cacheId}_$generation.bin';
    final dataFile = File(
      '${directory.path}${Platform.pathSeparator}$dataFileName',
    );
    final dataIsAlreadyCommitted =
        await dataFile.exists() && await dataFile.length() == bytes.length;
    if (!dataIsAlreadyCommitted) {
      final tempFile = File(
        '${dataFile.path}.${now.microsecondsSinceEpoch}.tmp',
      );
      try {
        await tempFile.writeAsBytes(bytes, flush: true);
        await _replaceFile(tempFile, dataFile);
      } on Object {
        if (await tempFile.exists()) await tempFile.delete();
        rethrow;
      }
    }

    final resource = CachedImageResource(
      cacheId: cacheId,
      storageToken: dataFileName,
      generation: generation,
      sourceKind: source.kind,
      mediaKind: mediaKind,
      validatedAt: now,
      contentLength: bytes.length,
      contentType: downloaded.contentType,
      etag: downloaded.etag,
      lastModified: downloaded.lastModified,
      remoteGeneration: downloaded.remoteGeneration,
      fromPersistentCache: false,
      stale: false,
    );

    await _writeMetadata(directory, resource);
    _memoryIndex[cacheId] = resource;

    if (existing != null && existing.storageToken != resource.storageToken) {
      final old = File(
        '${directory.path}${Platform.pathSeparator}${existing.storageToken}',
      );
      if (await old.exists()) {
        try {
          await old.delete();
        } on FileSystemException {
          // Best-effort cleanup. The metadata already points at the new file.
        }
      }
    }

    return resource;
  }

  @override
  Future<Uint8List> readBytes(CachedImageResource resource) async {
    final directory = await _cacheDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}${resource.storageToken}',
    );
    final bytes = await file.readAsBytes();
    if (bytes.length != resource.contentLength) {
      throw FileSystemException(
        'Cached image length does not match its metadata.',
      );
    }
    return bytes;
  }

  @override
  Future<void> remove(CachedImageResource resource) async {
    final directory = await _cacheDirectory();
    _memoryIndex.remove(resource.cacheId);
    final data = File(
      '${directory.path}${Platform.pathSeparator}${resource.storageToken}',
    );
    final metadata = File(
      '${directory.path}${Platform.pathSeparator}${resource.cacheId}.json',
    );
    final metadataBackup = File('${metadata.path}.bak');
    if (await data.exists()) await data.delete();
    if (await metadata.exists()) await metadata.delete();
    if (await metadataBackup.exists()) await metadataBackup.delete();
  }

  Future<Directory> _cacheDirectory() async {
    final existing = _directory;
    if (existing != null) return existing;
    final directory = await _cacheDirectoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _directory = directory;
    return directory;
  }

  Future<CachedImageResource?> _readMetadata(
    Directory directory,
    String cacheId,
    ImageSourceKind expectedKind,
  ) async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}$cacheId.json',
    );
    final backup = File('${file.path}.bak');
    if (!await file.exists() && await backup.exists()) {
      try {
        await backup.rename(file.path);
      } on FileSystemException {
        return null;
      }
    }
    if (!await file.exists()) return null;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final resource = _resourceFromJson(decoded);
      if (resource.cacheId != cacheId || resource.sourceKind != expectedKind) {
        return null;
      }
      final data = File(
        '${directory.path}${Platform.pathSeparator}${resource.storageToken}',
      );
      if (!await data.exists()) return null;
      final length = await data.length();
      if (length != resource.contentLength) return null;
      return resource.copyWith(fromPersistentCache: true);
    } on Object {
      return null;
    }
  }

  Future<void> _writeMetadata(
    Directory directory,
    CachedImageResource resource,
  ) async {
    final metadata = File(
      '${directory.path}${Platform.pathSeparator}${resource.cacheId}.json',
    );
    final temp = File(
      '${metadata.path}.${_clock().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temp.writeAsString(
        jsonEncode(_resourceToJson(resource)),
        flush: true,
      );
      await _replaceFile(temp, metadata);
    } on Object {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<void> _replaceFile(File temp, File destination) async {
    try {
      await temp.rename(destination.path);
      return;
    } on FileSystemException {
      if (!await destination.exists()) rethrow;
    }

    final backup = File('${destination.path}.bak');
    if (await backup.exists()) await backup.delete();
    await destination.rename(backup.path);
    try {
      await temp.rename(destination.path);
      if (await backup.exists()) await backup.delete();
    } on Object {
      if (!await destination.exists() && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
  }

  Map<String, Object?> _resourceToJson(CachedImageResource resource) {
    return <String, Object?>{
      'version': 1,
      'cacheId': resource.cacheId,
      'storageToken': resource.storageToken,
      'generation': resource.generation,
      'sourceKind': resource.sourceKind.name,
      'mediaKind': resource.mediaKind.name,
      'validatedAt': resource.validatedAt.toUtc().toIso8601String(),
      'contentLength': resource.contentLength,
      'contentType': resource.contentType,
      'etag': resource.etag,
      'lastModified': resource.lastModified,
      'remoteGeneration': resource.remoteGeneration,
      'complete': true,
    };
  }

  CachedImageResource _resourceFromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['complete'] != true) {
      throw const FormatException('Unsupported image-cache metadata.');
    }
    return CachedImageResource(
      cacheId: json['cacheId'] as String,
      storageToken: json['storageToken'] as String,
      generation: json['generation'] as String,
      sourceKind: ImageSourceKind.values.byName(json['sourceKind'] as String),
      mediaKind: ImageMediaKind.values.byName(json['mediaKind'] as String),
      validatedAt: DateTime.parse(json['validatedAt'] as String).toUtc(),
      contentLength: json['contentLength'] as int,
      contentType: json['contentType'] as String?,
      etag: json['etag'] as String?,
      lastModified: json['lastModified'] as String?,
      remoteGeneration: json['remoteGeneration'] as String?,
      fromPersistentCache: true,
    );
  }

  void _validateRemote(ResolvedImageSource source) {
    if (!source.isRemote) {
      throw ArgumentError.value(
        source.original,
        'source',
        'Only HTTP(S) and gs:// sources use the persistent image cache.',
      );
    }
  }

  /// Native compatibility with the previous synchronous fast-path API.
  File? getCachedFileSync(String sourceValue) {
    final source = const ImageSourceResolver().resolve(sourceValue);
    if (!source.isRemote) return null;
    final directory = _directory;
    if (directory == null) return null;
    final cacheId = ImageCacheIdentity.cacheId(source);
    final resource = _memoryIndex[cacheId];
    if (resource == null) return null;
    final file = _fileForResource(directory, resource);
    if (!file.existsSync() || file.lengthSync() != resource.contentLength) {
      return null;
    }
    return file;
  }

  Future<File> getImageFromUrl(String sourceValue) async {
    final source = const ImageSourceResolver().resolve(sourceValue);
    if (source.kind != ImageSourceKind.network) {
      throw ArgumentError.value(
        sourceValue,
        'source',
        'An HTTP or HTTPS image URL is required.',
      );
    }
    return _resolveLegacyFile(source);
  }

  // Future<File> getImageFromFirebase(Reference reference) {
  //   return _resolveLegacyFile(_sourceFromReference(reference));
  // }

  // Future<File?> revalidateFirebaseImage(Reference reference) async {
  //   final source = _sourceFromReference(reference);
  //   final before = peekRemote(
  //     source,
  //     cacheDuration: Duration.zero,
  //     includeStale: true,
  //   );
  //   final refreshed = await resolveRemote(
  //     source,
  //     cacheDuration: Duration.zero,
  //     allowStaleOnError: true,
  //   );
  //   if (before?.generation == refreshed.generation) return null;
  //   final directory = await _cacheDirectory();
  //   return _fileForResource(directory, refreshed);
  // }

  Future<File> _resolveLegacyFile(ResolvedImageSource source) async {
    final resource = await resolveRemote(source);
    final directory = await _cacheDirectory();
    return _fileForResource(directory, resource);
  }

  ResolvedImageSource _sourceFromReference(Reference reference) {
    final encodedPath = reference.fullPath
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    return const ImageSourceResolver().resolve(
      'gs://${reference.bucket}/$encodedPath',
    );
  }

  File _fileForResource(Directory directory, CachedImageResource resource) {
    return File(
      '${directory.path}${Platform.pathSeparator}${resource.storageToken}',
    );
  }

  @override
  void close() => _downloader.close();
}
