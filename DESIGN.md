# QuinnVoice — Design & Architecture Guide

## UI/UX Design Recommendations

### Inspiration from Top-Tier Mac Apps
Drawing from the best menu bar apps (Raycast, CleanShot X, Sleeve, Bartender, iStat Menus):

#### 1. Floating Panel Design
- **Raycast-style command palette feel** — the voice panel should feel like invoking a powerful tool, not opening an app
- **Sleeve-style visual polish** — album art-level attention to the waveform visualization; make it genuinely beautiful to look at
- **CleanShot-style utility** — every pixel should serve a purpose; no chrome for chrome's sake

#### 2. Liquid Glass Implementation
- **Navigation layer only** (Apple's golden rule) — glass on the panel frame, toolbar, and controls
- **Never stack glass** — content area should be solid/opaque for readability
- Use `.glassEffect(.regular.interactive())` for the main panel
- Use `.glassEffect(.regular)` (non-interactive) for status indicators
- Respect `Reduce Transparency` — provide solid fallback backgrounds
- Limit glass containers to **3 max on screen** for performance

#### 3. State Animations
- **Idle**: Subtle breathing glow on the mic icon (2s ease-in-out cycle)
- **Listening**: Real-time waveform driven by actual mic levels, pulsing cyan ring
- **Thinking**: Flowing liquid animation (like mercury moving), purple gradient
- **Speaking**: Radiating concentric rings outward from center, synced to audio amplitude
- **Agent Mode**: Amber/gold border glow with a subtle "scanning" sweep animation

#### 4. Micro-Interactions
- **Haptic-style feedback**: Scale bounce (0.95→1.0) on button press
- **State transitions**: 0.3s spring animation between states
- **Transcript messages**: Slide in from bottom with subtle fade
- **Error states**: Gentle red pulse (not jarring — 2s cycle, low opacity)
- **Agent actions**: Each action logged with a subtle "tick" animation

#### 5. Typography & Layout
- **SF Pro Rounded** for display text (status, headers)
- **SF Mono** for transcript content (technical readability)
- **Dynamic Type** support for accessibility
- **12pt minimum** touch/click targets (Apple HIG)
- **8px grid system** for consistent spacing

#### 6. Color System
```
Primary:     #007AFF (System Blue) — interactive elements
Listening:   #00D4AA (Cyan) — mic active
Thinking:    #AF52DE (Purple) — AI processing  
Speaking:    #34C759 (Green) — audio output
Agent:       #FF9500 (Amber) — computer control
Error:       #FF3B30 (Red) — errors/alerts
Background:  System adaptive (dark/light mode)
```

#### 7. Sound Design (Optional)
- Subtle activation chime on session start (think AirPods connect sound)
- Soft "listening" indicator tone
- No sounds during speaking (avoid feedback loop)

---

## Gemini Model Strategy

### Dual-Model Architecture: Live + Standard

**Yes, absolutely build regular Gemini into QuinnVoice** for non-voice components.

| Use Case | Model | Why |
|----------|-------|-----|
| Voice conversation | `gemini-live-2.5-flash-native-audio` | Speech-to-speech, lowest latency, native audio |
| Tool result processing | `gemini-2.5-flash` | Cheap, fast, good for structured tool responses |
| Agent reasoning (computer use) | `gemini-2.5-pro` | Complex multi-step reasoning needs Pro |
| Screen understanding | `gemini-2.5-flash` | Image/screenshot analysis is fast on Flash |
| Context summarization | `gemini-2.5-flash` | Compress long memory files before injection |
| Code analysis/fixing | `gemini-2.5-pro` | Code requires Pro-level reasoning |

### Implementation

```swift
// GeminiClient.swift — Standard (non-Live) Gemini API client
// Used for: tool processing, agent reasoning, image analysis, summarization
// REST API: POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent

class GeminiClient {
    func generate(model: GeminiModel, prompt: String, images: [Data]? = nil) async throws -> String
    func generateStructured<T: Decodable>(model: GeminiModel, prompt: String, schema: T.Type) async throws -> T
}

enum GeminiModel {
    case flash      // gemini-2.5-flash — cheap, fast
    case pro        // gemini-2.5-pro — smart, expensive
    case liveFlash  // gemini-live-2.5-flash-native-audio — voice only
}
```

### Cost Optimization Strategy

#### Pricing (per million tokens)
| Model | Input | Output | Audio Input |
|-------|-------|--------|-------------|
| Flash | $0.30 | $2.50 | $1.00 |
| Pro | $1.25 | $10.00 | N/A |
| Live Flash | ~$0.30 | ~$2.50 | ~$1.00 |

#### Optimization Techniques

1. **Context Caching** (up to 90% savings)
   - Cache the system prompt (SOUL.md + MEMORY.md) — it rarely changes within a session
   - Cache tool declarations — they're static
   - Only send dynamic content (user speech, screen state) as uncached

2. **Smart Model Routing**
   - Default to Flash for everything except complex reasoning
   - Auto-escalate to Pro only when Flash confidence is low or task is complex
   - Agent loop: use Flash for observe/simple-act, Pro for think/complex-act

3. **Token Minimization**
   - Summarize MEMORY.md before injection (Flash can compress ~5KB to ~500 tokens)
   - Limit screen context to relevant portion (active window only, not full screen)
   - Truncate clipboard content to first 2000 chars
   - Limit agent observation to last 50 lines of terminal output

4. **Batch Non-Urgent Work**
   - Background tasks (summarization, context refresh) can use Batch API at 50% discount
   - Pre-process context during idle time

5. **Estimated Monthly Cost**
   For typical personal use (30 min voice/day, 10 agent sessions/day):
   - Voice (Live Flash): ~$0.50/day → **~$15/month**
   - Tool calls (Flash): ~$0.10/day → **~$3/month**
   - Agent mode (Pro): ~$0.30/day → **~$9/month**
   - **Total estimate: ~$27/month** (without caching)
   - **With context caching: ~$15/month**

---

## Test Coverage Strategy (95% Target)

### Coverage Areas

| Component | Priority | Strategy |
|-----------|----------|----------|
| Models (AppState, VoiceConfig, etc.) | 🔴 Critical | Unit tests — all state transitions, encoding/decoding |
| ConfigManager + KeychainHelper | 🔴 Critical | Unit tests with mocked Keychain |
| AudioBufferConverter | 🔴 Critical | Unit tests — math must be correct |
| GeminiToolProxy | 🟡 High | Unit tests — tool declarations, routing, confirmation gates |
| ContextLoader | 🟡 High | Unit tests with mocked file system |
| OpenClawBridge | 🟡 High | Unit tests with mocked URLSession |
| AgentLoop | 🟡 High | Integration tests — state machine, iteration limits, interrupts |
| ComputerController | 🟡 High | Unit tests for action construction (mock AXUIElement) |
| ClipboardManager | 🟢 Medium | Unit tests with mocked pasteboard |
| GeminiLiveSession | 🟢 Medium | Protocol tests (message format, encoding) |
| HotkeyManager | 🟢 Medium | Unit tests for key event construction |
| WakeWordDetector | 🟢 Medium | State machine tests (mock SFSpeechRecognizer) |
| Views | 🟢 Medium | Snapshot tests for each state |

### Test Structure
```
Tests/QuinnVoiceTests/
├── Models/
│   ├── AppStateTests.swift
│   ├── VoiceConfigTests.swift
│   └── AgentActionTests.swift
├── Config/
│   ├── ConfigManagerTests.swift
│   └── KeychainHelperTests.swift
├── Audio/
│   └── AudioBufferConverterTests.swift
├── Gemini/
│   ├── GeminiToolProxyTests.swift
│   ├── GeminiLiveSessionTests.swift
│   └── GeminiMessageFormatTests.swift
├── OpenClaw/
│   ├── OpenClawBridgeTests.swift
│   └── ContextLoaderTests.swift
├── Agent/
│   ├── AgentLoopTests.swift
│   ├── AgentActionTests.swift
│   └── ComputerControllerTests.swift
├── Context/
│   ├── ClipboardManagerTests.swift
│   └── ScreenContextTests.swift
├── Input/
│   ├── HotkeyManagerTests.swift
│   └── WakeWordDetectorTests.swift
└── Integration/
    ├── SessionControllerTests.swift
    └── ToolExecutionFlowTests.swift
```

---

## Performance Guidelines

1. **Audio latency budget**: < 200ms from speech end to first response audio byte
2. **UI frame rate**: 60fps minimum for all animations (Metal-backed Canvas)
3. **Memory ceiling**: < 150MB resident for idle, < 300MB during active session
4. **CPU idle**: < 2% when no session active (wake word off), < 5% with wake word
5. **WebSocket keepalive**: 30s ping interval to prevent timeout
6. **Reconnect strategy**: Exponential backoff (1s, 2s, 4s, 8s, max 30s)
