import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:lottie/lottie.dart';
import '../core/image_media_detector.dart';
import '../core/image_source.dart';
import '../cache/image_cache_service.dart';

import 'decoded_media.dart';
import 'platform_bytes_loader.dart';

/// A request for decoded media, identified by [key].
///
/// [readBytes] is only called on a store miss, so a warm key never touches the
/// asset bundle, the file system or the network cache.
@immutable
final class MediaRequest {
  const MediaRequest({
    required this.key,
    required this.readBytes,
    this.kindHint,
    this.extensionHint,
  });

  /// The store key an asset resolves to. Exposed so callers can [MediaStore.peek]
  /// an asset without building a full request.
  static String assetKey(String path, {AssetBundle? bundle}) {
    final source = bundle ?? rootBundle;
    // Only namespace the key when a non-root bundle is in play (tests), so the
    // common case keeps a short, stable key.
    return identical(source, rootBundle)
        ? 'asset:$path'
        : 'asset:${identityHashCode(source)}:$path';
  }

  factory MediaRequest.asset(
    String path, {
    AssetBundle? bundle,
    ImageMediaKind? kindHint,
    String? extensionHint,
  }) {
    final source = bundle ?? rootBundle;
    return MediaRequest(
      key: assetKey(path, bundle: source),
      kindHint: kindHint,
      extensionHint: extensionHint,
      readBytes: () async {
        final data = await source.load(path);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      },
    );
  }

  factory MediaRequest.file(
    String path, {
    ImageMediaKind? kindHint,
    String? extensionHint,
  }) {
    return MediaRequest(
      key: 'file:$path',
      kindHint: kindHint,
      extensionHint: extensionHint,
      readBytes: () => readPlatformFileBytes(path),
    );
  }

  /// Bytes already downloaded and validated by [ImageCacheService]. The
  /// generation is part of the key so a refreshed remote asset decodes again.
  factory MediaRequest.cached(
    CachedImageResource resource,
    ImageCacheService service,
  ) {
    return MediaRequest(
      key: 'remote:${resource.cacheId}:${resource.generation}',
      kindHint: resource.mediaKind == ImageMediaKind.unknown
          ? null
          : resource.mediaKind,
      readBytes: () => service.readBytes(resource),
    );
  }

  /// Builds a request for a local source, carrying the extension-derived media
  /// kind through when it is decisive so the bytes never need sniffing.
  ///
  /// Results are memoized: this is called from `build`, and every field of the
  /// request — including the closure — is derived purely from the key, so one
  /// instance per key can be shared.
  static MediaRequest? forLocalSource(
    ResolvedImageSource source, {
    AssetBundle? bundle,
  }) {
    final String key;
    switch (source.kind) {
      case ImageSourceKind.asset:
        key = assetKey(source.normalized, bundle: bundle);
        break;
      case ImageSourceKind.file:
        key = 'file:${source.filePath ?? source.normalized}';
        break;
      case ImageSourceKind.network:
      // case ImageSourceKind.firebaseStorage:
      case ImageSourceKind.invalid:
      case ImageSourceKind.unsupported:
        return null;
    }

    final hit = _localRequests.remove(key);
    if (hit != null) {
      _localRequests[key] = hit;
      return hit;
    }

    final hint = source.mediaHint == ImageMediaKind.unknown
        ? null
        : source.mediaHint;
    final request = source.kind == ImageSourceKind.asset
        ? MediaRequest.asset(
            source.normalized,
            bundle: bundle,
            kindHint: hint,
            extensionHint: source.extensionHint,
          )
        : MediaRequest.file(
            source.filePath ?? source.normalized,
            kindHint: hint,
            extensionHint: source.extensionHint,
          );

    if (_localRequests.length >= _maxLocalRequests) {
      _localRequests.remove(_localRequests.keys.first);
    }
    _localRequests[key] = request;
    return request;
  }

  static const int _maxLocalRequests = 512;
  static final Map<String, MediaRequest> _localRequests =
      <String, MediaRequest>{};

  @visibleForTesting
  static void clearRequestCache() => _localRequests.clear();

  final String key;
  final Future<Uint8List> Function() readBytes;
  final ImageMediaKind? kindHint;
  final String? extensionHint;
}

/// Process-wide cache of decoded media.
///
/// Decoding an SVG or a Lottie composition costs far more than painting one,
/// and the result is independent of the widget showing it. Caching the decoded
/// value keyed by source identity means a remount — a list scroll, a route
/// change, a parent rebuild — resolves synchronously through [peek] and paints
/// on the first frame, so no placeholder is ever shown for warm media.
///
/// Entries fall in two tiers: [pin]ned entries survive for the process lifetime
/// (used by startup precaching) and the rest are evicted least-recently-used
/// once [maxWeight] is exceeded.
final class MediaStore {
  MediaStore({this.maxWeight = 48 * 1024 * 1024});

  /// Replaceable so tests can isolate their own store.
  static MediaStore instance = MediaStore();

  static const ImageMediaDetector _detector = ImageMediaDetector();
  static const int _maxFailures = 128;

  final int maxWeight;

  final Map<String, DecodedMedia> _pinned = <String, DecodedMedia>{};
  final Map<String, DecodedMedia> _recent = <String, DecodedMedia>{};
  final Map<String, Future<DecodedMedia>> _inFlight =
      <String, Future<DecodedMedia>>{};
  // Local decode failures are deterministic; remembering them stops a broken
  // asset from re-reading the bundle on every remount.
  final Map<String, Object> _failures = <String, Object>{};

