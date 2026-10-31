import 'package:flutter/services.dart' show appFlavor;

/// Which app this is. Set by `flutter run --flavor dev|prod` (default: dev, see pubspec.yaml).
/// Dev shows live boxes, confidence scores and a model picker; prod hides all of that.
final bool isDev = appFlavor != 'prod';
