import 'package:flutter/material.dart';

/// Camera screen layout: camera on top, controls below (they scroll if they don't fit).
class CameraLayout extends StatelessWidget {
  const CameraLayout({super.key, required this.camera, required this.panel});
  final Widget camera;
  final List<Widget> panel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: camera),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: panel,
            ),
          ),
        ),
      ],
    );
  }
}
