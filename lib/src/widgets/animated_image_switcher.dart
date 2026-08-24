import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'image_loader.dart';
import 'curved_reveal_clipper.dart';

export 'curved_reveal_clipper.dart';

class AnimatedImageSwitcher extends StatefulWidget {
  final String assetPath;
  final double amplitude;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final bool? animate;
  final bool? repeat;
  final String? errorImage;
  final ColorFilter? colorFilter;
  final List<ColorFilter> colorFilters;

  const AnimatedImageSwitcher(
    this.assetPath, {

    this.width,
    this.amplitude = 20,
    this.height,
    this.fit,
    this.animate,
    this.errorImage,
    this.repeat,
    this.colorFilter,
    this.colorFilters = const [],
    super.key,
  });

  @override
  State<AnimatedImageSwitcher> createState() => _AnimatedImageSwitcherState();
}

class _AnimatedImageSwitcherState extends State<AnimatedImageSwitcher>
    with SingleTickerProviderStateMixin {
  late String _currentAsset;
  String? _nextAsset;

  late AnimationController _controller;
  late Animation<double> _revealAnimation;
  @override
  void initState() {
    super.initState();
    _currentAsset = widget.assetPath;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _revealAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _buildLottie(String asset) {
    final composition = cachedComposition(asset);
    if (composition == null) {
      return RepaintBoundary(
        child: ImageLoader(
          asset,
          errorImage: widget.errorImage,
          key: ValueKey(asset),
          colorFilters: widget.colorFilters,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          animate: widget.animate,
          colorFilter: widget.colorFilter,
          repeat: widget.repeat,
          // The opaque background beneath this widget is intentional; showing
          // a spinner here briefly punches through the chat panel during
          // decoding.
          placeholder: const SizedBox.expand(),
        ),
      );
    }
    Widget lottie = Lottie(
      composition: composition,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      animate: widget.animate ?? true,
      repeat: widget.repeat ?? true,
    );
    for (final filter in <ColorFilter>[
      if (widget.colorFilter != null) widget.colorFilter!,
      ...widget.colorFilters,
    ].reversed) {
      lottie = ColorFiltered(colorFilter: filter, child: lottie);
    }
    return RepaintBoundary(child: lottie);
  }

  @override
  void didUpdateWidget(covariant AnimatedImageSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compare against the asset we're already transitioning to (or showing), not
    // just _currentAsset — _currentAsset only updates when the reveal completes,
    // so a redundant rebuild mid-transition would otherwise reset and replay the
    // animation (it visibly jumps back to the top and plays twice).
    final targetAsset = _nextAsset ?? _currentAsset;
    if (widget.assetPath == targetAsset) return;

    _nextAsset = widget.assetPath;
    _controller
      ..reset()
      ..forward().then((_) {
        if (!mounted) return;
        setState(() {
          _currentAsset = _nextAsset!;
          // Keep the fully revealed image mounted until the next switch. The
          // new base image is created only now and can still be decoding; if
          // this layer is removed immediately, SVG patterns flash blank.
        });
      });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Keep the previous visual fully opaque until the replacement has been
        // revealed. This prevents an undecoded image from exposing the panel
        // behind it.
        Positioned.fill(child: _buildLottie(_currentAsset)),
        if (_nextAsset != null)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _revealAnimation,
              builder: (context, child) {
                return ClipPath(
                  clipper: CurvedRevealClipper(
                    progress: _revealAnimation.value,
                    amplitude: widget.amplitude,
                  ),
                  child: child,
                );
              },
              child: _buildLottie(_nextAsset!),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}