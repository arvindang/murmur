# Changelog

## v0.1.0

Initial release of Murmur — a menu bar macOS app that reads text aloud.

### Features

- **Menu bar app** — Lives in the menu bar with no dock icon or main window. SF Symbol icons reflect idle, processing, and speaking states.
- **Global hotkey** (⌘⇧L) — Toggle read-aloud from anywhere. Customizable in settings via KeyboardShortcuts recorder.
- **Clipboard reading** — Read clipboard text with HTML stripping, whitespace normalization, and smart truncation.
- **Universal text extraction** — Automatically grabs text from the frontmost app using the Accessibility API (AXorcist), no clipboard needed.
  - Works with Safari, Chrome, Notes, Mail, Terminal, VS Code, Slack, and more.
  - Selected text is read first; falls back to full document content.
- **Browser-specific extraction** — AppleScript bridges for Safari and Chrome extract page content directly, with reader-mode heuristic to strip nav/footer/sidebar.
- **Smart context detection** — Detects content type (article, email, code, chat, PDF) and adjusts extraction strategy. Shows a brief toast with source and estimated read time.
- **System voices** — AVSpeechSynthesizer with premium voice selection, adjustable rate (0.5–2.0x), and voice preview.
- **OpenAI TTS** — Cloud-based high-quality speech via OpenAI API (user provides their own key). Multiple voice options with preview.
- **Playback controls** — Pause, resume, and stop from the menu bar dropdown.
- **Settings** — Voice engine selection, voice browser, rate slider, hotkey recorder, launch-at-login toggle.
- **Launch at login** — SMAppService integration via LaunchAtLogin-Modern.
- **Notarized distribution** — Signed and notarized .dmg for Gatekeeper-approved installation.

### Requirements

- macOS 15 Sonoma or later
- Apple Silicon
