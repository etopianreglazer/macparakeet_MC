# Island voice meter — bars left, timer right; the glow goes

> Status: **HISTORICAL** — shipped in `ee8a669c` (thread 17, 2026-09-26), pressed by the owner: "looking really cool".

## Why

Owner, pressing `54b6dd09`: while recording, the island is a steady red, so "recording and hearing
me" looks the same as "recording silence". The island should show that it is *taking in your voice*,
the way upstream's dictation waveform and Apple Voice Memos' Dynamic Island do. The ambient glow
(desktop bloom + pill halo + talk-reactive sway) "feels gimmicky" — remove it entirely.

## Decided (owner picked in the live prototype tuner)

Variant **D — Voice Memos layout**, while recording:

| Slot | Was | Now |
|---|---|---|
| Left (menu hit rect) | breathing Splay mark | **5 bars**, red; clicking them still opens the card |
| Right (stop hit rect) | red status dot | **elapsed timer** `m:ss`, red, monospaced digits; clicking it stops |

Dialled values: bars 5, bar width 2 pt, gap 1.5 pt, max height 14 pt, silent height 2 pt, gain 1.9,
noise gate 0.04, attack 30 ms, release 160 ms. Level in = `micLevel` (per-buffer RMS × 10, clamped),
then gate → `sqrt` → gain/1.6 → attack/release envelope; bars peak in the centre (upstream
`WaveformView`: `level × (1 − distance × 0.55)`) with a small per-bar wobble so it reads as a voice.

- **Mic only drives the bars** — on a double-tap (mic + system) the meeting audio must not look like
  your voice. The coordinator passes `micLevel` alone to the island.
- **Dead ≠ silent:** silent-but-alive = flat red bars at 2 pt; dead input (no frames) = motionless
  **amber** bars + amber timer. Reduce Motion: bars still follow the level, no wobble.
- **Glow removed:** the desktop glow panel (`SplayGlowView`, `SplayAmbientBloom`), the pill halo, the
  mark's glow shadow, the talk-reactive sway, `SplayGlowSettings` + the Settings "Talking glow"
  slider, `TalkEnvelope`/`SplayTalkGlowTuning`. The thin rim stripe stays as the state-colour line.
  The orphaned `splay.talkGlowIntensity` default is left alone (harmless).
- Other states (ready, transcribing, done, failed) keep their current faces.

## Steps

1. `SplayIslandMeter` view + `MeterEnvelope` + `SplayMeterTuning` constants; unit-test the envelope
   and bar-height math (pure functions).
2. Indicator: recording left = meter, right = timer; drop halo/glow/sway; hit rects: widen the
   recording stop rect to cover the timer.
3. Remove the glow panel from `IslandController`, delete `SplayGlow` bloom + settings slider.
4. Coordinator: island gets mic level only.
5. Build, focused tests, `swift test`, `/vet`, install, owner presses. — all done.
