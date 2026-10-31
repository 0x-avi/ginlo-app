import 'detector.dart';
import 'embedder.dart';

/// Loads each model once and keeps it for the app's lifetime (a few MB each), so screens
/// can share them and nothing is ever closed while a background isolate is using it.
class Models {
  static final _detectors = <String, Future<Detector>>{};
  static final _embedders = <String, Future<Embedder>>{};

  static Future<Detector> detector(DetectorSpec spec) => _detectors.putIfAbsent(spec.asset, () => Detector.load(spec));

  static Future<Embedder> embedder(EmbedderSpec spec) => _embedders.putIfAbsent(spec.id, () => Embedder.load(spec));

  /// What the shop app (Bill, Learn) uses. The dev Lab lets you try the others.
  static const billDetector = 0; // index into detectorSpecs: YOLOE products
  static const billEmbedder = 0; // index into embedderSpecs: MobileNet-V3 small
}
