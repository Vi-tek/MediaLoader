import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:lottie/lottie.dart';
import '../core/image_source.dart';

import 'decoded_media.dart';
import 'image_render.dart';
import 'image_loader_props.dart';
import 'media_store.dart';

/// Renders any non-raster-provider media (SVG, Lottie, dotLottie, in-memory
/// raster) through [MediaStore].
///
/// This replaces the three separate async widgets the loader used to need — one
/// to read local bytes, one to read cached remote bytes and one to parse SVG —
/// each of which restarted from nothing on every mount and showed a spinner
/// while it did. Here the store is probed synchronously in [initState], so warm
/// media paints on the very first frame and never flashes a placeholder.
final class DecodedMediaView extends StatefulWidget {
  const DecodedMediaView({
    required this.request,
    required this.props,
    this.store,
    super.key,
  });

  final MediaRequest request;
  final ImageLoaderProps props;
  final MediaStore? store;

  @override
  State<DecodedMediaView> createState() => _DecodedMediaViewState();
}

final class _DecodedMediaViewState extends State<DecodedMediaView> {
  MediaStore get _store => widget.store ?? MediaStore.instance;

  DecodedMedia? _media;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant DecodedMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.key != widget.request.key ||
        oldWidget.store != widget.store) {
      _resolve();
    }
  }

  void _resolve() {
    final generation = ++_generation;
    final key = widget.request.key;

    final cached = _store.peek(key);
    if (cached != null) {
      _media = cached;
      _error = null;
      return;
    }

    final failure = _store.peekFailure(key);
    if (failure != null) {
      _media = null;
      _error = failure;
      return;
    }

    _media = null;
    _error = null;
    _store
        .load(widget.request)
        .then((media) {
          if (!mounted || generation != _generation) return;
          setState(() => _media = media);
        })
        .catchError((Object error) {
          if (!mounted || generation != _generation) return;
          setState(() => _error = error);
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return buildImageError(context, widget.props);
    final media = _media;
    if (media == null) return buildImagePlaceholder(widget.props);

    final props = widget.props;
    switch (media) {
      case DecodedRaster(:final bytes):
        return Image.memory(
          bytes,
          width: props.width,
          height: props.height,
          fit: props.fit ?? BoxFit.fitHeight,
          gaplessPlayback: true,
          cacheWidth: props.resolvedCacheWidth,
          cacheHeight: props.resolvedCacheHeight,
          semanticLabel: props.resolvedSemanticLabel,
          excludeFromSemantics: props.resolvedExcludeFromSemantics,
          errorBuilder: (context, error, stackTrace) =>
              buildImageError(context, props),
        );
      case DecodedVector(:final image):
        return applyImageSemantics(
          SizedBox(
            width: props.width,
            height: props.height,
            child: ScalableImageWidget(
              si: image,
              fit: props.fit ?? BoxFit.fitHeight,
            ),
          ),
          props,
        );
      case DecodedAnimation(:final composition):
        return applyImageSemantics(
          RepaintBoundary(
            child: Lottie(
              composition: composition,
              width: props.width,
              height: props.height,
              fit: props.fit,
              animate: props.animate ?? false,
              repeat: props.repeat,
            ),
          ),
          props,
        );
    }
  }
}

/// Convenience wrapper for local (asset or file) sources.
final class LocalMediaView extends StatelessWidget {
  const LocalMediaView({
    required this.source,
    required this.props,
    this.store,
    super.key,
  });

  final ResolvedImageSource source;
  final ImageLoaderProps props;
  final MediaStore? store;

  @override
  Widget build(BuildContext context) {
    final request = MediaRequest.forLocalSource(
      source,
      bundle: DefaultAssetBundle.of(context),
    );
    if (request == null) return buildImageError(context, props);
    return DecodedMediaView(request: request, props: props, store: store);
  }
}
