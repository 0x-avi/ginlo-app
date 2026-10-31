import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Camera screen layout that works however the phone is held:
/// portrait -> camera on top, controls below; landscape -> camera left, controls right.
/// The controls scroll if they don't fit.
class CameraLayout extends StatelessWidget {
  const CameraLayout({super.key, required this.camera, required this.panel});
  final Widget camera;
  final List<Widget> panel;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final controls = SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: panel),
    );
    if (size.width > size.height) {
      return Row(
        children: [
          Expanded(child: camera),
          SizedBox(width: math.min(380, size.width * 0.42), child: controls),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: camera),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * 0.42),
          child: controls,
        ),
      ],
    );
  }
}
