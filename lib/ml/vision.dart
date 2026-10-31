import 'dart:isolate';
import 'dart:typed_data';

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

  /// With allTurns: the same box fingerprinted turned 90°, 180° and 270° (teaching).
  final List<List<Float32List>?> turned;
  final int preMs, inferMs, postMs, embedMs, embedCount;

  const VisionResult(
    this.detections,
    this.vectors,
    this.crops,
    this.turned,
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
    bool allTurns = false,
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
      allTurns,
    );
    final run = _tail.then((_) => _spawn(job));
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  // Static, so the isolate closure can't accidentally capture an Interpreter (they can't be sent).
  static Future<VisionResult> _spawn(_Job job) => Isolate.run(() => _run(job));
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
  final bool allTurns;
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
    this.allTurns,
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
  final turned = List<List<Float32List>?>.filled(dets.length, null);
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
    Float32List embed(int i, int turns) {
      prepareEmbedderInput(job.frame, dets[i].box, crop, turns: turns);
      emb.getInputTensor(0).data = crop.buffer.asUint8List();
      emb.invoke();
      final o = emb.getOutputTensor(0).data;
      return l2normalize(o.buffer.asFloat32List(o.offsetInBytes, o.lengthInBytes ~/ 4));
    }

    for (final i in picked) {
      vectors[i] = embed(i, 0);
      if (job.allTurns) turned[i] = [embed(i, 1), embed(i, 2), embed(i, 3)];
      if (job.wantCrops) crops[i] = cropJpeg(job.frame, dets[i].box);
    }
  }
  final embedMs = sw.elapsedMilliseconds - preMs - inferMs - postMs;
  return VisionResult(dets, vectors, crops, turned, preMs, inferMs, postMs, embedMs, picked.length);
}
