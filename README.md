# Voixa

**Private, on-device voice typing for macOS, built for South Asian accents and languages.**

Click into any text box, hold **Fn**, speak, and let go: your words are typed where your cursor is. Speak English, Hindi, Bengali, Urdu or a mix ("Hinglish", "Banglish"). Voixa runs OpenAI's Whisper model locally on Apple Silicon, so your voice never leaves your Mac.

> **Status: early development.** Push-to-talk dictation works end to end. There is no pre-built download yet; build it from source (below).

## Features

- **Works in any app**: Slack, Chrome, VS Code, Terminal, Notes. Voixa pastes into the focused field and puts your clipboard back afterwards.
- **Push-to-talk on Fn**: hold to talk, release to type. Double-tap Fn for hands-free mode; press Fn again to finish or Esc to cancel.
- **Accent-aware language handling**: you choose the languages you speak, and Voixa only picks among those. This stops accented English being mistaken for Hindi or Malay, which is Whisper's most common failure for South Asian speakers.
- **Code-switching**: mixed sentences keep English words in Latin script: "कल की मीटिंग में हमने API deployment discuss किया".
- **Custom vocabulary**: add names and technical terms so Whisper spells them right.
- **Light on memory**: about 15 MB while idle. The speech model loads when you press Fn and is released after 3 idle minutes (see [Memory](#memory)).
- **100% local**: no account, no cloud, no telemetry.

## Supported languages

English, Hindi, Bengali, Urdu, Tamil, Telugu, Marathi, Gujarati, Punjabi, Kannada, Malayalam, Nepali and Sinhala.

Hindi, Hinglish and Indian-accented English work well in early tests. Whisper is noticeably weaker at Bengali. For now, Bengali speakers get the best results by selecting only Bengali. Better Bengali support is on the [roadmap](#roadmap).

## Requirements

- Mac with Apple Silicon (M1 or later)
- macOS 15 Sequoia or later
- About 2 GB of disk space for the speech model
- To build: Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build and run

```bash
brew install xcodegen
git clone https://github.com/tecbay/Voixa.git
cd Voixa
make build
open build/Build/Products/Debug/Voixa.app
```

Voixa lives in the menu bar (microphone icon); it has no Dock icon.

**Keep permissions across rebuilds (recommended for development):** builds are ad-hoc signed by default, and macOS forgets Voixa's permissions every time an ad-hoc build changes. To sign with your own Apple Development certificate instead:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
# then set DEVELOPMENT_TEAM to your team ID in Config/Local.xcconfig
```

## First-time setup

On first launch, a **Set up Voixa** window lists what's needed, with a live checkmark for each step:

| Permission | Why |
|---|---|
| Microphone | To hear you while you hold Fn |
| Input Monitoring | To notice the Fn key while you're in other apps |
| Accessibility | To paste the text into the field you're typing in |

Also set **System Settings → Keyboard → "Press 🌐 key to" → Do Nothing**, otherwise macOS reacts to Fn as well (emoji picker, input source or its own dictation).

Voixa then downloads the speech model (1.6 GB). The first load compiles it for your Mac, which can take a few minutes; after that, loading takes about a second.

Finally, open **Settings…** from the menu bar icon and select the languages you speak. Fewer languages means fewer misdetections.

## Usage

| Action | What happens |
|---|---|
| Hold **Fn**, speak, release | Text is typed into the focused field |
| Double-tap **Fn** | Hands-free: keeps listening until you press Fn again |
| **Esc** while listening | Cancels |
| Fn + another key (e.g. Fn+←) | Treated as a normal shortcut; no recording |

A small pill at the bottom of the screen shows *Listening…* and *Transcribing…*. It never takes focus, so your cursor stays where it is. If Accessibility access is missing, Voixa copies the text and tells you to press ⌘V.

## Speech models

| Model | Download | Speed (M3 Max, 5 s sentence) | Notes |
|---|---|---|---|
| Whisper large-v3-turbo (default) | 1.6 GB | ~0.8 s | Same results as large-v3 in our tests so far |
| Whisper large-v3 | 3 GB | ~2.5 s | Needs 16 GB of memory |

Switch models in Settings. Models are stored in `~/Library/Application Support/Voixa/Models`.

## Memory

The speech model runs in a separate helper process, `VoixaTranscriber`, that Voixa starts when you press Fn and ends after 3 idle minutes. Ending the process is the only way to give all of CoreML's memory back to macOS.

| State | Memory |
|---|---|
| Idle | ~15 MB (helper not running) |
| Dictating, plenty of free memory | ~2.5 GB, GPU, fastest |
| Dictating, memory tight | ~0.3 GB, Neural Engine, about 2× slower |

If macOS reports memory pressure, Voixa releases the model immediately (or right after the dictation in progress).

## Privacy

- Audio is recorded only while you hold Fn (or in hands-free mode), and only kept in memory until it's transcribed.
- Transcription runs entirely on your Mac. The only network access is downloading the model from Hugging Face.
- Voixa stores your settings (languages, vocabulary) in its preferences. It does not keep transcripts or audio.

## Project layout

```
App/                   Menu bar app (SwiftUI + AppKit): hotkey, recording, pasting, UI
Helper/                VoixaTranscriber: helper process that runs the speech model
Packages/VoixaKit/
  Sources/VoixaKit/        Pure logic: push-to-talk, settings, prompts, helper protocol (unit-tested)
  Sources/VoixaEngines/    WhisperKit engine and accent-aware language detection
  Sources/voixa-transcribe/ CLI for transcribing audio files (testing, benchmarks)
Config/                Shared build settings and local signing
docs/                  Architecture and decision records
project.yml            XcodeGen spec; Voixa.xcodeproj is generated, not committed
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit together and [docs/DECISIONS.md](docs/DECISIONS.md) for why things are the way they are.

## Development

```bash
make open    # generate Voixa.xcodeproj and open it in Xcode
make build   # build the app and helper
make test    # run unit tests
```

Transcribe a file with the same engine the app uses:

```bash
swift run --package-path Packages/VoixaKit -c release voixa-transcribe clip.wav --lang en,hi --runs 3
```

| Environment variable | Effect |
|---|---|
| `VOIXA_DEBUG=1` | Log language scores and timing breakdowns to stderr |
| `VOIXA_COMPUTE=gpu\|ane\|mixed` | Force a compute mode (benchmarking) |
| `VOIXA_IDLE_SECONDS=20` | Shorter idle timeout before the model is released (testing) |

Logs: `/usr/bin/log stream --predicate 'subsystem == "com.techlevin.voixa.mac"'`

## Roadmap

- [x] Push-to-talk dictation into any app
- [x] Accent-aware language detection, custom vocabulary
- [x] On-demand model loading, memory-aware compute mode
- [ ] Silero voice activity detection to trim silence
- [ ] Live audio level in the indicator; configurable hotkey
- [ ] Accuracy test set with real South Asian speakers (WER/CER per language)
- [ ] Better Bengali (language-specific or fine-tuned model)
- [ ] Optional on-device LLM cleanup (punctuation, misheard words, romanized output)
- [ ] Signed and notarized DMG with auto-updates

## Contributing

Contributions are welcome, especially recordings and bug reports from speakers of the supported languages. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Acknowledgements

- [OpenAI Whisper](https://github.com/openai/whisper): the speech recognition model (MIT)
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax: on-device Whisper for Apple Silicon (MIT)

## License

[MIT](LICENSE)
