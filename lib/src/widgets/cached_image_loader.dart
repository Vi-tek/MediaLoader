import 'dart:developer';

import 'package:flutter/material.dart';
import '../core/image_source.dart';
import '../cache/image_cache_provider.dart';
import '../cache/image_cache_service.dart';

import 'decoded_media_view.dart';
import 'image_loader_props.dart';
import 'image_render.dart';
import 'media_store.dart';

/// Resolves remote media once, preserving its detected media kind instead of
/// recursively sending an extensionless cache filename back through detection.
final class CachedImageLoader extends StatefulWidget {
  const CachedImageLoader({
    required this.source,
    required this.props,
    this.cacheService,
    super.key,
  });

  final ResolvedImageSource source;
  final ImageLoaderProps props;
  final ImageCacheService? cacheService;

  @override
  State<CachedImageLoader> createState() => _CachedImageLoaderState();
}

final class _CachedImageLoaderState extends State<CachedImageLoader> {
  ImageCacheService get _cacheService =>
      widget.cacheService ?? ImageCacheProvider.instance;

  CachedImageResource? _resource;
  Object? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _primeAndResolve();
  }

  @override
  void didUpdateWidget(covariant CachedImageLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = oldWidget.source != widget.source;
    final requestChanged =
        oldWidget.props.resolvedHeaders != widget.props.resolvedHeaders ||
        oldWidget.props.resolvedCacheKey != widget.props.resolvedCacheKey ||
        oldWidget.props.resolvedCacheDuration != widget.props.resolvedCacheDuration ||
        oldWidget.props.resolvedAllowStaleOnError !=
            widget.props.resolvedAllowStaleOnError ||
        !identical(oldWidget.cacheService, widget.cacheService);
    if (sourceChanged || requestChanged) _primeAndResolve();
  }

  void _primeAndResolve() {
    final generation = ++_requestGeneration;
    _error = null;
    _resource = _cacheService.peekRemote(
      widget.source,
      headers: widget.props.resolvedHeaders,
      cacheKey: widget.props.resolvedCacheKey,
      cacheDuration: widget.props.resolvedCacheDuration,
      includeStale: true,
    );
    _resolve(generation);
  }

  Future<void> _resolve(int generation) async {
    try {
      final resource = await _cacheService.resolveRemote(
        widget.source,
        headers: widget.props.resolvedHeaders,
        cacheKey: widget.props.resolvedCacheKey,
        cacheDuration: widget.props.resolvedCacheDuration,
        allowStaleOnError: widget.props.resolvedAllowStaleOnError,
      );
      if (!mounted || generation != _requestGeneration) return;
      if (_resource?.generation == resource.generation &&
          _resource?.stale == resource.stale) {
        return;
      }
      setState(() => _resource = resource);
    } on Object catch (error, stackTrace) {
      log(
        'Image loading failed for ${widget.source.kind.name} source.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || generation != _requestGeneration) return;
      if (_resource != null && widget.props.resolvedAllowStaleOnError) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return buildImageError(context, widget.props);
    final resource = _resource;
    if (resource == null) return buildImagePlaceholder(widget.props);

    if (resource.mediaKind == ImageMediaKind.raster) {
      return buildRasterImage(
        context,
        widget.props,
        widget.source,
        preparedResource: resource,
        cacheService: _cacheService,
      );
    }

    return DecodedMediaView(
      key: ValueKey<String>(resource.generation),
      request: MediaRequest.cached(resource, _cacheService),
      props: widget.props,
    );
  }
}
