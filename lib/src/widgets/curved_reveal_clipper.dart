import 'dart:math';
import 'package:flutter/material.dart';

class CurvedRevealClipper extends CustomClipper<Path> {
  final double progress;
  final double amplitude;

  CurvedRevealClipper({required this.progress, required this.amplitude});

  @override
  Path getClip(Size size) {
    final path = Path();
    final double revealY = size.height * progress + amplitude;

    path.moveTo(0, 0);
    path.lineTo(0, revealY);

    for (double x = 0; x <= size.width; x++) {
      final y = revealY + amplitude * sin((x / size.width) * 2 * pi);
      path.lineTo(x, y);
    }

    path.lineTo(size.width, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CurvedRevealClipper oldClipper) =>
      oldClipper.progress != progress || oldClipper.amplitude != amplitude;
}
