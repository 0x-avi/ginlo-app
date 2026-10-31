import 'package:flutter/foundation.dart';

import '../ml/vision.dart';

/// Running timing totals for one model setup (dev build only).
class ModelStats {
  int frames = 0;
  int preSum = 0, inferSum = 0, postSum = 0, embedSum = 0, embedCount = 0, wallSum = 0, boxesSum = 0;
  int minWall = 1 << 30, maxWall = 0;

  double get avgPre => preSum / frames;
  double get avgInfer => inferSum / frames;
  double get avgPost => postSum / frames;
  double get avgEmbed => embedSum / frames;

  /// Per crop, so embedders can be compared regardless of how many boxes there were.
  double get embedPerCrop => embedCount == 0 ? 0 : embedSum / embedCount;

  /// Camera frame in -> results back on the UI thread (includes starting the background isolate).
  double get avgWall => wallSum / frames;
  double get avgBoxes => boxesSum / frames;
}

/// Collects how long every finished analysis took, per model setup. The Logs tab listens to it.
class PerfLog extends ChangeNotifier {
  PerfLog._();
  static final instance = PerfLog._();

  /// "detector + embedder" -> stats, in the order they were first used.
  final Map<String, ModelStats> stats = {};

  void record(String setup, VisionResult r, int wallMs) {
    final s = stats.putIfAbsent(setup, ModelStats.new)
      ..frames += 1
      ..preSum += r.preMs
      ..inferSum += r.inferMs
      ..postSum += r.postMs
      ..embedSum += r.embedMs
      ..embedCount += r.embedCount
      ..wallSum += wallMs
      ..boxesSum += r.detections.length;
    if (wallMs < s.minWall) s.minWall = wallMs;
    if (wallMs > s.maxWall) s.maxWall = wallMs;
    notifyListeners();
  }

  void clear() {
    stats.clear();
    notifyListeners();
  }
}
