# Product & Architecture Decisions

Voixa is a local, on-device voice-to-text app for macOS. Hold a key, speak, release, and the text is typed into whatever field has focus.

| # | Decision | Choice | Notes |
|---|---|---|---|
| 1 | Target users | South Asia | Hindi, Bengali, Urdu, Tamil, etc., plus South Asian–accented English |
| 2 | Speech style | Mixed | Accented English, native language, and code-switching (Hinglish / Banglish) |
| 3 | Output script | User setting | Defaults to native script (Devanagari, Bengali, ...); toggle for romanized output |
| 4 | Minimum hardware | Any Apple Silicon | Whisper large-v3-turbo on every Mac; large-v3 selectable in Settings on 16 GB+ |
| 5 | Minimum macOS | 15 Sequoia | Apple SpeechAnalyzer / Foundation Models only when running on macOS 26+ |
| 6 | Trigger | Hold Fn (push-to-talk) | Double-tap Fn for hands-free toggle; rebindable |
| 7 | LLM cleanup | Off by default, opt-in | Qwen via MLX. Required for romanized output, so turning that on prompts to enable cleanup |
| 8 | Bundle ID | `com.techlevin.voixa.mac` | Product name: Voixa |
| 9 | Distribution | Open source, direct DMG | Developer ID signed + notarized, Sparkle updates. No Mac App Store (sandbox blocks Accessibility / event taps) |
| 10 | License | MIT | |
| 11 | Project setup | XcodeGen + local SwiftPM package | `project.yml` generates the `.xcodeproj`; logic lives in `Packages/VoixaKit` |

## Pipeline

```
Fn hotkey → AVAudioEngine (16 kHz mono) → silence check → Whisper (WhisperKit)
          → [optional] Qwen cleanup (MLX) → paste into focused field (clipboard restored)
```

## Speech recognition

- Default engine: **Whisper large-v3-turbo** via WhisperKit, chosen after the first benchmark below (about 3x faster, same results). **large-v3** is an option in Settings on 16 GB+ Macs.
- Engines sit behind the `TranscriptionEngine` protocol so others (whisper.cpp, Apple SpeechAnalyzer, language-specific models) can be added.
- Quality settings:
  - Users pick their languages; auto-detection is limited to that set (stops accented English being detected as another language).
  - Custom vocabulary and the previous utterance go into Whisper's prompt.
  - A silence check skips empty recordings, which prevents Whisper from inventing text (Silero VAD trimming planned).
  - Greedy decoding with temperature fallback (WhisperKit has no beam search); uncompressed models only.
- Language detection uses Whisper's own language scores, restricted to the user's languages (`AllowedLanguageSampler`). WhisperKit's built-in detection only reports the overall top pick.

## Memory

The model never stays in memory while unused:

- It runs in a separate helper process (`VoixaTranscriber`). CoreML keeps about 0.5 GB of buffers even after a model is unloaded, and no call returns that memory, so Voixa ends the helper instead. The menu bar app itself uses about 15 MB.
- On load, Voixa picks a mode from the memory that's free: **fast** (GPU, ~2.5 GB, ~0.8 s per sentence) with at least 4 GB available, otherwise **efficient** (Neural Engine, ~0.3 GB, ~1.6 s).
- The helper is ended after 3 idle minutes, or right away on a macOS memory-pressure warning (after the current dictation, if one is running).
- Pressing Fn starts loading while you speak, so a reload (about 1–3 s once compiled) mostly overlaps your speech.

### First benchmark (M3 Max, synthetic macOS TTS voices, warm)

| Clip | large-v3 | large-v3-turbo |
|---|---|---|
| Indian English, 3.5 s | 1.2 s, "Laravel" → "Lenovo" | 0.36 s, same error |
| Hindi, 2.8 s | 2.5 s, correct | 0.8 s, correct |
| Hinglish, 4.6 s | 2.3 s, correct, English words kept in Latin script | 0.7 s, same |
| Bengali, 1.6 s (en/hi/bn allowed) | detected as Hindi | detected as Hindi |
| Bengali, forced | right words, spelling errors | same |

Takeaways: turbo is about 3× faster with no visible quality loss on these clips; Whisper's Bengali is noticeably weaker than its Hindi. TTS voices are not real accents, so these numbers only show speed and obvious failures.

- Model choice is decided by an evaluation set (Svarah, FLEURS, Common Voice, IndicVoices, plus recordings from real users), scored by WER / CER and latency.
- Fine-tune Whisper with LoRA only if the evaluation shows a specific accent or language group performing poorly.
