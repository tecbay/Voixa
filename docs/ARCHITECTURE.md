# Architecture

Voixa is two processes: a small menu bar app that handles the keyboard, microphone and UI, and a helper that runs the speech model only while it's needed.

```
┌──────────────────────── Voixa.app (~15 MB) ─────────────────────────┐
│                                                                      │
│  HotkeyMonitor ──► PushToTalk ──► DictationController ──► TextInserter
│  (Fn event tap)    (state machine)   │        ▲            (paste + restore
│                                      │        │             clipboard)
│                    AudioRecorder ────┘        │                      │
│                    (16 kHz mono)              │  DictationHUD        │
│                                               │  (floating pill)     │
│                              TranscriberProcess                      │
└───────────────────────────────────┬──────────┬───────────────────────┘
                     JSON lines on  │ stdin    │ stdout
                                    ▼          │
┌──────────── VoixaTranscriber (started on demand) ───────────────────┐
│  WhisperKitEngine ──► AllowedLanguageSampler ──► WhisperKit (CoreML) │
│  GPU (fast) or Neural Engine (efficient)                             │
└──────────────────────────────────────────────────────────────────────┘
```

## A dictation, step by step

1. **Fn down.** `HotkeyMonitor` sees it through a listen-only `CGEventTap`, which needs Input Monitoring permission. `PushToTalk` turns it into *start recording*.
2. **Recording.** `AudioRecorder` captures the default microphone with `AVAudioEngine` and converts it to 16 kHz mono Float32. The engine only runs while recording, so the mic indicator is off otherwise. If the model isn't loaded, `DictationController` starts loading it now, while you're still speaking.
3. **Fn up.** `PushToTalk` decides what the release means:
   - held longer than 0.3 s: transcribe;
   - a quick tap: cancel;
   - a second tap within 0.4 s: hands-free mode;
   - another key pressed while Fn is down: cancel, because Fn was being used as a modifier.
4. **Silence check.** `SpeechGate` skips recordings that are too short or too quiet. Whisper tends to invent text ("Thank you for watching") from silence.
5. **Transcribe.** The audio goes to the helper with the user's languages and a prompt (`PromptBuilder`: custom vocabulary plus the previous sentence, if recent).
6. **Insert.** `TextInserter` puts the text on the clipboard, posts ⌘V (needs Accessibility), then restores the previous clipboard contents. The temporary entry is marked transient so clipboard managers ignore it.
7. **Idle.** After 3 minutes without dictation, or on a memory-pressure warning, the helper is ended.

## Accent-aware language detection

Whisper normally detects the language from the first 30 seconds of audio and picks from all 99 languages it knows. For South Asian speakers that fails in predictable ways: accented English gets labelled Hindi, Urdu or Malay, and a short Bengali clip gets labelled Hindi or English.

Voixa asks the user which languages they speak. With one language, detection is skipped and that language is forced. With several, `AllowedLanguageSampler` runs Whisper's language-detection step but only compares the scores of the allowed language tokens. WhisperKit's built-in `detectLanguage` can't do this, because it reports only the overall top pick.

## Why a helper process

CoreML keeps roughly 0.5 GB of buffers after a model is unloaded, outside any malloc zone the app can release. The only reliable way to return all of it is to end the process that loaded it. The helper protocol is defined in `TranscriberProtocol.swift`:

| Request (app → helper) | Response (helper → app) |
|---|---|
| `load(model, mode)` | `progress(fraction)` while downloading, then `loaded(mode, seconds)` |
| `transcribe(audio, languages, prompt)` | `transcript(text, language)` |
| | `failure(message)` for either request |

Each message is one JSON line prefixed with `@voixa `, so stray library output on stdout is ignored. The helper exits when its stdin closes, so it can't outlive the app.

## Compute modes

`ComputeMode.choose` looks at free memory (`SystemMemory.available`) each time the model loads:

| Mode | When | Memory | Speed |
|---|---|---|---|
| fast (GPU encoder + decoder) | ≥ 4 GB available | ~2.5 GB | ~0.8 s for 5 s of speech |
| efficient (Neural Engine) | otherwise | ~0.3 GB | ~1.6 s |

Running the encoder on the GPU and the decoder on the Neural Engine (or the reverse) was also measured. It cost nearly as much memory as fast mode for little speed gain.

## Model storage

Models download from [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) into `~/Library/Application Support/Voixa/Models`. `ModelStore` writes a `.voixa-complete` marker only after a download finishes. An interrupted download (folders present, weights missing) is therefore resumed instead of failing to load.

## Testing

- `make test`: unit tests for the pure logic in `VoixaKit`: push-to-talk state machine, silence gate, prompt builder, settings migration, compute-mode choice, helper protocol.
- `voixa-transcribe`: runs the real engine on audio files. Use `--runs N` for warm latency and `VOIXA_DEBUG=1` for language scores and timings.
