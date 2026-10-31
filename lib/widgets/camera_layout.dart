import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// Camera screen layout that works however the phone is held:
/// portrait -> camera on top, controls below in a panel you resize by dragging its handle (it scrolls);
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

  /// Portrait: the controls panel's share of the screen height. Drag the handle to change it;
  /// shared by every camera screen and kept while the app runs.
  static double _panelShare = 0.24;
  static const _minShare = 0.10, _maxShare = 0.70;

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
          // Drag handle: up = bigger panel, down = bigger camera.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => setState(() {
              _panelShare = (_panelShare - d.delta.dy / size.height).clamp(_minShare, _maxShare);
            }),
            child: SizedBox(
              height: 22,
              child: Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
          ),
          SizedBox(height: size.height * _panelShare, child: controls),
        ],
      );
    }

    // Landscape: dark theme inside the floating box so text and sliders read on top of video.
    final dark = ThemeData(
      // Seeded dark schemes turn buttons pale lavender: keep GinLo's solid blue with white text.
      colorScheme: ColorScheme.fromSeed(seedColor: GinloColors.blue, brightness: Brightness.dark).copyWith(
        primary: GinloColors.blue,
        onPrimary: Colors.white,
        secondaryContainer: GinloColors.blue,
        onSecondaryContainer: Colors.white,
      ),
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
