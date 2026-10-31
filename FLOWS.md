# GinLo — the flows, step by step through the code

Each flow follows one thing the user does, line by line through the files. Open the links side by side.
(Line numbers are from commit `a21ddec`; they drift a little as code changes.)

## 0. Five Flutter ideas you need first

| Idea | In one line | Where you'll see it |
|---|---|---|
| **Widget + `build()`** | A widget is a description of UI; Flutter calls `build()` to draw it. | every screen |
| **`State` + `setState()`** | A `StatefulWidget` keeps data in its `State`; calling `setState(() {...})` changes it and makes Flutter call `build()` again. | `_LiveBillState`, `_LearnViewState` |
| **`Future` + `async`/`await`** | A Future is "a value that arrives later" (a database read, a model run). `await` pauses that function until it arrives without freezing the app. | everything touching the DB or models |
| **Isolate** | A second Dart thread with its own memory. Heavy pixel/model work runs there so the UI stays smooth; data is copied in and results copied back. | `vision.dart` |
| **Listeners** (`ValueNotifier` / `ChangeNotifier`) | An object that says "I changed"; widgets wrapped in `ValueListenableBuilder` / `ListenableBuilder` rebuild when it does. | `AppDb.changes`, `BillDraft`, `PerfLog` |

---

## 1. App start and tabs
1. [`main()`](lib/main.dart#L11) runs `runApp(GinLoApp())`. `GinLoApp` sets the theme (`ginloTheme()` in
   [ui/theme.dart](lib/ui/theme.dart)) and shows `AppShell`.
