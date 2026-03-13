# Murmur

A zero-cloud macOS menu bar utility that reads text aloud using local TTS. No accounts, no API keys, no data leaves your machine.

Copy text or select it in any app, press **⌘⇧L**, and hear it read aloud.

## Features

- **Menu bar-only** — no dock icon, no main window, just an icon and a dropdown panel
- **Universal text extraction** — reads selected text from any app via the Accessibility API, with browser-specific smart extraction for Safari and Chrome
- **Local neural TTS** — Soprano 80M, Marvis TTS, and Qwen3-TTS via [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) on Apple Silicon
- **System voice fallback** — AVSpeechSynthesizer works instantly with zero setup
- **Global hotkey** — ⌘⇧L to toggle reading (customizable via settings)
- **Privacy-first** — everything runs on-device, no network calls required

## Requirements

- macOS 15 Sonoma or later
- Apple Silicon (M1+)
- Xcode 26+ with Swift 6.2

## Building

Murmur uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate its Xcode project from `project.yml`.

```bash
# Install XcodeGen (if needed)
brew install xcodegen

# Download the Metal toolchain (required for mlx-audio-swift)
xcodebuild -downloadComponent MetalToolchain

# Generate the Xcode project
xcodegen generate

# Build
xcodebuild -project Murmur.xcodeproj -scheme Murmur -configuration Debug build
```

## TTS Models

On first launch, Murmur uses system voices (zero download). You can download local neural voices from settings:

| Model | Size | Languages | Voices |
|-------|------|-----------|--------|
| Soprano 80M | ~160 MB | English | 1 |
| Marvis TTS | ~250 MB | EN, FR, DE | 4 |
| Qwen3-TTS | ~500 MB | 10 languages | Auto-detect |

Models are stored in the HuggingFace cache (`~/.cache/huggingface/hub/`) and unloaded after 5 minutes of idle to free RAM.

## Tech Stack

- **Swift 6.2** with strict concurrency
- **SwiftUI + AppKit** hybrid for menu bar integration
- **mlx-audio-swift** for on-device neural TTS
- **AXorcist** for Accessibility API text extraction
- **KeyboardShortcuts** for global hotkey registration
- **Defaults** for type-safe UserDefaults
- **LaunchAtLogin-Modern** for launch at login

## License

All rights reserved.
