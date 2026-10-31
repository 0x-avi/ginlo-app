# GinLo: Point. Bill. Grow.

Offline AI billing and growth insights for India’s kirana stores, on the phone the shopkeeper already owns.
Paytm Build for India AI Hackathon · Track 1: Merchant Growth AI · Team Velox

## Demo video

**[Watch the demo (30 s)](https://github.com/0x-avi/ginlo-app/releases/download/v1.0-demo/GinLo_demo.mp4)**

## Try it

Download the Android APK (arm64, Android 8+) from
[Releases › v1.0-demo](https://github.com/0x-avi/ginlo-app/releases/tag/v1.0-demo). It runs fully offline; no account needed.

1. **Learn:** tap New product, name it (OCR can fill name and price from the label), capture 6 angles, Save.
2. **Bill:** point the camera at the items, tap Add to bill, then show the UPI QR and mark it paid.
3. **Modify:** type or say a change, e.g. “Maggi ke teen packet bache hain”; confirm with “haan”.
4. **Home:** sales trends, top item, payment split and recent invoices (Products ⋮ › Add demo sales fills a month).

## What it does

- **Point-and-bill:** the camera recognises and counts items against the shop’s own catalog; no barcode scanner.
- **Learns any product:** 6 photos per item, with augmented variants; OCR autofills name and price.
- **Trends that grow sales:** sales vs the last period, top sellers and stock left show what is worth buying.
- **Easy ledger:** every sale, UPI or cash, is logged with a shareable PDF invoice.
- **Speak to modify:** Hindi, Hinglish and English stock and price edits, always confirmed first.
- **100% offline, ₹0 extra cost:** all AI runs on the phone; no cloud, no subscription, no extra hardware.

## Tech

Flutter, Dart, SQLite, TensorFlow Lite (YOLOE detector, MobileNet-V3 embeddings), Google ML Kit OCR,
on-device speech recognition, UPI QR (qr_flutter), pdf, fl_chart. Built with Claude Code.

See [ARCHITECTURE.md](ARCHITECTURE.md), [FLOWS.md](FLOWS.md) and [DEVLOG.md](DEVLOG.md) for how it works.
