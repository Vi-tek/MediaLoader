media_loader

A self-contained Flutter package for loading and caching images and media.
Supports asset, local file, network, and Firebase Storage sources, in raster,
SVG, Lottie, and dotLottie form, with persistent disk caching, in-memory
decoded-media caching, and startup precaching.

Extracted from the UpTalk app's image loading subsystem. No app-specific
dependency remains; every previously app-coupled behavior is now an optional
hook in lib/src/config.dart.


USING IT IN ANOTHER PROJECT

Path dependency (same machine, monorepo style):

  dependencies:
    media_loader:
      path: ../path/to/media_loader

Git dependency (separate repos):

  dependencies:
    media_loader:
      git:
        url: https://your-git-host/media_loader.git

Then:

  import 'package:media_loader/media_loader.dart';

  ImageLoader('https://example.com/avatar.png', width: 48, height: 48)
  ImageLoader('assets/icons/star.svg', width: 24, height: 24)
  ImageLoader('assets/animations/celebrate.json', animate: true)


SUPPORTED SOURCES

  assets/foo.png                          asset (bundled)
  /absolute/or/relative/path.png          local file
  https://example.com/foo.png             network, cached to disk
  gs://bucket/path/to/foo.png             Firebase Storage, cached to disk

Media kind (raster / svg / lottie / dotLottie) is detected from the file
extension first and, for remote sources, confirmed from the downloaded bytes'
signature/content so an extensionless URL still resolves correctly.


CORE PIECES

  ImageLoader                 the widget most callers use directly
  AnimatedImageSwitcher       ImageLoader wrapped in a curved-reveal cross-fade
                               transition when the asset path changes
  ImageLoader.imageProvider   get a bare ImageProvider for APIs that need one
                               (e.g. PaletteGenerator.fromImageProvider)
  ImageCacheProvider.instance the process-wide persistent image cache service
                               (disk-backed on native, in-memory on web)
  MediaStore.instance          process-wide cache of *decoded* SVG/Lottie media,
                               so remounting the same source repaints instantly
  ImagePrecacher                warms assets under given directories at startup


OPTIONAL HOOKS (lib/src/config.dart)

Every hook defaults to a neutral no-op, so the package works with zero setup.
Set any of these once at app startup to customize behavior globally:

  colorSourceDecoder        Color? Function(String? source)
    Lets a host app encode non-image strings (e.g. "color#RRGGBB") into the
    same field ImageLoader takes as an asset path, and paint a solid color
    instead of resolving an image.

  legacyCompositionLookup   LottieComposition? Function(String assetPath)
    Fallback composition lookup consulted only after MediaStore's own pinned
    cache misses, for apps migrating from their own Lottie cache.

  defaultErrorImage         String?
    Asset path shown when image resolution fails and the widget was not given
    its own errorImage. Left null, ImageLoader falls back to a plain
    broken-image icon.

  imagePlaceholderBuilder (lib/src/widgets/image_render.dart)
    Widget Function(ImageLoaderProps props)?
    Replaces the default inert placeholder box shown while media is loading.


CACHING MODEL

  - Persistent cache (ImageCacheProvider.instance): downloaded remote bytes,
    keyed by a SHA-256 hash of the source identity, headers, and any explicit
    cache key. Disk-backed on iOS/Android/desktop (path_provider), in-memory
    only on web. Respects ETag / Last-Modified / Firebase generation for
    conditional revalidation, and serves stale-on-error by default.
  - Decoded-media cache (MediaStore.instance): parsed SVG and Lottie/dotLottie
    results, so a remount never re-parses. Bounded by weight with LRU
    eviction; ImagePrecacher can pin entries for the app's lifetime.
  - ImageProviderFactory memoizes ImageProvider instances by their resolved
    identity so Image widgets skip re-resolving on rebuild.


TESTING

  cd packages/media_loader
  flutter test

Fakes for ImageDownloader / ImageCacheService and PNG/JPEG fixtures are under
test/support and test/fixtures.
