import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Camera screen layout that works however the phone is held:
/// portrait -> camera on top, controls below (scroll if they don't fit);
/// landscape -> camera fills the screen, controls float in a see-through box top-right
/// that can be hidden with one tap.
class CameraLayout extends StatefulWidget {
  const CameraLayout({super.key, required this.camera, required this.panel});
  final Widget camera;
  final List<Widget> panel;

  @override
  State<CameraLayout> createState() => _CameraLayoutState();
}

class _CameraLayoutState extends State<CameraLayout> {
  bool _panelOpen = true;

  // Portrait and landscape are different layouts; without a fixed identity Flutter would see
  // a *new* camera widget on every turn and open a second camera session while the first is
  // still closing (Android refuses: "too many use cases"). The key moves the same one across.
  final _cameraKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final camera = KeyedSubtree(key: _cameraKey, child: widget.camera);
    final controls = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: widget.panel,
      ),
    );

    if (size.width <= size.height) {
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

    // Landscape: dark theme inside the floating box so text and sliders read on top of video.
    final dark = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Theme.of(context).colorScheme.primary, brightness: Brightness.dark),
      useMaterial3: true,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: Colors.black, child: camera),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Theme(
            data: dark,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _panelOpen ? 'Hide controls' : 'Show controls',
                    icon: Icon(_panelOpen ? Icons.close_fullscreen : Icons.tune),
                    onPressed: () => setState(() => _panelOpen = !_panelOpen),
                  ),
                  if (_panelOpen)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.min(340, size.width * 0.4),
                        maxHeight: size.height * 0.7,
                      ),
                      child: controls,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
