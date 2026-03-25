# Murmur

A macOS menu bar utility that reads text aloud. Local by default with system voices, optionally cloud-powered via OpenAI TTS for higher quality.

Copy text or select it in any app, press **⌘⇧L**, and hear it read aloud.

## Features

- **Menu bar-only** — no dock icon, no main window, just an icon and a dropdown panel
- **Universal text extraction** — reads selected text from any app via the Accessibility API, with browser-specific smart extraction for Safari and Chrome
- **System TTS** — AVSpeechSynthesizer works instantly with zero setup, no downloads, no network calls
- **OpenAI TTS** (optional) — high-quality cloud voices using your own API key
- **Global hotkey** — ⌘⇧L to toggle reading (customizable via settings)
- **Privacy-first** — system voice path is fully on-device with no network calls

## Requirements

- macOS 15 Sonoma or later
- Apple Silicon (M1+)
- Xcode 26+ with Swift 6.2

## Building

Murmur uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate its Xcode project from `project.yml`.

```bash
# Install XcodeGen (if needed)
brew install xcodegen

# Generate the Xcode project
xcodegen generate

# Build
xcodebuild -project Murmur.xcodeproj -scheme Murmur -configuration Debug build
```

## OpenAI TTS Setup

To use OpenAI's high-quality voices:

1. Open Murmur settings (click the menu bar icon → Settings)
2. Switch the voice engine to **OpenAI**
3. Enter your OpenAI API key
4. Choose a voice (default: Nova)

An API key is only required for OpenAI voices. System voices work without any configuration.

## Tech Stack

- **Swift 6.2** with strict concurrency
- **SwiftUI + AppKit** hybrid for menu bar integration
- **AXorcist** for Accessibility API text extraction
- **SwiftReadability** for browser content extraction
- **KeyboardShortcuts** for global hotkey registration
- **Defaults** for type-safe UserDefaults
- **LaunchAtLogin-Modern** for launch at login

## License

MIT License — see [LICENSE](LICENSE) for details.
