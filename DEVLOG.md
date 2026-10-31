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

## 6. Dev log, prod smoothing, augmented teaching — this commit
**Goal:** steady results in the shop app; a running log of changes; 6–8 captures per product with automatic
variants so recognition survives dim light, glare, distance and products lying sideways.
- `DEVLOG.md` (this file) + `CLAUDE.md` (rule: update this log every iteration).
- `lib/ml/smoother.dart` + `test/smoother_test.dart` (6 tests): each item gets a short memory across frames —
  shown only after 2 frames (one-frame ghost boxes never appear), name = majority vote over the last 4 frames,
  box glides halfway to the new position, survives 2 missed frames, boxes mostly inside a bigger box hidden.
- `lib/screens/bill_screen.dart`: prod always uses the smoothed items (boxes, names, counts, total); dev shows raw
  per-frame output with a **"Prod view (smoothed)"** switch to compare.
- `lib/ml/embedder.dart`: `teachVariants` — as seen, turned 90°/180°/270°, darker (×0.55), brighter (×1.4),
  further away (more margin), closer (tight crop). Brightness `gain` added to the crop preparation.
- `lib/ml/vision.dart`: `Vision.embedVariants()` fingerprints one box in all 8 variants (+ crop picture) in the
  background; the old per-frame "all turns" option is gone.
- `lib/screens/learn_screen.dart`: live view now runs detection only (faster); Capture makes the 8 variants;
  Capture stops at 8, Save needs at least 6. A product = 6–8 captures × 8 variants = 48–64 fingerprints.

**How it went:** analyze clean, 8 tests pass, installed on the phone. Not yet checked on the phone (it was
locked): Capture timing, and prod view vs raw on Bill.

## 7. Tunable smoothing, steady counts, augmenting old angles — this commit
**Goal:** fewer duplicate boxes and jumping item counts in prod, every smoothing knob tunable; give angles taught
before the variants existed the same 8 variants.
- `lib/ml/smoother.dart`: `SmoothSettings` (saved as JSON in the settings table) — show after N frames, keep
  through N misses, name vote frames, **count hold frames**, **merge duplicates** (hide a box overlapping a
  bigger one by ≥ X of the smaller box; before, only boxes ~fully inside were hidden), link overlap, glide.
  New `CountSmoother`: each product's listed count = its most common count over the last N frames.
- `lib/screens/bill_screen.dart`: dev **Smoothing settings** sheet with a slider per knob (live, saved on close,
  reset to defaults); prod item list uses the held counts.
- `lib/ml/frame.dart` / `embedder.dart`: `Pixels` interface so the embedder reads live frames *or* stored crop
  pictures (`ImagePixels`); area outside the picture repeats edge pixels (lets "further away" work on a stored crop).
- `lib/ml/vision.dart`: `embedStoredVariants()` fingerprints stored crop JPEGs in all 8 variants.
- `lib/data/db.dart`: `anglesNeedingVariants()`, `replaceAngleVectors()`.
- `lib/screens/catalog_screen.dart`: **Upgrade N old angles** button (only shown when needed).
- `test/smoother_test.dart`: 11 tests (merging, live settings, save/load, held counts).

**How it went:** on the phone the button showed "Upgrade 18 old angles" (3 products × 6) and finished in ~5 s:
every angle now has 8 fingerprints. Smoothing sliders not yet tuned on the phone — defaults: show after 2,
keep 2, vote 4, count hold 5, merge 0.6, link 0.3, glide 0.5. Note: for old angles "further away" is synthetic
(edge pixels repeated), since the stored crop has no real surroundings.

## 8. Shop app: Ginlo design, billing flow with UPI QR, Home dashboard — `e8161d4` … `02f1216`
**Goal:** the complete prod flow in the Ginlo look: photo → bill → more photos or Done → customer scans our QR
with the amount → paid; plus the earnings dashboard from the mock-ups.
- `lib/ui/theme.dart`: colours measured from the logo (blue `#0035F5`, coin yellow `#FECE28`), lavender page,
  white 20 px cards (`GinloCard`), logo header (`GinloHeader`). `assets/brand/ginlo_logo.png`: logo, background
  made transparent. `lib/ui/format.dart`: `inr()` with Indian grouping (₹12,48,000.00), `pct()`, `clock()`.
- `lib/data/sales.dart`: `BillLine`, `Sale`, `Period`, `SalesStats.compute()` (total, % vs previous period, bills,
  average bill, chart buckets, top item, units per item, money per payment method, recent).
- `lib/data/db.dart` v2: `sales.payment` (migration for existing installs), `recordSale()` (also lowers stock),
  `sales()`, `shop()` / `setShop()`, `productPhoto()`.
