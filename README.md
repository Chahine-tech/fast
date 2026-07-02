# SwiftSpeed

A tiny, native macOS menu bar app to test your internet speed. Click the icon, get download/upload/ping — no browser tab, no ads.

## Features

- One-click speed test: download, upload, ping (idle vs. under load)
- Live sparkline while the download test runs
- Shows which Cloudflare datacenter and country you tested against
- No Dock icon, lives entirely in the menu bar
- No third-party dependencies, no tracking, no accounts

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26 or later (to build)

## Building

The Xcode project (`SwiftSpeed/SwiftSpeed.xcodeproj`) is generated from `SwiftSpeed/project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you change `project.yml` or add/remove source files, regenerate it:

```bash
brew install xcodegen
cd SwiftSpeed
xcodegen generate
open SwiftSpeed.xcodeproj
```

Then build and run from Xcode (⌘R). The app has no Dock icon — look for the speedometer icon in the menu bar.

## Installing a pre-built copy

If you download a built `SwiftSpeed.app` instead of building it yourself, macOS Gatekeeper will likely block it on first launch since it isn't notarized by Apple (that requires a paid Apple Developer account). To open it anyway:

1. Right-click (or Control-click) `SwiftSpeed.app` and choose **Open**.
2. Click **Open** in the dialog that appears.

Or: **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the SwiftSpeed warning.

## How it works

- **Speed test**: downloads/uploads test data from `speed.cloudflare.com` (4 parallel streams each way, mirroring how real speed test tools saturate a connection) and measures throughput directly.
- **Ping**: round-trip time to Cloudflare's edge, measured once at idle and once while the download is running, to give a rough sense of bufferbloat under load.
- **Server/client info**: parsed from the same Cloudflare trace request used for ping — no extra network calls.

All testing traffic goes to Cloudflare's public speed-test infrastructure (`speed.cloudflare.com`), the same one used by [speed.cloudflare.com](https://speed.cloudflare.com) itself. It's not a formally documented public API, so it can occasionally rate-limit (HTTP 429) if tested very frequently — the app surfaces this clearly instead of showing a bogus result.

## License

[MIT](LICENSE)
