# QuinnVoice

A native macOS voice assistant powered by [Gemini Live](https://ai.google.dev/gemini-api/docs/live) and [OpenClaw](https://github.com/openclaw/openclaw).

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- **Voice Conversations** — Real-time speech-to-speech via Gemini Live API
- **Menu Bar App** — Lives in your menu bar, activated with ⌥Space or "Hey Quinn"
- **Agent Mode** — Computer use with keystroke injection, mouse control, and screen reading
- **Dual Gemini Architecture** — Live for voice, Flash for tools/analysis, Pro for complex reasoning
- **OpenClaw Integration** — Full access to your OpenClaw agent's tools and context
- **25+ Tools** — Calendar, email, reminders, smart home, file management, and more
- **Multi-Modal** — Camera and screen context awareness
- **Safety Rails** — Confirmation gates for destructive actions, app allowlist, audit log

## Install

1. Download **QuinnVoice-0.2.0.dmg** from [Releases](https://github.com/jaredmabry/quinnvoice/releases/latest)
2. Drag to Applications
3. Open QuinnVoice — no Gatekeeper warnings (signed & notarized by Apple)
4. Enter your Gemini API key on first launch

> ✅ **Signed** with Developer ID (Mabry Ventures LLC)
> ✅ **Notarized** by Apple — opens clean, no right-click workaround needed

## Requirements

- macOS 26 (Tahoe) or later
- [Gemini API key](https://aistudio.google.com/apikey)
- [OpenClaw](https://github.com/openclaw/openclaw) (optional, for tool integration)

## Build from Source

```bash
git clone https://github.com/jaredmabry/quinnvoice.git
cd quinnvoice
swift build
```

### Run Tests

```bash
swift test
```

323 tests across 18 test suites covering models, config, audio, Gemini, OpenClaw, agent, context, input, and integration.

## Architecture

| Component | Model | Use Case |
|-----------|-------|----------|
| Voice | `gemini-live-2.5-flash-native-audio` | Speech-to-speech conversations |
| Tools | `gemini-2.5-flash` | Tool processing, screen analysis, summarization |
| Agent | `gemini-2.5-pro` | Complex reasoning, computer use, code analysis |

See [DESIGN.md](DESIGN.md) for UI/UX guidelines, color system, and performance budgets.

## Privacy

- API keys stored in macOS Keychain, never on disk
- No telemetry or analytics
- All processing via Gemini API (your key, your data)
- Microphone/camera only active during conversations

## License

MIT — see [LICENSE](LICENSE)
