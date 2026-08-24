/// media_loader
///
/// A self-contained Flutter widget and caching layer for loading images from
/// any source (asset, local file, network, Firebase Storage) in any format
/// (raster, SVG, Lottie, dotLottie), with persistent disk caching, in-memory
/// decoded-media caching, and startup precaching.
///
/// The single entry point most callers need is [ImageLoader]:
///
///     ImageLoader('https://example.com/avatar.png', width: 48, height: 48)
///
/// See the package README for the full guide, including the optional hooks
/// exposed in config.dart for customizing app-wide defaults.
library;

export 'src/config.dart';

// Core: source resolution, media detection, cache identity.
export 'src/core/image_cache_identity.dart';
export 'src/core/image_media_detector.dart';
export 'src/core/image_source.dart';
export 'src/core/image_source_cache.dart';
export 'src/core/image_source_resolver.dart';

// Cache: persistent + in-memory remote image caching.
export 'src/cache/default_image_downloader.dart';
export 'src/cache/image_cache_provider.dart';
export 'src/cache/image_cache_service.dart';
export 'src/cache/image_cache_service_factory.dart';
export 'src/cache/image_cache_service_native.dart'
    if (dart.library.html) 'src/cache/image_cache_service_web.dart';
export 'src/cache/image_download.dart';
export 'src/cache/image_downloader.dart';

// Widgets: the loader itself, decoded-media rendering, precaching.
export 'src/widgets/animated_image_switcher.dart';
export 'src/widgets/cached_image_loader.dart';
export 'src/widgets/cached_source_image_provider.dart';
export 'src/widgets/curved_reveal_clipper.dart';
export 'src/widgets/decoded_media.dart';
export 'src/widgets/decoded_media_view.dart';
export 'src/widgets/image_loader.dart';
export 'src/widgets/image_loader_props.dart';
export 'src/widgets/image_precacher.dart';
export 'src/widgets/image_provider_factory.dart';
export 'src/widgets/image_render.dart';
export 'src/widgets/media_store.dart';
export 'src/widgets/platform_bytes_loader.dart';
export 'src/widgets/platform_file_image_provider.dart';
export 'src/widgets/svg_source_image_provider.dart';