2. [`_AppShellState`](lib/main.dart#L53) keeps one number: `_tab` (0 = Bill). Tapping a tab calls `setState` →
   `build()` runs again with the new tab.
3. The tabs live in an [`IndexedStack`](lib/main.dart#L69): all screens exist at once, only one is shown, so a
   half-built bill survives a look at Home. Camera screens get [`active: _tab == 0`](lib/main.dart#L73) — when
   `false` they show an empty box, which disposes the camera.

## 2. Live billing: a camera frame becomes named boxes (the core)
Follow one frame from the lens to the screen.

**a. The camera hands us a frame** — [widgets/camera_feed.dart](lib/widgets/camera_feed.dart)
1. [`_start()`](lib/widgets/camera_feed.dart#L42) opens the back camera and
   [`startImageStream`](lib/widgets/camera_feed.dart#L56): ~30 times a second it calls `_onImage` with a raw frame
   and the rotation needed to make it upright (sensor angle − screen angle).
2. [`_onImage()`](lib/widgets/camera_feed.dart#L93): [`if (_busy) return`](lib/widgets/camera_feed.dart#L99) — if the
   previous frame is still being processed, this one is dropped. That's why a slow model gives fewer updates per
   second instead of a growing backlog. Otherwise it wraps the frame in a `FrameData` and calls the screen's
   `onFrame`.
3. `FrameData` ([ml/frame.dart](lib/ml/frame.dart)) copies the camera's YUV planes. Its
   [`rgb(x, y)`](lib/ml/frame.dart#L11) answers "what colour is pixel (x, y) *as the user sees it*", turning the
   coordinates by the rotation and converting YUV → RGB [on the fly](lib/ml/frame.dart#L63).

**b. The Bill screen asks for analysis** — [screens/bill_screen.dart](lib/screens/bill_screen.dart)
4. [`_onFrame()`](lib/screens/bill_screen.dart#L117) gets the loaded models (`Models.detector/embedder` load each
   once, [models.dart](lib/ml/models.dart#L10)) and calls
   [`Vision.analyze(... pick: EmbedPick.all)`](lib/screens/bill_screen.dart#L120) — "find boxes, fingerprint all of them".

**c. In a background isolate: detect, then fingerprint** — [ml/vision.dart](lib/ml/vision.dart)
5. [`analyze()`](lib/ml/vision.dart#L60) packs everything into a `_Job` and [`_queue`](lib/ml/vision.dart#L110)s it:
   jobs run one after another, so two screens never use a model at once.
   [`Isolate.run(() => _run(job))`](lib/ml/vision.dart#L117) runs the work on another thread.
6. [`_run()`](lib/ml/vision.dart#L161):
   - [re-attaches the model](lib/ml/vision.dart#L164) by its memory address (models can't be copied between isolates);
   - [`prepareDetectorInput`](lib/ml/vision.dart#L167) → [detector.dart](lib/ml/detector.dart#L94): shrinks the upright
     frame into 640×640 keeping its shape, grey padding around (the "letterbox"), pixel values 0..1;
   - [`det.invoke()`](lib/ml/vision.dart#L171) runs YOLO;
   - [`decodeDetections`](lib/ml/detector.dart#L124): the model outputs 8,400 candidate boxes, each with a score per
     class; keep those [above the confidence](lib/ml/detector.dart#L144), convert coordinates back to 0..1 of the
     frame, then [`_nms`](lib/ml/detector.dart#L158) removes overlapping duplicates of the same object;
   - [for each picked box](lib/ml/vision.dart#L195), [`_embed`](lib/ml/vision.dart#L130):
     [`prepareEmbedderInput`](lib/ml/embedder.dart#L99) crops the box and stretches it to 224×224, MobileNet turns it
     into 1,024 numbers, [`l2normalize`](lib/ml/embedder.dart#L144) scales them to length 1 (the "fingerprint").
   - Returns a `VisionResult`: boxes + one fingerprint per box + timings.

**d. Name each box** — [ml/matcher.dart](lib/ml/matcher.dart)
7. Back in Bill, [`_matcher.match(v)`](lib/screens/bill_screen.dart#L125) for every fingerprint.
   [`match()`](lib/ml/matcher.dart#L38) compares it with every taught fingerprint using [`dot()`](lib/ml/embedder.dart#L153)
   (for length-1 vectors, the dot product *is* the cosine similarity: 1 = identical look, 0 = unrelated). The best
   one wins — [unless it's below 0.6](lib/ml/matcher.dart#L48), then it's "Unknown".
   The taught fingerprints come from the database in [`_loadCatalog()`](lib/screens/bill_screen.dart#L83).

**e. Steady it, draw it**
8. [`_smoother.update()`](lib/screens/bill_screen.dart#L126) and [`_countSmoother.update()`](lib/screens/bill_screen.dart#L135)
   (flow 3), all inside `setState`, so `build()` runs.
9. `build()` turns results into [`items`](lib/screens/bill_screen.dart#L292) (steady ones in prod, raw ones in dev),
   then `BoxTag`s that `TagPainter` draws over the preview, and the "In view" list + total.

## 3. Smoothing: why boxes don't flicker in the shop app — [ml/smoother.dart](lib/ml/smoother.dart)
[`FrameSmoother.update()`](lib/ml/smoother.dart#L101) remembers each item as a "track":
1. [Link](lib/ml/smoother.dart#L103) each new box to the existing track it overlaps most (same item, next frame).
2. Linked: the box [glides](lib/ml/smoother.dart#L118) halfway to the new position (`Rect.lerp`), its name joins a
   short history, its "seen" count goes up.
3. Not linked: the track's "missed" count goes up; [after too many misses](lib/ml/smoother.dart#L130) it's dropped.
   Unlinked new boxes start new tracks.
4. Shown: only tracks seen often enough, biggest first, [skipping boxes that mostly overlap a bigger one](lib/ml/smoother.dart#L141)
   (duplicates). Name = the most common in its history.

[`CountSmoother`](lib/ml/smoother.dart#L186) then holds each product's count at its most common value over the last
few frames. All the numbers are `SmoothSettings`, tunable in dev and saved in the database.

## 4. A bill, from photo to paid
1. **Add to bill** → [`_addToBill()`](lib/screens/bill_screen.dart#L267): takes the steady counts, makes `BillLine`s,
   [`BillDraft.addAll()`](lib/data/bill_draft.dart#L18) (same product again → quantity goes up), then
   `Navigator.push(InvoiceScreen)` — a new screen on top of the stack.
2. `BillDraft` is a `ChangeNotifier` that lives for the whole app ([bill_draft.dart](lib/data/bill_draft.dart)), so
   the bill survives leaving the screen. Every change calls `notifyListeners()`; the invoice and the bill bar under
   the camera are `ListenableBuilder`s, so they redraw.
3. [InvoiceScreen](lib/screens/invoice_screen.dart): − / + call [`changeQty`](lib/data/bill_draft.dart#L31).
   - **Add more photos** = [`Navigator.pop`](lib/screens/invoice_screen.dart#L71): back to the camera, draft kept.
   - **Done** = [push `PaymentScreen`](lib/screens/invoice_screen.dart#L81).
4. [PaymentScreen](lib/screens/payment_screen.dart) loads the shop name + UPI ID, builds the link with
   [`upiUri()`](lib/data/upi.dart#L4) → `upi://pay?pa=you@bank&pn=Shop&am=128.00&cu=INR&tn=...`, and
   [`QrImageView`](lib/screens/payment_screen.dart#L72) draws it. A UPI app scanning it opens a payment to you with
   the amount filled in.
5. **Paid** → [`_paid()`](lib/screens/payment_screen.dart#L34) → [`recordSale()`](lib/data/db.dart#L249): one
   database *transaction* (all or nothing) saves the sale and
   [lowers each product's stock](lib/data/db.dart#L258). Then the draft is cleared and `popUntil` goes back to the camera.

## 5. Teaching a product — [screens/learn_screen.dart](lib/screens/learn_screen.dart)
1. Live: [`_onFrame()`](lib/screens/learn_screen.dart#L74) runs detection only (fast) and remembers the last result
   *and* its frame; `build()` draws the biggest box green ("this one").
2. **Capture** → [`_capture()`](lib/screens/learn_screen.dart#L88) →
   [`Vision.embedVariants()`](lib/screens/learn_screen.dart#L96) ([vision.dart](lib/ml/vision.dart#L85)): in the
   background, fingerprint that box in all [8 teach variants](lib/ml/embedder.dart#L84) (as seen, turned, darker,
   brighter, further, closer) and [save its picture](lib/ml/embedder.dart#L126). Added to the strip at the bottom.
3. **Save** → [`_save()`](lib/screens/learn_screen.dart#L104) → [`addCapture()`](lib/data/db.dart#L140) for each
   capture: 8 rows sharing one `capture` id, picture stored once.
4. Every database write bumps [`AppDb.changes`](lib/data/db.dart#L45); Bill listens to it and reloads the
   fingerprints, so the product is recognised immediately.

## 6. Products (catalog) — [screens/catalog_screen.dart](lib/screens/catalog_screen.dart)
1. The list is a `FutureBuilder` (show a spinner until the database answers) inside a `ValueListenableBuilder` on
   `AppDb.changes` (reload after any write): products, angles per product, which need re-teaching.
2. [`ProductScreen`](lib/screens/catalog_screen.dart#L111): the angle gallery; 🗑 →
   [`deleteAngle()`](lib/data/db.dart#L204) removes every fingerprint of that capture.
3. **Upgrade old angles** → [`_upgrade()`](lib/screens/catalog_screen.dart#L230): re-fingerprints stored pictures in
   the missing variants and *adds* them (never replaces the original).

## 7. Home dashboard — [screens/home_screen.dart](lib/screens/home_screen.dart)
1. [`_load()`](lib/screens/home_screen.dart#L28): [`periodRange()`](lib/data/sales.dart#L49) gives this period and
   the previous one; [`db.sales()`](lib/data/db.dart#L267) fetches both;
   [`SalesStats.compute()`](lib/data/sales.dart#L92) (plain Dart, unit-tested) works out total, % change, chart
   buckets, top item, breakdowns, recent sales.
2. Wrapped in a listener on [`AppDb.changes`](lib/screens/home_screen.dart#L103): marking a bill paid updates Home.
3. The period chip opens [`_pickPeriod()`](lib/screens/home_screen.dart#L38) (bottom sheet) → `setState(_period)` →
   reload. Each card is a small widget below (`_StoreCard`, `_TotalSalesCard` with fl_chart bars/line, ...).

## 8. Rotation (why the picture and boxes always agree)
1. [`_readScreenRotation()`](lib/widgets/camera_feed.dart#L72) asks Android (via
   [MainActivity.kt](android/app/src/main/kotlin/in/ginlo/ginlo/MainActivity.kt)) how far the screen is turned; it's
   re-read ~3×/second because a 180° flip changes nothing Flutter can see.
2. That one angle turns **the frames** (`sensor − screen`, used by `FrameData.rgb`) and **the picture**
   ([`RotatedBox`](lib/widgets/camera_feed.dart#L181) around the raw camera texture). Same angle → boxes land on objects.
3. [`didChangeAppLifecycleState`](lib/widgets/camera_feed.dart#L114): release the camera when the app goes to the
   background, reopen it when it returns (the plugin doesn't).

## 9. The database — [data/db.dart](lib/data/db.dart)
Four tables: `products`, `embeddings` (one row per fingerprint: product, model, vector, capture id, variant, picture
on the first row), `sales`, `settings`. [`onUpgrade`](lib/data/db.dart#L74) adds columns to databases from older app
versions, so updating the app never loses data.
