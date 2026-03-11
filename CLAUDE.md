# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Generate Xcode project from project.yml (run after changing project.yml)
xcodegen generate

# Build
xcodebuild -project Murmur.xcodeproj -scheme Murmur -configuration Debug build

# Clean build
xcodebuild -project Murmur.xcodeproj -scheme Murmur clean build

# Resolve package dependencies
xcodebuild -project Murmur.xcodeproj -scheme Murmur -resolvePackageDependencies
```

No test targets exist yet.

## Architecture

Murmur is a **menu bar-only macOS app** (LSUIElement) built with SwiftUI + AppKit. It reads clipboard text aloud using local TTS. No dock icon, no main window — just a menu bar icon with a dropdown panel and a settings window.

### State Flow

`MurmurApp` (@main) creates `AppState` (@Observable, @MainActor) and injects it via `.environment(appState)` into both the `MenuBarExtra` dropdown and the `Settings` scene. Views read state with `@Environment(AppState.self)`.

`AppState` owns a `SystemVoiceEngine` and listens for state changes via callback. The global hotkey (⌘⇧L) toggles between idle→speak, speaking→stop, paused→resume.

### VoiceEngine Protocol

`VoiceEngine` is a `@MainActor` protocol. `SystemVoiceEngine` implements it with AVSpeechSynthesizer. Future engines (Kokoro, OpenAI TTS) will conform to this same protocol. State flows upward via `onStateChange` callback.

### Concurrency Pattern

Swift 6.2 strict concurrency is enabled (`SWIFT_STRICT_CONCURRENCY: complete`). The key pattern for AppKit/AVFoundation delegates:

```swift
// Delegate methods must be nonisolated, then cross back to MainActor
nonisolated func speechSynthesizer(_ synth: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    MainActor.assumeIsolated { setPlaybackState(.idle) }
}
```

For non-MainActor callbacks (e.g., KeyboardShortcuts): wrap in `Task { @MainActor in }`.

### Settings Window Workaround

LSUIElement apps can't reliably surface settings windows. `AppState.openSettings()` temporarily sets `NSApp.setActivationPolicy(.regular)`, and `AppDelegate` resets to `.accessory` when the window closes.

### Preferences

All UserDefaults keys are defined in `Preferences.swift` using the `Defaults` package. Hotkey names use `KeyboardShortcuts.Name` extensions. Settings views bind directly with `@Default(.key)`.

## Dependencies (SPM via project.yml)

- **KeyboardShortcuts** — global hotkey registration + SwiftUI recorder
- **LaunchAtLogin-Modern** (imported as `LaunchAtLogin`) — SMAppService toggle
- **Defaults** — type-safe UserDefaults with `@Default` property wrapper

## Project Conventions

- **Target**: macOS 15+, Apple Silicon, Swift 6.2
- **Build system**: XcodeGen (`project.yml` → `.xcodeproj`)
- **State**: `@Observable` + `@Environment`, not `ObservableObject`/`@EnvironmentObject`
- **Concurrency**: `@MainActor` on all UI/state types; `Sendable` on data types
- **Extraction**: `ClipboardExtractor` is a stateless enum; future extractors will use a `TextExtractor` protocol
- **Voice rate**: User-facing 0.5–2.0x stored in Defaults; converted to AVSpeech rate by multiplying by 0.5

## ROADMAP.md

The roadmap is the source of truth for project scope and phasing. Read it at the start of each session. Work in phase order. Mark checkboxes as tasks complete.
