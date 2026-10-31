import 'package:flutter/foundation.dart';

import '../ml/detector.dart';

/// Running timing totals for one model (dev build only).
class ModelStats {
  int frames = 0;
  int preSum = 0, inferSum = 0, postSum = 0, wallSum = 0, boxesSum = 0;
  int minWall = 1 << 30, maxWall = 0;

  double get avgPre => preSum / frames;
  double get avgInfer => inferSum / frames;
  double get avgPost => postSum / frames;

  /// Camera frame in -> boxes back on the UI thread (includes starting the background isolate).
  double get avgWall => wallSum / frames;
  double get avgBoxes => boxesSum / frames;
}

/// Collects how long every finished detection took, per model. The Logs tab listens to it.
class PerfLog extends ChangeNotifier {
  PerfLog._();
  static final instance = PerfLog._();

  /// Model title -> stats, in the order models were first used.
  final Map<String, ModelStats> stats = {};

  void record(String model, DetectResult r, int wallMs) {
    final s = stats.putIfAbsent(model, ModelStats.new)
      ..frames += 1
      ..preSum += r.preMs
      ..inferSum += r.inferMs
      ..postSum += r.postMs
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
