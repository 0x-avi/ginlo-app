# GinLo — how the code is organised

GinLo points the phone at a shop counter, finds every item (**detector**), recognises each one against the shop's
own catalog (**embedder + matcher**), and turns that into a bill. Everything runs on the phone.

## Project structure

```
lib/
  main.dart                 app start, theme, tab shell
  config.dart               isDev: dev app vs prod app
  data/
    db.dart                 SQLite: products, taught angles, sales, settings, shop name + UPI ID
    sales.dart              bill lines, sales, dashboard stats per period (pure Dart)
    bill_draft.dart         the bill being built (survives "Add more photos")
    upi.dart                the upi://pay link inside the payment QR
  ml/                       the "AI" part: no UI in here
    frame.dart              one camera frame + reading its pixels upright
    detector.dart           YOLO: frame -> boxes
    embedder.dart           MobileNet: box crop -> fingerprint vector; teach variants
    vision.dart             runs detector + embedder together in a background isolate
    matcher.dart            fingerprint -> closest taught product (or Unknown)
    smoother.dart           steadies results across frames for the shop app
    models.dart             loads each model once
  ui/
    theme.dart              Ginlo colours, theme, GinloCard, GinloHeader
    format.dart             ₹ with Indian grouping, %, time
  widgets/                  reusable UI pieces
    camera_feed.dart        camera preview + frames, rotation, app lifecycle
    camera_layout.dart      camera + controls, portrait and landscape
    tag_painter.dart        draws boxes with labels
  screens/                  one file per screen
    bill_screen.dart        live billing (opens first): Add to bill
    invoice_screen.dart     the bill: − / +, Add more photos, Done
    payment_screen.dart     QR with the amount for the customer; Paid via UPI / cash
    shop_dialog.dart        edit store name + UPI ID
    catalog_screen.dart     products, angle gallery, upgrade old angles
    learn_screen.dart       teach a product its angles
    home_screen.dart        earnings dashboard (store, total sales + chart, top item, breakdown, recent)
    lab_screen.dart         dev only: detector/embedder test benches
    live_detect_view.dart   dev only: raw detector view (Lab -> Detect)
    logs_screen.dart        dev only: timings per model (Lab -> Logs)
  dev/
    perf_log.dart           dev only: collects timings for the Logs view
assets/models/              .tflite models + class names
android/app/src/main/kotlin/.../MainActivity.kt   tells Dart the screen's rotation
test/                       widget test + smoother tests
tools/inline_buffers.py     fixes newly exported models for the phone's TFLite runtime
```

**How a frame flows:** `CameraFeed` → `FrameData` → `Vision.analyze` (background isolate: `detector.dart` finds boxes,
`embedder.dart` fingerprints them) → `Matcher.match` names each box → `FrameSmoother` steadies it (prod) →
`TagPainter` draws it and the screen lists items and the total.

## Reading order

Read top to bottom; each file only uses things from files above it.

### 1. App basics
1. **`lib/main.dart`**: `main()` locks nothing and starts the app. `GinLoApp` sets the theme. `AppShell` holds the
   tabs in an `IndexedStack` (every tab stays alive; only the visible camera tab gets `active: true`). Portrait =
   bottom `NavigationBar`, landscape = side `NavigationRail`; a `GlobalKey` keeps the same tabs across the switch.
2. **`lib/config.dart`**: `isDev` — true in GinLo Dev (boxes, scores, Lab), false in the shop app.

### 2. Data
3. **`lib/data/db.dart`**: `AppDb.open()` creates the tables once. `Product` is one catalog row.
   Products: `products()`, `upsertProduct()`, `deleteProduct()`. Taught angles: `addAngle()` saves a fingerprint +
   its crop picture, `angles()` loads all fingerprints for the matcher, `productAngles()` one row per picture for the
   gallery, `deleteAngle()` removes a picture and all its fingerprints, `anglesNeedingVariants()` /
   `replaceAngleVectors()` upgrade old angles. `setting()` / `setSetting()` key-value store.
   `AppDb.changes` is bumped after every write so screens reload.

### 3. Camera frames
4. **`lib/ml/frame.dart`**: `Pixels` = anything with pixels (camera frame or stored picture). `FrameData` copies a
   camera frame (YUV planes) so it can go to a background isolate; `rgb(x, y)` returns the colour of a pixel *as the
   user sees it* (turned upright by `rotation`) and converts YUV → RGB on the fly.
