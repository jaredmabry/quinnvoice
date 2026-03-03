# QuinnVoice — macOS Menu Bar Voice Assistant

## Overview
A native macOS menu bar app that connects to an OpenClaw instance and enables live voice conversation via the Gemini Live API. Full Liquid Glass macOS 26 aesthetic.

## Design Language
- **macOS 26 Liquid Glass** — `.glassEffect()` modifier on all chrome
- Navigation layer only (golden rule) — no stacked glass
- Translucent floating panel with depth, refraction, motion
- Minimal: mic button + waveform + status indicator
- Respects Reduce Transparency accessibility setting

## Architecture

```
┌─────────────────────────────┐
│   QuinnVoice (Menu Bar)     │
│   SwiftUI + MenuBarExtra    │
├─────────────────────────────┤
│   AVAudioEngine             │
│   Mic capture (16kHz PCM)   │
│   Speaker playback (24kHz)  │
├─────────────────────────────┤
│   GeminiLiveClient          │
│   WebSocket (bidirectional) │
│   Audio + tool calls        │
├─────────────────────────────┤
│   OpenClawBridge            │
│   REST → localhost:18789    │
│   Context injection         │
│   Tool execution proxy      │
└─────────────────────────────┘
```

## Core Components

### 1. Menu Bar App Shell
- `MenuBarExtra` with SF Symbol icon (waveform.circle)
- Click → opens floating Liquid Glass panel
- States: Idle, Listening, Thinking, Speaking
- Visual: animated waveform rings during Speaking, pulse during Listening

### 2. Audio Engine (`AudioManager`)
- `AVAudioEngine` for mic capture
- Input: 16-bit PCM, 16kHz, mono (Gemini Live input format)
- Output: 16-bit PCM, 24kHz, mono (Gemini Live output format)
- Streaming playback via `AVAudioPlayerNode`
- Echo cancellation via `AVAudioEngine` built-in AEC
- Interrupt handling: stop playback when user speaks (barge-in)

### 3. Gemini Live Client (`GeminiLiveClient`)
- WebSocket connection to `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent`
- Session setup with:
  - Model: `gemini-live-2.5-flash-native-audio`
  - System instructions (Quinn persona + context from OpenClaw)
  - Tool declarations (proxied to OpenClaw)
  - Voice config
- Handles: audio streaming, VAD, barge-in, transcription, function calls

### 4. OpenClaw Bridge (`OpenClawBridge`)
- HTTP client to OpenClaw gateway (`http://127.0.0.1:18789`)
- On session start: fetch context (MEMORY.md, SOUL.md, USER.md)
- Inject as system instructions into Gemini Live session
- Tool proxy: when Gemini calls a function → forward to OpenClaw → return result
- Available tools: calendar, reminders, lights, locks, weather, etc.

### 5. UI Components
- **IdleView**: Glass circle with Quinn icon, subtle breathing animation
- **ListeningView**: Glass circle with pulsing mic waveform
- **ThinkingView**: Glass circle with flowing animation
- **SpeakingView**: Glass circle with radiating waveform rings
- **TranscriptView**: Optional floating text showing conversation (toggle)
- **SettingsView**: API key config, voice selection, OpenClaw URL

## State Machine
```
Idle → (click/hotkey) → Listening
Listening → (speech detected + pause) → Thinking  
Thinking → (response ready) → Speaking
Speaking → (audio complete) → Listening (continuous mode)
Speaking → (user speaks) → Listening (barge-in)
Any → (click/hotkey/escape) → Idle
```

## Configuration
Stored in `~/Library/Application Support/QuinnVoice/config.json`:
```json
{
  "geminiApiKey": "AIzaSy...",
  "geminiModel": "gemini-live-2.5-flash-native-audio",
  "openclawUrl": "http://127.0.0.1:18789",
  "voiceConfig": {
    "name": "Kore",
    "pitch": 0,
    "speed": 1.0
  },
  "hotkey": "⌥Space",
  "continuousMode": true,
  "showTranscript": false
}
```

## Dependencies
- **swift-gemini-api** (`paradigms-of-intelligence/swift-gemini-api`) — Gemini Live WebSocket client
- **AVFoundation** — Audio capture/playback (system framework)
- **SwiftUI** — UI (system framework)
- **Network** / **URLSession** — OpenClaw HTTP bridge (system framework)

## Build Requirements
- Xcode 17+ (macOS 26 SDK)
- macOS 26 Tahoe target
- Swift 6.2+
- Entitlements: Microphone access, Network (outgoing)

## File Structure
```
QuinnVoice/
├── QuinnVoiceApp.swift          # App entry, MenuBarExtra
├── Views/
│   ├── VoicePanelView.swift     # Main floating panel (Liquid Glass)
│   ├── WaveformView.swift       # Animated waveform visualization
│   ├── TranscriptView.swift     # Optional conversation text
│   └── SettingsView.swift       # Configuration UI
├── Audio/
│   ├── AudioManager.swift       # AVAudioEngine mic/speaker
│   └── AudioBufferConverter.swift # PCM format conversion
├── Gemini/
│   ├── GeminiLiveSession.swift  # WebSocket session management
│   └── GeminiToolProxy.swift    # Function call → OpenClaw bridge
├── OpenClaw/
│   ├── OpenClawBridge.swift     # REST client for gateway
│   └── ContextLoader.swift      # Fetch MEMORY/SOUL/USER.md
├── Models/
│   ├── AppState.swift           # ObservableObject state machine
│   ├── VoiceConfig.swift        # Voice settings model
│   └── ConversationMessage.swift # Transcript model
├── Config/
│   └── ConfigManager.swift      # Persistent config read/write
├── Resources/
│   └── Assets.xcassets          # App icon, SF Symbols
├── QuinnVoice.entitlements      # Microphone + Network
└── Package.swift                # SPM dependencies
```

## MVP Scope (v0.1)
1. Menu bar icon → click to open floating glass panel
2. Push-to-talk OR continuous listening
3. Audio streams to Gemini Live, responses play back
4. Quinn persona injected via system instructions
5. Basic status indicators (listening/thinking/speaking)

## v0.2
- OpenClaw tool proxy (calendar, lights, reminders)
- Conversation transcript overlay
- Global hotkey (⌥Space)
- Barge-in support

## v0.3
- Persistent conversation history
- Multi-turn context window
- Voice selection UI
- Auto-reconnect on disconnect