- `lib/data/bill_draft.dart`: the bill being built, app-wide (survives "Add more photos").
- `lib/data/upi.dart`: `upiUri()` → `upi://pay?pa=…&pn=…&am=…&cu=INR&tn=…`; any UPI app opens with the amount filled.
- Screens: Bill gets **Add to bill** (freezes the steady items in view) + a bill bar; `invoice_screen.dart`
  (− / +, total, **Add more photos** / **Done**); `payment_screen.dart` (big QR + amount, **Paid via UPI** /
  **Paid in cash** → saved, back to the camera); `shop_dialog.dart` (store name + UPI ID);
  `home_screen.dart` (store card, Total Sales + Select Period sheet + chart, Top Performing Item with the
  product's own photo, Sales Breakdown donut, Recent Sales). Catalog tab renamed **Products**.
- Tests: `sales_test.dart`, `upi_test.dart`, `format_test.dart` — 21 tests total.

**How it went:** analyze clean, all tests pass, dev + prod APKs build. **Not yet checked on the phone** — it dropped
off wireless debugging while this was built. To check: set the UPI ID (Home → Edit), Add to bill → Done → scan
the QR with another phone (₹1 test), Paid → Home updates.

## 9. Fix the angle-upgrade regression; resizable portrait panel — `5a13441` + this commit
**What broke:** after "Upgrade 18 old angles" recognition dropped (power bank 0.84 → 0.60). The upgrade *replaced*
each angle's original fingerprint (made from the full camera frame) with ones re-made from the stored crop
picture — and that picture was capped at 224 px on its **long** side, so a tall can was kept ~90 px wide.
Measured on the laptop: similarity of the re-made fingerprint to the original was 0.96–0.98 for square crops but
**0.77–0.90 for long ones** (cans, power bank).
- `db.dart` v3: `embeddings.capture` groups one Capture's 8 fingerprints, `variant` names each, the crop picture
  is stored once per capture (was copied onto all 8 rows). Old rows migrate as `legacy`.
- `addCapture()` replaces `addAngle()`; the upgrade now only **adds** variants (`addVariants`) and never deletes
  the original. Products shows "re-teach for better recognition" for products with only legacy angles.
- `cropJpeg()`: short side kept at 224 px (long side ≤ 448), JPEG quality 92.
- `camera_layout.dart`: portrait controls are a **resizable panel** (drag handle; starts at 24 % of the screen,
  10–70 %, remembered) that scrolls; Bill puts **Add to bill** and the bill bar at the top of it.

**How it went:** installed both apps; portrait preview is now much taller, Add to bill always visible.
**To do on the phone:** re-teach the 3 products (6 captures each) — their original fingerprints were deleted by the
old upgrade and can't be recovered.

---

## 10. Demo build: OCR autofill in Learn, clearer buttons, Bill inside the tab bar — this commit
- `voice/ocr.dart` (new, ML Kit text recognition, on-device): `readLabel(jpeg)` reads the product's label;
  `guessLabel()` takes the price after MRP/₹/Rs/INR and the name from the tallest wordy line.
- `vision.embedVariants` also returns `ocr`: a full-resolution crop (up to 2000 px) so small print is readable.
- Learn: after a capture, a chip "Read: name · ₹price — Use" prefills the New product dialog
  (`showProductDialog(context, name:, price:)`). Nothing is filled in when the label can't be read.
- Learn: Capture / Save stay in full colour; tapping one too early shows a hint instead of grey disabled text.
- Tab bar: the round Bill button now sits inside the bar (was a docked FAB that overlapped Modify and the tabs).
- `proguard-rules.pro`: `-dontwarn com.google.mlkit.vision.text.**` (R8 failed on the unused non-Latin scripts).

**How it went:** prod release 75 MB (arm64), installed; the tab bar shows no overlap. Evals deferred until after the demo.

---

## 11. Steadier prod smoothing; demo sales and invoices on Home — this commit
**Problem:** in prod, items still flickered: a box missed for 2 frames vanished and then needed 2 frames to
come back, and a fast-moving box lost its track (too little overlap) and restarted.
- `smoother.dart` defaults: keep through **6** missed frames (was 2), show after 3, name vote over 8 frames,
  count hold 10, glide 0.35, link overlap 0.2.
- A box with little overlap but a nearby centre and a similar size still links to its track (fast hand movement).
- An Unknown frame counts half in the name vote.
- Bill saves the settings under `smoothing_v2`, so values saved with the old jumpy defaults are ignored.
  The dev slider for "keep through misses" now goes to 12.
- Home: with no sales, an **Add demo sales (30 days)** button makes made-up bills from the products you've
  taught (also in Products ⋮). Tapping a recent sale opens its **invoice** (share as PDF), now with a back arrow.

---

## 12. No splash, GinLo app icon — this commit
- Splash: `launch_background.xml` is just the app background colour (#EEF2FB). Android 12+ always shows a
  system splash, so `values-v31` / `values-night-v31` make it that colour with **no icon**, which is effectively invisible.
- Icon: the GinLo wordmark on white. `mipmap-anydpi-v26/ic_launcher.xml` is an adaptive icon (white background
  + `drawable-nodpi/ic_launcher_foreground.png`, logo inside the safe zone), so the phone's icon shape doesn't crop it;
  `mipmap-*/ic_launcher.png` (48–192 px) are for older phones. Made from `assets/brand/ginlo_logo.png` with `sips`.

---

## 13. Capture button white on blue — this commit
- Learn: Capture was a "tonal" button (dark text on pale blue); now solid blue with white text, also while capturing.
- Published: public repo github.com/0x-avi/ginlo-app, APK as release `v1.0-demo`.

---

## 14. Landscape rail matches the portrait bar — this commit
- `main.dart`: the landscape rail was a stock NavigationRail (Bill a grey pill). Now both layouts build the same
  items (`tab()`, round blue `bill`) via `slot()`: shares of the bar in portrait, 76 px slots in a white rail in landscape.
- Bill: "Add to bill" is solid blue with white text (was pale).

---

## Backlog (planned, not built)
- **Smoothing benchmark** (requested 31 Oct, after entry 7; extended after entry 9): the user builds a test set of
  scenes with known item counts; record ~5 s of raw per-frame results per scene (about how long a vendor waits
  before tapping Capture) once, then replay offline (instant, no model runs) through every candidate and setting:
  1. **FrameSmoother** (current): link boxes to last frame's position by overlap, name vote, merge, held counts.
  2. **ByteTrack-style two-stage matching**: strong boxes (≥ ~0.25) can start items; weak boxes (0.1–0.25,
     not fingerprinted) can only keep existing items alive — targets blinking items / jumping counts.
  3. **2 + Kalman filter**: predict each item's next position from its velocity before linking — should only
     matter when items or the camera move steadily (sliding items, panning); measure it rather than assume.
  Score: share of frames showing exactly the right items and counts, time to reach the right count, false items.
  Pick the winner per use case (spread, crowded, stacked, dim, moving) and make it the prod default.
- **Teach from a 5-second video** (requested 31 Oct, after entry 9): instead of tapping Capture 6 times, record ~5 s
  while turning the product; the app picks the frames itself. Plan:
  1. While recording, take the biggest box each frame (as Learn does now), skip blurry frames (sharpness check).
  2. **Skip near-duplicates cheaply** with a tiny "thumbnail fingerprint" (crop downscaled to e.g. 16×16 grey,
     compared by difference) — before running the embedder — so similar views aren't saved twice.
  3. Also compare each candidate with the product's **already saved** angles (thumbnail first, then embedding);
     keep only views that add something new, up to ~8.
  4. Each kept frame gets the 8 teach variants as today; show the picked frames so bad ones can still be removed.
- **Voice/command benchmark** (added 31 Oct): `eval/voice_eval_200.json` — 200 shopkeeper commands (Hinglish, Hindi in
  Devanagari, English; self-corrections like "paanch... nahi chaar") with the expected tool calls (`set_stock`,
  `add_stock`, `remove_stock`, `set_price`, `get_price`, `get_stock`, `create_product`, `rename_product`,
  `delete_product`, `show_catalog`) or `needs_clarification`. Use it to score the rules parser, FunctionGemma and a
  quantized Qwen3-0.6B (exact tool + arguments, clarification when needed); if none is good enough, fine-tune on it.
  Speech side: check Whisper on Hindi/Hinglish audio; Sarvam API is the online fallback (later — stay offline for now).
- **Later test sets** (31 Oct): (1) accent/voice test data ("omnivoice") for speech-to-text — Whisper vs Android
  recognizer on Indian accents, Hindi and Hinglish; (2) image and video test sets of items for detection,
  recognition and counting (the smoothing benchmark); (3) the offline LLM command test (`eval/voice_eval_200.json`).
  On-device model files already downloaded to `models_ondevice/` (FunctionGemma 270M, Qwen3 0.6B int4, Whisper
  base/small); the flutter_gemma / whisper_ggml packages were removed again for the demo build (not wired yet).
