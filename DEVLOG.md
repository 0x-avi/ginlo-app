# GinLo dev log

One entry per iteration: what we set out to do, files touched, how it went (including what broke).
Newest at the bottom. Commit hashes are on `main`.

---

## 1. Base app — `5b7aca4`, `0430cc7`, `da838f3`
**Goal:** a new Flutter repo (Android only) with every package installed, running on the phone.
- Created the project `ginlo` (app id `in.ginlo.ginlo`).
- Packages: `camera`, `tflite_flutter`, `image`, `sqflite`, `path`, `path_provider`, `qr_flutter`, `pdf`,
  `share_plus`, `speech_to_text`, `fl_chart`.
- Android: `minSdk 26`, camera + microphone permissions, speech-recogniser query
  (`android/app/build.gradle.kts`, `AndroidManifest.xml`).
- App shell: tabs Home / Bill / Catalog (`lib/main.dart`, `lib/screens/*_screen.dart`), widget test.

**How it went:** `tflite_flutter` failed to build (Java 11 vs Kotlin 17 targets) → relaxed the check in
`android/gradle.properties`. The USB cable kept dropping → switched to wireless debugging.

## 2. Models, flavors, database, live detector — `6c4ee4b` … `9b9f877`
**Goal:** all on-device models in the app; separate dev/prod installs; SQLite; live boxes + confidence in dev.
- `assets/models/`: YOLOE products (14 classes), SKU-110K (1 class), YOLO11n COCO, MobileNet-V3 small/large.
- Flavors: **GinLo Dev** (`in.ginlo.ginlo.dev`) and **GinLo** (prod) install side by side; `lib/config.dart` → `isDev`.
- `lib/data/db.dart`: tables products, embeddings, sales, settings.
- `lib/ml/detector.dart`: YUV→RGB, upright, letterbox 640, TFLite, decode, NMS — in a background isolate.
- `lib/screens/live_detect_view.dart`: live boxes, class + confidence, model picker, threshold, timings.

**How it went:** first run failed with `Input tensor 236 lacks data`. YOLO11n/YOLOE (exported with litert-torch)
stored weights outside the main file; the LiteRT 1.4.0 runtime in `tflite_flutter` can't read that. Fixed by
rewriting them with inline weights (`tools/inline_buffers.py`), outputs identical (max diff 0.0).
Speed on the phone: YOLOE ~600–800 ms/frame (~1.5 fps), COCO ~310 ms.

## 3. Logs tab + camera lifecycle — `3207394`
- `lib/dev/perf_log.dart`, `lib/screens/logs_screen.dart`: average ms per frame per model, split into
  prepare / model / boxes / overhead.
- **Measured:** YOLOE 653 ms/frame, of which 614 ms is the model itself; isolate overhead only 3 ms.

**How it went:** after unlocking the phone the detector stayed on "Loading" — the camera plugin doesn't restart
the stream after the app is backgrounded. Now the camera is released on pause and restarted on resume.

## 4. Embedders, Learn, Catalog on SQLite, Bill recognition, dev Lab — `4ba7cf4`
- `lib/ml/`: `frame.dart` (camera frame + upright pixels), `embedder.dart` (crop → 224, values 0..1 per the
  model's metadata, L2-normalise), `vision.dart` (detect, then fingerprint chosen boxes, one isolate, all model
  runs queued), `matcher.dart` (nearest taught angle, threshold 0.6), `models.dart` (load each model once).
- `lib/widgets/camera_feed.dart`, `tag_painter.dart`: one camera widget + box painter for every screen.
- Catalog: products from SQLite, add product, product page with **angle gallery and per-angle 🗑**.
- Learn tab: pick/add product, biggest box = "this one", Capture, drop bad captures with ✕, Save.
- Bill (opens first): boxes → fingerprint → product name or Unknown, live count and total.
- Dev Lab: Detect / Embed (top matches, pin-and-compare, small vs large) / Logs.

**How it went:** works end to end; MobileNet-small embeds a crop in ~21 ms on the phone.

## 5. Orientation saga — `3bb618e` … `02f9d9c`
**Goal:** use the phone in any orientation, like a normal camera.
- Attempt 1 (`3bb618e`): turn frames by sensor − phone orientation (ML Kit formula). Landscape boxes moved
  opposite to objects (180° off).
- Attempt 2 (`84d6e0d`): swapped the landscape directions, own preview sizing, floating control box in landscape.
  Also **Learn saves each capture in 4 rotations** (0/90/180/270) so products lying sideways still match.
- Attempt 3 (`5bf0597`): ask Android for the real screen angle (`MainActivity.kt` method channel). Correct when
  held still, but a straight landscape→landscape flip kept the old angle.
- `a7a99c1`: on request, went back to a plain portrait camera.
- Final (`02f9d9c`): landscape restored and fixed properly:
  - the camera picture is drawn by us (`Texture` + `RotatedBox`) and turned by the **same screen angle the
    detection uses** — the plugin's own preview read the angle mid-rotation and stayed turned the old way;
  - screen angle re-read ~3×/second (a 180° flip changes no size, so Flutter sends no signal);
  - `GlobalKey`s keep the same camera across portrait/landscape layouts — rebuilding it opened a second camera
    session and Android refused ("no supported surface combination").

**How it went:** verified on the phone in portrait, both landscapes and a direct flip: upright, unstretched,
boxes on the objects. Lesson: one source of truth for rotation, used by both the picture and the frames.
