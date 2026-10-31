import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detector.dart';
import 'embedder.dart';
import 'frame.dart';

/// Which boxes get a fingerprint after detection.
enum EmbedPick {
  none, // detection only
  largest, // just the biggest box (teaching: the product you're holding up)
  all, // every box, highest score first, up to maxEmbeds (billing)
}

/// One frame's analysis: boxes, and for picked boxes a fingerprint (+ crop JPEG if asked).
class VisionResult {
  final List<Detection> detections;

  /// Same order as [detections]; null where that box wasn't embedded.
  final List<Float32List?> vectors;
  final List<Uint8List?> crops;
  final int preMs, inferMs, postMs, embedMs, embedCount;

  const VisionResult(
    this.detections,
    this.vectors,
    this.crops,
    this.preMs,
    this.inferMs,
    this.postMs,
    this.embedMs,
    this.embedCount,
  );

  /// Index of the biggest box, or -1.
  int get largest {
    var best = -1;
    var area = 0.0;
    for (var i = 0; i < detections.length; i++) {
      final a = detections[i].box.width * detections[i].box.height;
      if (a > area) {
        area = a;
        best = i;
      }
    }
    return best;
  }
}

/// Runs detection and then the embedder on the chosen boxes, in one background isolate.
class Vision {
  // All model runs go one after another (a chain of futures): two screens can never
  // use the same interpreter at the same time, even while switching tabs.
  static Future<void> _tail = Future.value();

  static Future<VisionResult> analyze(
    Detector detector,
    FrameData frame, {
    Embedder? embedder,
    double conf = 0.25,
    EmbedPick pick = EmbedPick.none,
    int maxEmbeds = 12,
    bool wantCrops = false,
  }) {
    final job = _Job(
      detector.interpreter.address,
      detector.spec,
      detector.labels,
      embedder?.interpreter.address,
      frame,
      conf,
      embedder == null ? EmbedPick.none : pick,
      maxEmbeds,
      wantCrops,
    );
    return _queue(() => _spawn(job));
  }

  /// Teaching: fingerprint one box in every [teachVariants] way (turned, darker, brighter, further,
  /// closer), plus its crop picture. Runs once per Capture tap, not on every live frame.
  static Future<({List<Float32List> vectors, Uint8List crop})> embedVariants(
    Embedder embedder,
    FrameData frame,
    Rect box,
  ) {
    final address = embedder.interpreter.address;
    return _queue(() => _spawnVariants(address, frame, box));
  }

  /// Upgrading old angles: fingerprint each stored crop picture (JPEG) in every [teachVariants] way.
  /// One list of vectors per picture, in the same order.
  static Future<List<List<Float32List>>> embedStoredVariants(Embedder embedder, List<Uint8List> jpegs) {
    final address = embedder.interpreter.address;
    return _queue(
      () => Isolate.run(() {
        final emb = Interpreter.fromAddress(address, allocated: true);
        final input = Float32List(Embedder.size * Embedder.size * 3);
        List<Float32List> variants(ImagePixels px) => [
          for (final v in teachVariants) _embed(emb, px, storedCropBox, input, v),
        ];
        return [for (final jpeg in jpegs) variants(ImagePixels(img.decodeJpg(jpeg)!))];
      }),
    );
  }

  static Future<T> _queue<T>(Future<T> Function() work) {
    final run = _tail.then((_) => work());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  // Static, so the isolate closures can't accidentally capture an Interpreter (they can't be sent).
  static Future<VisionResult> _spawn(_Job job) => Isolate.run(() => _run(job));

  static Future<({List<Float32List> vectors, Uint8List crop})> _spawnVariants(int address, FrameData frame, Rect box) =>
      Isolate.run(() {
        final emb = Interpreter.fromAddress(address, allocated: true);
        final input = Float32List(Embedder.size * Embedder.size * 3);
        return (
          vectors: [for (final v in teachVariants) _embed(emb, frame, box, input, v)],
          crop: cropJpeg(frame, box),
        );
      });
}

Float32List _embed(Interpreter emb, Pixels frame, Rect box, Float32List input, Variant v) {
  prepareEmbedderInput(frame, box, input, pad: v.pad, turns: v.turns, gain: v.gain);
  emb.getInputTensor(0).data = input.buffer.asUint8List();
  emb.invoke();
  final o = emb.getOutputTensor(0).data;
  return l2normalize(o.buffer.asFloat32List(o.offsetInBytes, o.lengthInBytes ~/ 4));
}

class _Job {
  final int detAddress;
  final DetectorSpec spec;
  final List<String> labels;
  final int? embAddress;
  final FrameData frame;
  final double conf;
  final EmbedPick pick;
  final int maxEmbeds;
  final bool wantCrops;
  _Job(
    this.detAddress,
    this.spec,
    this.labels,
    this.embAddress,
    this.frame,
    this.conf,
    this.pick,
    this.maxEmbeds,
    this.wantCrops,
  );
}

VisionResult _run(_Job job) {
  final sw = Stopwatch()..start();
  // Same native interpreter, re-wrapped in this isolate by its memory address.
  final det = Interpreter.fromAddress(job.detAddress, allocated: true);

  final input = Float32List(3 * Detector.size * Detector.size);
  final lb = prepareDetectorInput(job.frame, input, job.spec.channelsFirst);
  det.getInputTensor(0).data = input.buffer.asUint8List();
  final preMs = sw.elapsedMilliseconds;

  det.invoke();
  final inferMs = sw.elapsedMilliseconds - preMs;

  // YOLOE also outputs mask prototypes; the boxes are the 3-D output [1, 4 + classes (+32 mask), 8400].
  final out = det.getOutputTensors().firstWhere((t) => t.shape.length == 3);
  final raw = out.data.buffer.asFloat32List(out.data.offsetInBytes, out.data.lengthInBytes ~/ 4);
  final dets = decodeDetections(raw, out.shape[2], job.spec, job.labels, job.conf, lb);
  final postMs = sw.elapsedMilliseconds - preMs - inferMs;

  final vectors = List<Float32List?>.filled(dets.length, null);
  final crops = List<Uint8List?>.filled(dets.length, null);
  final picked = <int>[];
  if (job.pick == EmbedPick.all) {
    picked.addAll(List.generate(dets.length, (i) => i).take(job.maxEmbeds)); // dets are sorted by score
  } else if (job.pick == EmbedPick.largest && dets.isNotEmpty) {
    var best = 0;
    for (var i = 1; i < dets.length; i++) {
      if (dets[i].box.width * dets[i].box.height > dets[best].box.width * dets[best].box.height) best = i;
    }
    picked.add(best);
  }
  if (picked.isNotEmpty) {
    final emb = Interpreter.fromAddress(job.embAddress!, allocated: true);
    final crop = Float32List(Embedder.size * Embedder.size * 3);
    for (final i in picked) {
      vectors[i] = _embed(emb, job.frame, dets[i].box, crop, teachVariants.first);
      if (job.wantCrops) crops[i] = cropJpeg(job.frame, dets[i].box);
    }
  }
  final embedMs = sw.elapsedMilliseconds - preMs - inferMs - postMs;
  return VisionResult(dets, vectors, crops, preMs, inferMs, postMs, embedMs, picked.length);
}
