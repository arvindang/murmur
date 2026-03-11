# Murmur

A zero-cloud macOS menu bar utility that reads aloud or summarizes content from any app using local AI. No accounts, no API keys, no data leaves your machine.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                   Menu Bar App                        │
│              (SwiftUI + AppKit hybrid)                │
├──────────────┬──────────────┬────────────────────────┤
│  Text        │ Summarizer   │  Voice Engine           │
│  Extraction  │              │                         │
│              │              │                         │
│  AXorcist    │  Local:      │  Local:                 │
│  (a11y API)  │  Foundation  │  Soprano 80M            │
│              │  Models      │  (mlx-audio-swift)      │
│  Pasteboard  │  (macOS 26+) │                         │
│  fallback    │              │  Fallback:              │
│              │  Cloud:      │  AVSpeechSynthesizer    │
│              │  Claude API  │                         │
│              │              │  Cloud (optional):      │
│              │              │  OpenAI TTS             │
└──────────────┴──────────────┴────────────────────────┘
```

### Core Principles
- **Local-first**: Everything runs on-device by default. Cloud is opt-in.
- **Universal**: Works with any app — browsers, Notes, Mail, Preview, Slack, VS Code.
- **Invisible**: No window. Menu bar icon + global hotkey. Audio is the only output.
- **Fast**: Stream audio as summary generates. Sub-second latency for read-aloud.

### Tech Stack
- **Language**: Swift 6.2, SwiftUI for settings, AppKit for menu bar integration
- **IDE**: Xcode 26 (.xcodeproj + SPM for dependencies)
- **Min Target**: macOS 15 Sonoma (Apple Silicon required)
- **Text extraction**: AXorcist (modern AXUIElement wrapper), NSPasteboard fallback
- **Local TTS**: Soprano 80M via mlx-audio-swift (MLX, downloaded on first use)
- **TTS fallback**: AVSpeechSynthesizer (zero-download, instant)
- **Cloud TTS (opt-in)**: OpenAI TTS (gpt-4o-mini-tts, user provides API key)
- **Local LLM**: Foundation Models framework (macOS 26+ only, graceful degradation)
- **Cloud LLM (opt-in)**: Claude API (Haiku for speed, Sonnet for quality, user provides key)
- **Global hotkeys**: KeyboardShortcuts (sindresorhus)
- **Audio**: AVAudioEngine for playback with streaming support
- **Storage**: UserDefaults via Defaults (sindresorhus), Keychain for API keys
- **Launch at login**: LaunchAtLogin-Modern (sindresorhus, SMAppService)
- **Auto-update**: Sparkle 2
- **Distribution**: Direct download (.dmg) with notarization, then Mac App Store later

### Dependencies (Swift Packages)
| Package | Purpose |
|---------|---------|
| mlx-audio-swift | Soprano TTS inference on Apple Silicon |
| KeyboardShortcuts | Global hotkey registration + recorder UI |
| LaunchAtLogin-Modern | Launch at login via SMAppService |
| Defaults | Type-safe UserDefaults with SwiftUI support |
| Sparkle 2 | Auto-update framework |
| AXorcist | Modern Swift wrapper for Accessibility API |

---

## Phase 1: Audio Pipeline — "Read Selection Aloud"

**Goal**: Get audio output working end-to-end with the simplest text input path.
**Build order**: Menu bar shell with system voices first → swap in Kokoro.

### 1.1 — Menu Bar Shell
- [ ] Create macOS menu bar app (LSUIElement, no dock icon)
- [ ] MenuBarExtra with `.window` style for dropdown UI
- [ ] SwiftUI settings window (workaround: hidden window + NSApp activation policy toggling for reliable Settings presentation)
- [ ] Global hotkey registration (default: ⌘⇧L) using KeyboardShortcuts
  - [ ] Recorder UI in settings for user customization
- [ ] Menu bar icon states: idle, processing, speaking (SF Symbols)
- [ ] Stop playback on second press of hotkey (toggle behavior)
- [ ] LaunchAtLogin-Modern toggle in settings

### 1.2 — Text Input (Simple)
- [ ] Read text from system pasteboard (clipboard) as the initial input method
- [ ] Menu bar dropdown option: "Read Clipboard"
- [ ] Strip HTML tags, normalize whitespace, handle common encoding issues
- [ ] Truncate to reasonable max length (~10,000 chars) with user-facing note

### 1.3 — System Voice Baseline
- [ ] Implement VoiceEngine protocol
- [ ] AVSpeechSynthesizer implementation as the zero-download default
- [ ] Use "Premium" system voices when available (e.g., Zoe for US English)
- [ ] Audio output via AVAudioEngine for consistent playback control
- [ ] Playback controls in menu bar dropdown: pause/resume, stop
- [ ] Settings: voice selection dropdown, speaking rate slider (0.75x–2.0x)
- [ ] Voice preview button in settings

### 1.4 — Soprano TTS Integration
- [x] Integrate Soprano 80M via mlx-audio-swift Swift package
- [x] First-launch flow: prompt user to download Soprano model (~160MB)
- [x] Store models in HuggingFace cache (~/.cache/huggingface/hub/)
- [x] Audio synthesis pipeline: text → Soprano → PCM buffer → AVAudioEngine
- [x] Streaming playback: begin audio output as soon as first sentence is synthesized
- [x] Settings toggle: "Use system voices" vs "Use Murmur Voice (Soprano)"
- [x] Single Soprano voice (voice parameter unused in this model)
- [x] Explicit failure with status message if Soprano model not yet downloaded

### Phase 1 Ship Criteria
- User copies text, hits ⌘⇧L, hears it read aloud
- System voices work immediately with zero setup
- Soprano voice available after one-time model download
- Under 500ms latency from hotkey to first audio (model kept warm in memory)
- No network calls required

---

## Phase 2: Universal Text Extraction — "Read What I See"

**Goal**: Automatically grab text from the frontmost app without requiring clipboard.

### 2.1 — Accessibility API Integration
- [ ] Request Accessibility permissions on first launch (clear onboarding UI)
- [ ] Integrate AXorcist for modern, async-friendly AXUIElement access
- [ ] Get frontmost application via NSWorkspace.shared.frontmostApplication
- [ ] Extract focused/selected text first (AXSelectedText attribute)
- [ ] Fall back to full document text (AXValue on text areas, AXChildren traversal)
- [ ] Handle common app patterns:
  - Safari/Chrome: focused web content area → extract text
  - Notes/TextEdit: AXValue of main text view
  - Mail: message body text
  - Terminal: visible buffer text
  - VS Code/Electron apps: AXValue with fallback to clipboard simulation

### 2.2 — Browser-Specific Extraction
- [ ] For Safari: AppleScript bridge to get page content
- [ ] For Chrome: AppleScript → execute JS to get document.body.innerText
- [ ] Reader-mode heuristic: strip nav, footer, sidebar content (simple main content area detection)
- [ ] Preference: "Read selected text" vs "Read full page/document"

### 2.3 — Smart Context Detection
- [ ] Detect content type: article, email, code, chat thread, PDF
- [ ] Adjust extraction strategy per content type
- [ ] Show brief toast/notification: "Reading from Safari — 2 min article"
- [ ] Handle edge case: no extractable text → show notification, don't fail silently

### Phase 2 Ship Criteria
- User focuses any app, hits ⌘⇧L, Murmur reads the visible/selected content
- Works reliably with Safari, Chrome, Notes, Mail, Preview, Slack, VS Code
- Graceful fallback to clipboard if accessibility extraction fails

---

## Phase 3: Local Summarization — "Give Me the TLDR"

**Goal**: Add on-device summarization before reading content aloud.

### 3.1 — Foundation Models Integration (macOS 26+)
- [ ] Use `@available(macOS 26, *)` checks to gate summarization features
- [ ] Integrate Foundation Models framework for on-device inference
- [ ] Implement summarization prompt template:
  ```
  Summarize the following content in 2-3 spoken sentences.
  Be concise and conversational — this will be read aloud.
  Do not use bullet points or formatting.

  Content: {extracted_text}
  ```
- [ ] Token streaming: pipe output tokens directly to TTS as sentences complete
- [ ] On macOS 15: summarization UI shows "Requires macOS 26 or Claude API" with link to settings

### 3.2 — Cloud Summarization (Claude API)
- [ ] Settings: "Summarization engine" — Local (default on macOS 26+) / Claude API
- [ ] User provides their own API key (stored in Keychain)
- [ ] Use claude-haiku for speed, claude-sonnet as option for quality
- [ ] Works on macOS 15+ (primary summarization path for pre-Tahoe users)
- [ ] Visual indicator in menu bar when cloud mode is active

### 3.3 — Interaction Modes
- [ ] Two global hotkeys (user-configurable via KeyboardShortcuts):
  - ⌘⇧L — **Listen**: Read the full content aloud
  - ⌘⇧K — **Key points**: Summarize then read aloud
- [ ] Menu bar dropdown reflects current mode
- [ ] Summary length setting: "Quick" (1-2 sentences), "Standard" (3-4), "Detailed" (paragraph)
- [ ] After summary plays, subtle chime/tone to indicate completion

### 3.4 — Streaming Pipeline
- [ ] Pipeline architecture: Text extraction → LLM (streaming) → Sentence buffer → TTS → Audio
- [ ] Begin TTS on first complete sentence from LLM output
- [ ] Overlap: synthesize sentence N+1 while playing sentence N
- [ ] Target: first audio within 2-3 seconds of hotkey press

### Phase 3 Ship Criteria
- User hits ⌘⇧K on a long article, hears a ~30-second spoken summary within 3 seconds
- On macOS 26+: entirely local by default — no network indicator visible
- On macOS 15: Claude API provides summarization (read-aloud still fully local)
- Cloud toggle works for users who want higher quality summaries on any OS

---

## Phase 4: Voice & Polish — "Make It Mine"

**Goal**: Voice customization, cloud TTS option, and quality-of-life features.

### 4.1 — Voice Management
- [ ] Add additional TTS engines (Marvis TTS for multilingual, others)
- [ ] Organize voices by language and style
- [ ] Per-mode voice assignment (e.g., different voice for summaries vs full read)
- [ ] Cloud TTS option: OpenAI TTS with user's own key (stored in Keychain)
  - [ ] gpt-4o-mini-tts for speed, prompt-steerable voice direction
- [ ] Voice preview button for all options (speaks a sample sentence)

### 4.2 — History & Queue
- [ ] Lightweight history: last 20 items with title, source app, timestamp
- [ ] Accessible from menu bar dropdown
- [ ] Replay any history item
- [ ] Queue: if something is playing, new ⌘⇧L adds to queue rather than interrupting
- [ ] "Read later" — manually add clipboard content to queue

### 4.3 — Quality of Life
- [ ] Auto-pause when system audio starts (music, video call)
- [ ] Resume when system audio stops (configurable)
- [ ] AirPods integration: play/pause maps to Murmur when it's the active audio source
- [ ] Notification when summary/reading is queued or complete
- [ ] Skip forward/back by sentence (via menu bar controls or media keys)
- [ ] Speed ramping: gradually increase reading speed over time (configurable)

### 4.4 — Onboarding
- [ ] First-launch walkthrough: accessibility permissions, model download, voice selection, hotkey setup
- [ ] Sample content to demonstrate both read and summarize modes
- [ ] "Ready to go" confirmation with the chosen voice speaking a welcome message

### Phase 4 Ship Criteria
- Settings feel polished and complete
- Users can customize voice, speed, summary length, and hotkeys
- History lets you replay recent items without re-extracting text

---

## Phase 5: Distribution & Growth

### 5.1 — Launch Prep
- [ ] Landing page (Astro or plain HTML on Cloudflare Pages)
- [ ] Screen recording demo: 30-second GIF showing hotkey → summary → audio
- [ ] Direct .dmg download with auto-update (Sparkle 2)
- [ ] Notarization via `notarytool` and code signing for Gatekeeper

### 5.2 — Launch
- [ ] Product Hunt launch
- [ ] Hacker News Show HN (emphasize local-first, zero-cloud, privacy angle)
- [ ] r/macapps, r/apple, r/artificial

### 5.3 — Mac App Store
- [ ] Adapt for App Store sandboxing (accessibility API requires entitlements review)
- [ ] App Store listing with screenshots and preview video
- [ ] Pricing: free tier (system voices + limited summaries/day) / one-time purchase for Kokoro voices + unlimited summaries

---

## Open Questions

- **Model bundling vs download**: Bundle the app at <20MB. Download Soprano model (~160MB) on first launch. Foundation Models uses system-provided models (no download). Consider: ship with system voices as instant default, prompt for Soprano download during onboarding.
- **PDF extraction**: Preview's accessibility tree is spotty for PDFs. May need PDFKit-based extraction as a special case in Phase 2.
- **Memory pressure**: Soprano 80M is modest (~160MB). Foundation Models managed by the OS. Still need to handle low-memory gracefully — unload Soprano when idle for N minutes.
- **Foundation Models capabilities**: At time of writing, the exact capabilities and model quality of the Foundation Models framework for summarization tasks needs validation during Phase 3 development. May need prompt tuning.

---

## Claude Code Usage

This file is the source of truth for project scope and phasing. When working with Claude Code:

1. **Start each session** by referencing this file: `Read ROADMAP.md and continue from where we left off`
2. **Work in phase order** — don't jump ahead. Each phase builds on the last.
3. **Mark checkboxes** in this file as tasks are completed.
4. **Add implementation notes** under each task as decisions are made.
5. **Create a CHANGELOG.md** after each phase ships.

### Project Structure (Target)
```
Murmur/
├── ROADMAP.md              ← you are here
├── CHANGELOG.md
├── Murmur.xcodeproj
├── Murmur/
│   ├── App/
│   │   ├── MurmurApp.swift
│   │   ├── MenuBarController.swift
│   │   └── AppState.swift
│   ├── Extraction/
│   │   ├── TextExtractor.swift         (protocol)
│   │   ├── AccessibilityExtractor.swift (AXorcist)
│   │   ├── BrowserExtractor.swift
│   │   └── ClipboardExtractor.swift
│   ├── Summarization/
│   │   ├── Summarizer.swift            (protocol)
│   │   ├── FoundationModelSummarizer.swift (macOS 26+)
│   │   └── ClaudeSummarizer.swift
│   ├── Voice/
│   │   ├── VoiceEngine.swift           (protocol)
│   │   ├── SopranoEngine.swift         (mlx-audio-swift)
│   │   ├── SystemVoiceEngine.swift     (AVSpeechSynthesizer)
│   │   └── OpenAIVoiceEngine.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── VoiceBrowserView.swift
│   │   └── Preferences.swift
│   └── Resources/
│       └── (SF Symbols, sounds)
└── Models/                             (downloaded at runtime, gitignored)
    └── soprano/
```
