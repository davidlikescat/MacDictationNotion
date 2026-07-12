# MacDictationNotion

A macOS menu bar app that sends voice notes directly to a Notion database — without leaving whatever you're working on.

Press a hotkey from any app, say your note, press the same hotkey again. Done. The text lands in Notion in about five seconds.

Built entirely with [Claude Code](https://claude.ai/code).

---

## How it works

1. Press the hotkey (default: `⌘1`, configurable)
2. Speak — a floating HUD shows the live transcript as you talk
3. Press the hotkey again to send, or ESC / X button to cancel

The note is created as a new page in your Notion database. If Notion is unreachable, the text queues locally and retries automatically when the connection returns.

**Optional**: if you run [Ollama](https://ollama.com) locally, enable the LLM refinement option to clean up filler words before sending.

## Requirements

- macOS 13 Ventura or later
- A Notion workspace with an Integration token
- Network connection (macOS Speech Recognition uses Apple's servers)

## Installation

1. Download `MacDictationNotion.dmg` from [Releases](../../releases)
2. Open the DMG and copy the app to `/Applications`
3. Clear the Gatekeeper flag (the app is not App Store signed):
   ```bash
   xattr -cr /Applications/MacDictationNotion.app
   ```
4. Launch the app

## Setup

### Notion side

1. Go to [notion.so/profile/integrations](https://www.notion.so/profile/integrations) and create a new internal integration. Copy the token (starts with `ntn_`).
2. Open the target database in Notion. Click `...` → **Connections** → connect your integration.
   > Easy to miss: without this step, the API returns "not found" even with a valid token.
3. Get the database ID from the URL: `notion.so/.../{DATABASE-ID}?v=...`

### App side

Click the menu bar icon → **Preferences...**

| Field | Description |
|---|---|
| Notion Token | Your `ntn_...` integration token |
| Database ID | 32-character ID from the database URL |
| Title property | Name of the title column (default: `Name`) |
| Language | Locale for speech recognition (e.g. `en-US`, `ko-KR`) |
| Prefix | Text prepended to each note (e.g. `Voice memo:`) |
| Hotkey | Click the field and press your desired key combo |
| LLM Refine | Optional Ollama cleanup pass before sending |

Hit **Save** — settings apply immediately.

**Permissions required on first launch:**
- Microphone
- Speech Recognition
- Accessibility (System Settings → Privacy & Security → Accessibility) — needed for the global hotkey

**Check your language model**: System Settings → Keyboard → Dictation → make sure your language is downloaded. If missing, the mic activates but no text appears.

## Building from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/davidlikescat/MacDictationNotion
cd MacDictationNotion
swift build -c release
cp -R .build/release/MacDictationNotion /Applications/MacDictationNotion.app/Contents/MacOS/MacDictationNotion
```

## Architecture

```
MacDictationNotionCore/        platform-independent library
  Settings.swift               config load/save
  DictationPipeline.swift      STT → LLM → Notion state machine
  LLMRefiner.swift             Ollama /api/chat integration
  NotionClient.swift           Notion REST API
  OfflineQueue.swift           local retry queue

MacDictationNotion/            macOS app target
  AppDelegate.swift            menu bar, hotkey, pipeline wiring
  SpeechRecognizer.swift       SFSpeechRecognizer + AVAudioEngine
  RecordingHUDController.swift floating transcript panel
  SettingsWindowController.swift
  HotKeyManager.swift          Carbon RegisterEventHotKey
```

51 unit tests cover the pipeline, Notion client, LLM refiner, offline queue, and settings.

## License

MIT
