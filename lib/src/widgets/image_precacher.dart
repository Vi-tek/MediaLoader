import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../core/image_source.dart';
import '../core/image_source_cache.dart';

import 'image_provider_factory.dart';
import 'media_store.dart';

/// Warms decoded media before it is first shown.
///
/// Precaching used to reload the asset manifest once per directory and decode
/// every file sequentially. Here the manifest is read once and shared, and
/// decodes run with bounded concurrency, so startup warms far more assets in
/// less wall-clock time.
///
/// Vector and animation assets land in [MediaStore] as pinned entries; raster
/// assets are decoded into Flutter's own [ImageCache] so that `Image` resolves
/// them synchronously and skips its placeholder frame.
final class ImagePrecacher {
  const ImagePrecacher._();

  static const int _maxConcurrency = 8;

  static AssetManifest? _manifest;
  static Future<AssetManifest>? _manifestLoad;

  /// The asset manifest, loaded at most once per process.
  static Future<AssetManifest> manifest() {
    final loaded = _manifest;
    if (loaded != null) return SynchronousFuture<AssetManifest>(loaded);
    return _manifestLoad ??= AssetManifest.loadFromAssetBundle(rootBundle).then((
      value,
    ) {
      _manifest = value;
      _manifestLoad = null;
      return value;
    });
  }

  /// Every asset under any of [directories] whose extension resolves to a
  /// supported media kind.
  static Future<List<String>> assetsUnder(Iterable<String> directories) async {
    if (directories.isEmpty) return const <String>[];
    final loaded = await manifest();
    final prefixes = directories.toList(growable: false);
    return loaded
        .listAssets()
        .where(
          (asset) => prefixes.any((prefix) => asset.startsWith(prefix)),
        )
        .toList(growable: false);
  }

  /// Decodes and pins every supported asset under [directories].
  ///
  /// Set [concurrency] to 1 and [gap] to a non-zero duration for background
  /// passes over large directories: SVG and Lottie parsing is synchronous, so
  /// pacing the work keeps it off the critical path instead of bunching it into
  /// a few long frames.
  static Future<void> warmDirectories(
    Iterable<String> directories, {
    int concurrency = _maxConcurrency,
    Duration gap = Duration.zero,
  }) {
    return warmAssets(
      assetsUnder(directories),
      concurrency: concurrency,
      gap: gap,
    );
  }

  /// Decodes and pins [assets]. Failures are swallowed per asset so one bad
  /// file cannot stall startup.
  static Future<void> warmAssets(
    FutureOr<Iterable<String>> assets, {
    int concurrency = _maxConcurrency,
    Duration gap = Duration.zero,
  }) async {
    final paths = await assets;
    await _forEachConcurrently(
      paths,
      _warmAsset,
      concurrency: concurrency,
      gap: gap,
    );
  }

  static Future<void> _warmAsset(String assetPath) async {
    final source = ImageSourceCache.resolve(assetPath);
    if (!source.isValid) return;

    if (source.mediaHint == ImageMediaKind.raster) {
      await _warmRaster(source);
      return;
    }

    final request = MediaRequest.forLocalSource(source);
    if (request == null) return;
    await MediaStore.instance.pin(request);
  }

  /// Pushes a raster asset through Flutter's image cache so the first `Image`
  /// build resolves synchronously instead of showing a placeholder frame.
  static Future<void> _warmRaster(ResolvedImageSource source) {
    final ImageProvider<Object> provider;
    try {
      provider = ImageProviderFactory.shared.imageProviderFromResolved(source);
    } on Object {
      return Future<void>.value();
    }

    final completer = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);
    ImageStreamListener? listener;
    listener = ImageStreamListener(
      (image, synchronousCall) {
        if (!completer.isCompleted) completer.complete();
        // Detach only after the frame ends, so ImageCache._liveImages keeps
        // holding the entry in the meantime. This mirrors precacheImage.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          image.dispose();
          stream.removeListener(listener!);
        }, debugLabel: 'ImagePrecacher.removeListener');
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) completer.complete();
        stream.removeListener(listener!);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  static Future<void> _forEachConcurrently(
    Iterable<String> items,
    Future<void> Function(String item) action, {
    required int concurrency,
    required Duration gap,
  }) async {
    final queue = items.toList(growable: false);
    if (queue.isEmpty) return;

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= queue.length) return;
        try {
          await action(queue[index]);
        } on Object {
          // Best effort: a single unreadable asset must not fail the batch.
        }
        if (gap > Duration.zero) await Future<void>.delayed(gap);
      }
    }

    final workerCount = concurrency < 1
        ? 1
        : (queue.length < concurrency ? queue.length : concurrency);
    await Future.wait(<Future<void>>[
      for (var i = 0; i < workerCount; i++) worker(),
    ]);
  }
}