5. **`lib/widgets/camera_feed.dart`**: `CameraFeed` starts the back camera, and for each frame calls `onFrame`
   — skipping frames while the previous one is still being processed. `_readScreenRotation()` asks Android how far the
   screen is turned (re-read ~3×/s); frame rotation = sensor angle − screen angle. `build()` draws the raw camera
   texture turned by the same angle, so picture and boxes always agree. `didChangeAppLifecycleState()` releases the
   camera when the app is backgrounded and restarts it on return.
6. **`android/.../MainActivity.kt`**: answers `rotationDegrees` from Dart with Android's display rotation.

### 4. The models
7. **`lib/ml/detector.dart`**: `DetectorSpec` describes a model (input layout, labels); `detectorSpecs` lists the 3.
   `Detector.load()`. `prepareDetectorInput()` letterboxes the upright frame into 640×640 (scaled, grey padding, never
   stretched). `decodeDetections()` reads the model output (8400 candidate boxes), keeps those above the confidence
   threshold, converts back to 0..1 of the frame, and `_nms()` removes overlapping duplicates.
8. **`lib/ml/embedder.dart`**: `Embedder.load()`. `prepareEmbedderInput()` crops a box, resizes to 224×224 (values
   0..1), optionally turned / brightened / zoomed. `teachVariants` = the 8 ways each taught capture is fingerprinted.
   `cropJpeg()` the picture shown in the gallery. `l2normalize()` + `dot()` = cosine similarity.
9. **`lib/ml/models.dart`**: `Models.detector()` / `Models.embedder()` load each model once and reuse it.
10. **`lib/ml/vision.dart`**: the core. `Vision.analyze()` runs in a background isolate: detect → fingerprint the
    picked boxes (`EmbedPick.all` for billing, `largest` for teaching) → `VisionResult`. `embedVariants()` (Capture in
    Learn) and `embedStoredVariants()` (upgrade old angles) make the 8 variants. `_queue()` makes sure two screens
    never use a model at the same time.
11. **`lib/ml/matcher.dart`**: `Matcher.match()` compares a fingerprint with every taught angle; the closest wins if
    its similarity ≥ `Matcher.threshold` (0.6), otherwise Unknown. `ranking()` = top products (dev Embed test).
12. **`lib/ml/smoother.dart`**: `FrameSmoother.update()` links boxes frame to frame ("tracks"); an item is shown after
    N frames, its name is voted over recent frames, boxes glide, duplicates merge. `CountSmoother` holds each
    product's count steady. `SmoothSettings` = all the knobs (saved in the database).

### 5. Screens
13. **`lib/widgets/tag_painter.dart`** + **`camera_layout.dart`**: draw boxes with labels; place camera + controls.
14. **`lib/screens/bill_screen.dart`**: `_onFrame()` = analyze → match → smooth; `build()` draws boxes and the item list
    with total. Dev extras: raw vs prod view, threshold, smoothing settings sheet.
15. **`lib/screens/learn_screen.dart`**: live view (detector only); `_capture()` fingerprints the biggest box in all 8
    variants; `_save()` writes them. 6–8 captures per product.
16. **`lib/screens/catalog_screen.dart`**: product list, `showProductDialog()`, `ProductScreen` (angle gallery with
    🗑), `_UpgradeAnglesButton`.
17. Dev only, skim: `lab_screen.dart`, `live_detect_view.dart`, `logs_screen.dart`, `dev/perf_log.dart`.

### 6. Shop flow (read after Bill)
18a. **`lib/ui/theme.dart`**, **`format.dart`**: colours and reusable card/header; rupee formatting.
18b. **`lib/data/sales.dart`**: `SalesStats.compute()` turns a list of sales into everything Home shows.
18c. **`lib/data/bill_draft.dart`** → **`invoice_screen.dart`** → **`upi.dart`** → **`payment_screen.dart`**: follow
     one bill from "Add to bill" (in `bill_screen.dart`) to "Paid" (`AppDb.recordSale`).
18d. **`lib/screens/home_screen.dart`**: `_load()` reads the period's sales and the previous period's, then each card.

### 7. Tests and tools
18. **`test/smoother_test.dart`**: readable examples of what the smoother guarantees.
19. **`tools/inline_buffers.py`**: why newly exported models need rewriting before the phone can run them.
