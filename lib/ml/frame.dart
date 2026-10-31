import 'dart:typed_data';

import 'package:camera/camera.dart';

/// A copy of one camera frame that can be sent to a background isolate.
/// Android gives YUV420: a full-size brightness plane (Y) and quarter-size colour planes (U, V).
class FrameData {
  final Uint8List y, u, v;
  final int width, height, yRowStride, uvRowStride, uvPixelStride;

  /// Clockwise degrees to turn the sensor image upright (the camera's sensorOrientation).
  final int rotation;

  FrameData(CameraImage img, this.rotation)
    : y = img.planes[0].bytes,
      u = img.planes[1].bytes,
      v = img.planes[2].bytes,
      width = img.width,
      height = img.height,
      yRowStride = img.planes[0].bytesPerRow,
      uvRowStride = img.planes[1].bytesPerRow,
      uvPixelStride = img.planes[1].bytesPerPixel ?? 1;

  bool get _turned => rotation == 90 || rotation == 270;

  /// Size of the frame as the user sees it (portrait).
  int get uprightWidth => _turned ? height : width;
  int get uprightHeight => _turned ? width : height;

  /// Colour of the upright pixel (ux, uy) as 0xRRGGBB.
  int rgb(int ux, int uy) {
    // upright pixel -> sensor pixel
    int sx, sy;
    switch (rotation) {
      case 90:
        sx = uy;
        sy = height - 1 - ux;
      case 180:
        sx = width - 1 - ux;
        sy = height - 1 - uy;
      case 270:
        sx = width - 1 - uy;
        sy = ux;
      default:
        sx = ux;
        sy = uy;
    }
    final yv = y[sy * yRowStride + sx];
    final uvi = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;
    final uu = u[uvi] - 128, vv = v[uvi] - 128;
    final r = (yv + 1.402 * vv).round().clamp(0, 255);
    final g = (yv - 0.344 * uu - 0.714 * vv).round().clamp(0, 255);
    final b = (yv + 1.772 * uu).round().clamp(0, 255);
    return (r << 16) | (g << 8) | b;
  }
}
