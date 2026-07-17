<div align="center">

<img src="apps/web/public/icons/icon-180.png" alt="PrivyMark" width="88" height="88" />

# PrivyMark

**English** · [简体中文](README.zh-CN.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/iOS-17.6%2B-black.svg)](https://www.apple.com/ios/)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/chen2he)

**Find private details before you share.**

</div>

> A screenshot holds more than you think — a phone number, a card, an address,
> a face in the background. PrivyMark finds them and covers them in one tap,
> **entirely on your iPhone**. Nothing is ever uploaded.

PrivyMark scans a photo on-device for the private details you might accidentally
share, presents each match as a suggestion you can review, and lets you cover
them before you post, message, or send.

<p align="center">
  <a href="https://privymark.o-c.do">privymark.o-c.do</a>
</p>

## Private by architecture, not by promise

- **Photos never leave your device.** Scanning, covering and exporting all run
  locally. Turn on Airplane Mode and everything still works.
- **Nothing is collected.** No accounts, no analytics, no ad or tracking SDKs,
  no crash logs with your content. There is no server — there isn't one to leak.
- **Nothing is kept.** No history, no copies. Images handed over from the share
  sheet are deleted the moment they're read.

## What it does

- **Scans what matters** — faces, QR / barcodes, emails, phone numbers, URLs,
  street addresses, card-style numbers, ID / passport numbers (including
  Mainland China 身份证), order / tracking numbers, and names. Every match is a
  reviewable suggestion; low-confidence ones are labeled "Maybe".
- **Covers, your way** — solid block (irreversible, the default for text),
  pixelate, blur, Hide Text (blends a region into its background), freehand
  Marker, and a fun emoji cover for faces.
- **Fixes what the scan missed** — long-press a line to "explode" it into word
  chips and cover just the words that matter, or draw a box anywhere.
- **Cleans up metadata** — view what's inside the file (GPS, device, timestamps),
  strip GPS by default, and optionally scrub simple pixel-level hidden marks.
- **Works from the share sheet** — send a photo to PrivyMark from any app, cover
  it, and share back out.

### Honest about the limits

Detection is a smart assistant, not a guarantee — always review before sharing.
Pixelation and blur on text can sometimes be reversed (which is why text
defaults to a solid block), and the hidden-mark scrub cannot remove robust
forensic watermarking. See the in-app notes and the [landing page](https://privymark.o-c.do).

## How detection works

100% on-device, with graceful degradation across OS versions:

1. **Vision** — face rectangles, QR / barcode payloads, and OCR text recognition.
2. **Rule matcher** (`TextRuleMatcher`) — keyword- and regex-anchored matching
   over the OCR text for phones, cards (Luhn-checked), IDs, addresses, names,
   order numbers, etc. Pure Foundation, unit-testable.
3. **On iOS 26+** — Vision's `RecognizeDocumentsRequest` owns phone / email / URL
   / postal-address / tracking detection with native boxes, and (on
   Apple-Intelligence hardware) an **on-device** Foundation Models semantic pass
   classifies names / IDs / sensitive spans the rules miss. The on-device model
   only — never the server / Private Cloud Compute path.

Every stage tolerates the next one being unavailable, so a detector failure
never blocks the editor.

## Project structure

```
apps/
├── iOS/          # The app — SwiftUI, Vision, Core Image, share + photo-editing
│   │             #   extensions, App Group handoff. iOS 17.6+.
│   └── PrivyMark/
├── DAMA/         # HarmonyOS app (打码) — ArkTS/ArkUI, Core Vision Kit
│                 #   (OCR + face) + Scan Kit, offscreen-canvas renderer.
│                 #   HarmonyOS 6.0+ (API 20).
└── web/          # Landing page — Next.js + next-intl, deployed to
                  #   Cloudflare Workers via OpenNext (privymark.o-c.do).
```

## Build

**iOS** — open `apps/iOS/PrivyMark.xcodeproj` in Xcode (26+) and run. The app
icon uses Icon Composer (`PrivyMark/app.icon`); deployment target is iOS 17.6.

**HarmonyOS** — open `apps/DAMA` in DevEco Studio (6.x) and run, or build from
the CLI with hvigor (`assembleHap`). On-device AI (OCR / face detection) needs a
real device or an emulator image that ships the AI models.

**Web** —

```bash
cd apps/web
pnpm install
pnpm dev        # local dev
pnpm build      # static build
pnpm deploy     # OpenNext → Cloudflare Workers
```

## Related

PrivyMark keeps things on your device. Two sibling projects put you in charge of
your own infrastructure:

- **[Orange Cloud](https://o-c.do)** — your Cloudflare, at a glance. A native
  client for iPhone, iPad & Android.
- **[Yield](https://yield.o-c.do)** — a self-hosted App Store order console, fed
  entirely by Apple's server notifications.

## License

[MIT](LICENSE) © 2026 JIAMIN CHEN
