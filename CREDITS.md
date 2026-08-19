# Credits

Splay is a small app standing on a lot of other people's work. This is the honest
accounting of whose.

## MacParakeet, and Daniel Moon

Splay exists because **[MacParakeet](https://github.com/moona3k/macparakeet)** existed
first. It is not an inspiration or a reference — it is the foundation Splay was built
from, and a great deal of what makes Splay fast is code [Daniel Moon](https://github.com/moona3k)
wrote: the CoreML speech pipeline, the audio capture path, the scheduler that keeps
transcription off the main thread, the storage layer, the release tooling.

What changed here is the *product*, not the engine. Splay collapses dictation and meeting
recording into one gesture, throws away the window, and takes the position that a
transcript should never be polished. Those are opinions about one person's workflow, not
improvements — MacParakeet is broader, more capable software, and if you want dictation
into any app, YouTube import, meeting summaries, calendar auto-start, or LLM transforms,
you should go and use it.

Thank you for building it in the open, and for choosing a licence that let someone else
take it somewhere personal.

## Speech recognition

- **[Parakeet TDT 0.6B-v3](https://build.nvidia.com/nvidia/parakeet-tdt-0-6b-v3)** —
  NVIDIA's speech model, the reason a full hour of audio transcribes in about twenty
  seconds without touching a server.
- **[FluidAudio](https://github.com/FluidInference/FluidAudio)** — the Swift/CoreML layer
  that runs Parakeet on the Apple Neural Engine. It removed an entire Python runtime from
  this app's ancestry.
- **[WhisperKit / argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)** by
  Argmax — optional multilingual recognition.

## Libraries

- **[GRDB.swift](https://github.com/groue/GRDB.swift)** — SQLite, done properly.
- **[Sparkle](https://github.com/sparkle-project/Sparkle)** — in-app updates outside the
  App Store, maintained for two decades.
- **[swift-argument-parser](https://github.com/apple/swift-argument-parser)**,
  **[swift-collections](https://github.com/apple/swift-collections)**,
  **[swift-crypto](https://github.com/apple/swift-crypto)**,
  **[swift-asn1](https://github.com/apple/swift-asn1)** — Apple.
- **[swift-transformers](https://github.com/huggingface/swift-transformers)** and
  **[swift-jinja](https://github.com/huggingface/swift-jinja)** — Hugging Face.
- **[yyjson](https://github.com/ibireme/yyjson)** — very fast JSON.

## Bundled tools

- **[FFmpeg](https://ffmpeg.org)** — audio and video conversion. Genuinely one of the most
  load-bearing pieces of software in the world.
- **[yt-dlp](https://github.com/yt-dlp/yt-dlp)** — media download.
- **[Node.js](https://nodejs.org)** — a JavaScript runtime a few of the above rely on.

Full licence texts for everything here are in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

## Design influences

- **[DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)** — the blur-into-focus
  behaviour the card borrows as it opens.
- **[Talkify](https://github.com/tornikegomareli/Talkify)** — where the "dead is not the
  same as silent" doctrine came from. Splay used to kill a recording that went quiet for
  ten seconds, which lost real recordings on cold Bluetooth. Talkify's approach of
  distinguishing *no signal* from *no speech* is the reason Splay now holds a waiting
  light instead of throwing your recording away.

## And

Every person who filed a bug against MacParakeet, argued about a design decision in an
issue thread, or wrote up why a model choice was wrong. Most of that thinking is still in
this codebase, several rewrites later.
