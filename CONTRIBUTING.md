# Contributing to Voixa

Thanks for helping. Voixa aims to be the best local dictation app for South Asian speakers, so feedback from people who speak these languages is the most valuable contribution of all.

## Ways to help

- **Report transcription mistakes.** Open an issue with:
  - the language(s) you spoke;
  - what you said and what Voixa typed;
  - your Mac model;
  - the model selected in Settings.
- **Share test recordings.** Short clips (5–30 s) of real speech help us measure accuracy per language and accent. Please only share recordings you have the right to share, and say if a clip contains code-switching.
- **Fix bugs or add features.** Check the roadmap in the README and open an issue before starting anything large.

## Development setup

```bash
brew install xcodegen
make open      # generates Voixa.xcodeproj and opens Xcode
make test      # unit tests
```

Sign with your own team so macOS keeps Voixa's permissions between builds (see "Build and run" in the README).

## Guidelines

- **Edit `project.yml`, not the Xcode project.** `Voixa.xcodeproj` is generated and ignored by git.
- **Put logic in `VoixaKit` and test it there.** Code in `App/` should be thin glue around macOS APIs.
- **Swift 6 strict concurrency is on.** Avoid `@unchecked Sendable` unless you document why it's safe.
- **Measure claims about speed, memory or accuracy.** Use `voixa-transcribe`, `VOIXA_DEBUG=1` and `footprint`, and put the numbers in the PR.
- **Keep it local.** Nothing may send audio or text off the device.

## Pull requests

1. Fork and create a branch.
2. Make sure `make test` and `make build` pass.
3. Describe what changed and how you tested it, including the languages you tried if it affects transcription.

By contributing you agree that your contributions are licensed under the MIT License.
