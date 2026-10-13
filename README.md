# MacDictationNotion

Dictate straight into Notion from anywhere on your Mac — using the on-device speech engine already built into macOS. No cloud STT API, no per-word cost, no audio leaving your machine.

Press **⌘⇧D**, talk, press **⌘⇧D** again. A new page lands in your Notion database.

## Why

I take a lot of quick notes into Notion, and typing them (especially on my phone) kills the thought before I finish it. Every "voice to Notion" tool I tried routed audio through a cloud speech API with a monthly bill. macOS already ships a perfectly good on-device dictation engine — the same one behind system Dictation — so I wired it straight to the Notion API instead.

## How it works

| Step | What happens |
|------|--------------|
| Trigger | Global hotkey **⌘⇧D** (works in any app) |
| Speech → text | macOS **Speech framework**, on-device (free, offline, same engine as system Dictation) |
| Stop | Press **⌘⇧D** again → recognition ends and sends automatically |
| Send | Notion REST API `POST /v1/pages` creates a new page |
| Feedback | Menu bar icon state + native notification (success / failure) |
| Offline | Caches the transcript locally and retries when the network is back |

Menu bar icon: idle · recording · sending · needs setup.

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)
- The dictation language you want added once in **System Settings › Keyboard › Dictation** (on-device recognition needs it downloaded)

## Notion setup (5 min)

1. **Create an integration** at https://www.notion.so/my-integrations → *New integration* (type: Internal). Copy the **Internal Integration Secret** (`secret_...` / `ntn_...`) → this is your `notionToken`.
2. **Connect a database.** Prepare a Notion database, note its **Title property name** (default `Name`). On the database page: `···` › *Connections* › add the integration you just made. (Skipping this causes 403 / object-not-found errors.)
3. **Get the Database ID.** Open the database in a browser — the 32-character value in the URL (no hyphens) is your `databaseId`.

## Build

Copy the folder to your Mac, then build with the Swift toolchain. See the setup notes in the repo.

## Notes

- Native Swift, menu bar only, no third-party STT dependency.
- Recognition quality varies by language — add and test your language in System Settings first.
- The app is currently unsigned. On first launch, right click the app → **Open** to get past the Gatekeeper "unidentified developer" warning. Notarization is on the list.

## License

MIT — see [LICENSE](LICENSE).

## Build log

- [Build story (English)](https://aicoder-lab.blogspot.com/2026/07/macdictationnotion-voice-notes-notion.html)
- [개발기 (Korean)](https://aicoder-lab.blogspot.com/2026/07/macos-dictation-notion-menubar.html)