  int _recentWeight = 0;

  int get pinnedCount => _pinned.length;
  int get recentCount => _recent.length;

  /// Synchronous cache probe. Returns null on a miss.
  DecodedMedia? peek(String key) {
    final pinned = _pinned[key];
    if (pinned != null) return pinned;

    final hit = _recent.remove(key);
    if (hit == null) return null;
    _recent[key] = hit;
    return hit;
  }

  /// Probes only the pinned tier — media warmed by startup precaching.
  ///
  /// Callers that treat "precached" as a behavioural signal rather than a mere
  /// cache hit must use this: [peek] also reports media that merely happens to
  /// be resident from an earlier render.
  DecodedMedia? peekPinned(String key) => _pinned[key];

  /// The remembered failure for [key], if a previous decode threw.
  Object? peekFailure(String key) => _failures[key];

  /// Resolves [request], reusing an in-flight decode for the same key so N
  /// widgets showing the same asset trigger exactly one parse.
  Future<DecodedMedia> load(MediaRequest request, {bool pin = false}) {
    final cached = peek(request.key);
    if (cached != null) {
      if (pin) _promote(request.key, cached);
      return SynchronousFuture<DecodedMedia>(cached);
    }

    final failure = _failures[request.key];
    if (failure != null) return Future<DecodedMedia>.error(failure);

    final pending = _inFlight[request.key];
    if (pending != null) return pending;

    // The callback must have a block body: `Map.remove` returns the removed
    // value — this very future — and `whenComplete` would then wait on it.
    final Future<DecodedMedia> future = _decode(request, pin).whenComplete(() {
      _inFlight.remove(request.key);
    });
    _inFlight[request.key] = future;
    return future;
  }

  /// Decodes [request] and keeps it for the process lifetime.
  Future<void> pin(MediaRequest request) async {
    try {
      await load(request, pin: true);
    } on Object {
      // Precaching is best effort; a single bad asset must not abort startup.
    }
  }

  void evict(String key) {
    _pinned.remove(key);
    final removed = _recent.remove(key);
    if (removed != null) _recentWeight -= removed.weight;
    _failures.remove(key);
  }

  void clear() {
    _pinned.clear();
    _recent.clear();
    _failures.clear();
    _recentWeight = 0;
  }

  Future<DecodedMedia> _decode(MediaRequest request, bool pin) async {
    try {
      final bytes = await request.readBytes();
      final kind =
          request.kindHint ??
          _detector.detect(
            bytes,
            extensionHint: request.extensionHint,
            fallbackUnknownBinaryToRaster: true,
          );
      final media = await _decodeBytes(bytes, kind);
      _store(request.key, media, pin);
      return media;
    } on Object catch (error) {
      _rememberFailure(request.key, error);
      rethrow;
    }
  }

  static Future<DecodedMedia> _decodeBytes(
    Uint8List bytes,
    ImageMediaKind kind,
  ) async {
    if (bytes.isEmpty) {
      throw const FormatException('Image source contains no bytes.');
    }
    switch (kind) {
      case ImageMediaKind.raster:
        return DecodedRaster(bytes);
      case ImageMediaKind.svg:
        return DecodedVector(
          ScalableImage.fromSvgString(utf8.decode(bytes), warnF: _ignoreWarning),
          weight: bytes.lengthInBytes,
        );
      case ImageMediaKind.lottie:
        return DecodedAnimation(
          LottieComposition.parseJsonBytes(bytes),
          kind: ImageMediaKind.lottie,
          weight: bytes.lengthInBytes,
        );
      case ImageMediaKind.dotLottie:
        final composition = await LottieComposition.decodeZip(
          bytes,
          // Parameter types are inferred so this file does not need a direct
          // dependency on package:archive for ArchiveFile.
          filePicker: (files) {
            for (final file in files) {
              if (file.name.startsWith('animations/') &&
                  file.name.toLowerCase().endsWith('.json')) {
                return file;
              }
            }
            for (final file in files) {
              final name = file.name.toLowerCase();
              if (name.endsWith('.json') && !name.endsWith('manifest.json')) {
                return file;
              }
            }
            return null;
          },
        );
        if (composition == null) {
          throw const FormatException('dotLottie archive has no animation.');
        }
        return DecodedAnimation(
          composition,
          kind: ImageMediaKind.dotLottie,
          weight: bytes.lengthInBytes,
        );
      case ImageMediaKind.unknown:
        throw const FormatException('Unsupported image content.');
    }
  }

  void _store(String key, DecodedMedia media, bool pin) {
    _failures.remove(key);
    if (pin) {
      _promote(key, media);
      return;
    }
    if (_pinned.containsKey(key)) return;
    _recent[key] = media;
    _recentWeight += media.weight;
    _trim();
  }

  void _promote(String key, DecodedMedia media) {
    final removed = _recent.remove(key);
    if (removed != null) _recentWeight -= removed.weight;
    _pinned[key] = media;
  }

  void _trim() {
    while (_recentWeight > maxWeight && _recent.length > 1) {
      final oldest = _recent.keys.first;
      final removed = _recent.remove(oldest);
      if (removed == null) break;
      _recentWeight -= removed.weight;
    }
  }

  void _rememberFailure(String key, Object error) {
    if (_failures.length >= _maxFailures) {
      _failures.remove(_failures.keys.first);
    }
    _failures[key] = error;
  }

  static void _ignoreWarning(String _) {}
}
