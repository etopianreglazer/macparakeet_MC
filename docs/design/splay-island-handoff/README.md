# Handoff: Splay — Island + Card system (fiber-light variant)

Target project: **macparakeet (mc)**.

## Overview
Splay is a one-button macOS recorder: hold ⌥Space, it records anything audible (your voice
and/or system audio), transcribes locally, and writes a Markdown file. The UI is deliberately
reduced to **two interfaces**:

1. **The island** — a black pill hanging from the notch/menu-bar area. It is an *indicator only*.
   It never asks questions, never explains, never holds controls beyond one or two glyphs.
2. **The card** — a centred modal over a dimmed backdrop. It carries *everything else*:
   first run, permissions, confirmations, alerts, recent recordings, settings.

There is no third surface: no dropdown panel hanging off the island, no menu-bar popover,
no settings window. Anything previously in a panel is now a card.

## About the design files
`Splay Island Fiber.dc.html` (+ `support.js`) in this bundle is a **design reference created in
HTML** — a prototype of intended look and behaviour, not production code to copy. The task is to
recreate it in macparakeet's own environment (SwiftUI/AppKit, or whatever the app already uses),
following the codebase's existing patterns. The left sidebar and the fake macOS desktop in the
prototype are **scaffolding for browsing states** — they are not part of the product.

Open the file in a browser: pick a screen in the left rail, then a state chip under "State".

## Fidelity
**High fidelity.** Colours, sizes, radii, timings and copy below are final intent. Match them.

---

## Screen 1 — The island (indicator)

A black pill fixed to the top centre of the display, hanging below the camera housing.
Its width/height animate between states; it is always horizontally centred and its top edge is
flush with the top of the screen (bottom corners rounded only).

### Geometry per state
| State | Width | Height | Bottom radius |
|---|---|---|---|
| Dormant | 206 | 34 | 17 |
| Ready (shortcut held / hover) | 248 | 35 | 18 |
| Recording | 240 | 37 | 19 |
| Transcribing | 248 | 35 | 18 |
| Done / Copied | 300 | 40 | 21 |
| Warning / Failed / File dropped | 244 | 35 | 18 |

Surface: `#0B0813`, fully opaque — no transparency, no blur, no material.
Layout inside: `display:flex; align-items:flex-end; justify-content:space-between;
padding: 0 6px 6px`. A fixed **180 × 32 px** dead zone is reserved in the centre for the camera
housing; content is split into a left cluster and a right cluster around it and must never
run under it. Both clusters are 26 px tall with `overflow:hidden`.

### Contents per state
- **Dormant** — nothing. Empty black pill.
- **Ready** — Splay mark (16 px, `#A99BF5`) left; `⌥␣` right, 11 px,
  `rgba(255,255,255,.45)`, tabular numerals.
- **Recording** — mark only, breathing (see animations). *No dot, no ring, no meter.*
- **Transcribing** — mark left; 14 px spinner right (2 px ring,
  `rgba(255,255,255,.18)`, top edge `#A99BF5`, `spin .8s linear infinite`).
- **Done** — `✓` in a 16 px circle (1.5 px border, `#A99BF5`) left; two 22 px round-rect
  buttons right: `⧉` on `rgba(255,255,255,.1)` and `✦` on `#A99BF5` with `#0B0813` glyph.
- **Copied** — same as Done but the glyph is `⧉`; buttons hidden.
- **Warning** — no left glyph, chevron `⌄` right (10 px, `rgba(255,255,255,.45)`).
- **Failed** — `!` in a circle, `#F0837A`; chevron right.
- **File dropped** — mark only.

### The light (the whole point)
Two effects, both **behind** the island. The light never touches the island's face — the pill
stays flat black; the colour only radiates outward into the wallpaper.

**a) Ambient bloom** — two blurred radial gradients, painted *before* the pill in z-order:
- Layer 1: `top:-70px`, centred, `border-radius:50%`, `filter: blur(46px)`,
  `background: radial-gradient(closest-side, <stateColor>, transparent 72%)`.
- Layer 2: `top:-14px`, height 110 px, `filter: blur(22px)`,
  `radial-gradient(closest-side, <stateColor>, transparent 70%)`.

| State | L1 size | L1 opacity | L2 width | L2 opacity |
|---|---|---|---|---|
| Dormant | 340 × 190 | .26 | 220 | .14 |
| Ready | 420 × 220 | .50 | 270 | .30 |
| Recording | 640 × 290 | 1 | 400 | .85 |
| Transcribing | 520 × 250 | .85 | 320 | .60 |
| Done / Copied | 520 × 250 | .65 | 320 | .45 |
| File dropped | 520 × 250 | .65 | 320 | .45 |

**b) Fiber stripe** — a car-interior ambient-light strip tracing the island's silhouette:
a **solid, opaque 2 px line** (no transparency) inset `-1px` left/right, `-3px` top,
`-1px` bottom, radius matching the pill's bottom radius, `border-top: 0` so the strip only runs
down the sides and around the bottom curve. Its bloom:
`box-shadow: 0 0 9px <soft>, 0 0 22px 2px <soft>` plus the pill's own
`0 10px 34px <ambient>, 0 0 14px -2px <soft>`.
Opacity 1 in every state except Dormant (0.55).

### State colours
| State | Ambient bloom | Fiber line | Fiber bloom |
|---|---|---|---|
| Dormant | `rgba(94,72,214,.30)` | `#5B49B8` | `rgba(120,96,236,.5)` |
| Ready | `rgba(133,104,255,.62)` | `#9B86FF` | `rgba(140,110,255,.7)` |
| Recording | `rgba(232,84,72,.66)` | `#FF6B5E` | `rgba(255,90,74,.75)` |
| Transcribing | `rgba(140,110,255,.62)` | `#A99BF5` | `rgba(150,120,255,.7)` |
| Done / Copied | `rgba(72,196,143,.62)` | `#5FD9A0` | `rgba(76,206,150,.7)` |
| Warning | `rgba(244,190,89,.6)` | `#F6C86B` | `rgba(244,190,89,.7)` |
| Failed | `rgba(236,86,74,.62)` | `#FF7A6E` | `rgba(240,110,96,.75)` |
| File dropped | uses Transcribing purple | `#A99BF5` | `rgba(150,120,255,.7)` |

### Animations
- `voice` (recording, 1.5 s ease-in-out infinite, on the ambient bloom) — irregular
  opacity .5→1 with scale .96→1.06; it must feel like a level meter, not a metronome.
  Keyframes in the prototype: 0% .5/.96 · 11% .95/1.03 · 23% .62/.99 · 37% 1/1.06 ·
  49% .68/1 · 61% .92/1.03 · 74% .58/.98 · 87% .86/1.02 · 100% .5/.96.
- `rimlive` (recording, 1.5 s, on the fiber stripe) — opacity .45→1 on the same irregular beat.
- `rimsoft` (transcribing, 2.2 s) — fiber opacity .4 ⇄ .8.
- `latent` (all other states, 7 s; transcribing bloom 2.2 s) — opacity .5 ⇄ .85.
- `breathe` on the mark — scale 1 ⇄ 1.08 / opacity .85 ⇄ 1; 3.6 s idle, 1.9 s recording,
  1.1 s transcribing.
- Card entry `riseC`: opacity 0 → 1, translateY 10px → 0, .24 s ease.

---

## Screen 2 — The card (everything else)

One layout, reused for every message the app has to deliver.

**Scrim**: full-screen `rgba(36,31,56,.2)` + `backdrop-filter: blur(3px)`.
**Card**: `background: rgba(252,251,255,.98)`, `border-radius: 16px`,
`padding: 26px 24px 20px`, `box-shadow: 0 30px 70px rgba(40,28,90,.35)`, centred text.

Stack, top to bottom:
1. **Glyph tile** — 46 × 46, radius 14, background `rgba(74,56,166,.09)` (danger:
   `rgba(179,53,47,.1)`), glyph 19 px in `#4A38A6` (danger `#B3352F`).
2. **Title** — 14.5 px / 600.
3. **Body** — 12.5 px / 1.55, `rgba(36,31,56,.6)`, `text-wrap: pretty`, margin-top 7.
4. **Optional body block** (one of: destination list, permission row, key caps, recording
   list, toggle list) — margin-top 16, left-aligned.
5. **Buttons** — margin-top 20, `display:flex; gap:8`, each `flex:1`, radius 10,
   padding 10 px 0, 13 px / 500. Secondary: `rgba(36,31,56,.07)` on `#2c2350`.
   Primary: `#4A38A6` (danger `#B3352F`) on white.
6. **Optional dots** (first run) — 6 px circles, gap 6, active `#4A38A6`,
   inactive `rgba(36,31,56,.15)`.

### Card widths & copy

**First run** (5 cards, with dots)
1. 380 — `◍` "Splay records anything you can hear" / "One shortcut starts it. Your voice, a call,
   a video — it all becomes a Markdown file on this Mac. Nothing is uploaded, ever." → Continue
2. 380 — `●` "Splay needs the microphone" + permission row (Microphone · Required ·
   Not requested) → Ask macOS / Later
3. 400 — `▣` "And system audio, if you record calls" + permission row (Screen & system audio ·
   Optional · calls and video · Not requested) → Allow / Skip
4. 420 — `⌘` "Where should the text go?" + destination list → Use this
5. 380 — `⌥` "That is the whole app" + key caps `⌥` `Space` → Start recording

**Recent & settings** (2 cards, no dots)
- 480 — `▤` "Recent recordings" + list of five rows → Open folder / Close
- 420 — `◎` "Settings" + three toggles → Done / Quit Splay

**Alerts & handoffs** (5 cards, no dots)
- 330 — `⌫` "Delete this recording?" (danger) → Delete / Keep
- 340 — `■` "Stop recording?" → Stop and transcribe / Keep recording
- 380 — `●` "The microphone is switched off" (danger) + permission row (Denied)
  → Open System Settings / Later
- 390 — `▣` "Call audio will not be recorded" + permission row (Denied)
  → Open System Settings / Record me only
- 380 — `↺` "The speech model needs repairing" → Repair model / Not now

Exact body copy is in the `CARDS` object of the prototype's logic script.

### Body blocks
- **Destination list** — 4 rows, radius 12, padding 12/13, gap 7. Unselected
  `rgba(36,31,56,.04)` + `1px solid rgba(36,31,56,.08)`; selected `rgba(74,56,166,.09)` +
  `1.5px solid #4A38A6` and a right-hand "Default" tag in `#4A38A6`. Each row: 26 px glyph tile
  (white 75%, `#4A38A6`), name 12.5/500 `#2c2350`, sub 11 px `rgba(36,31,56,.5)`.
  Rows: A folder (~/Splay · one .md per recording) · Obsidian · Claude · Clipboard only.
- **Permission row** — radius 13, padding 13/15, tinted with the card tint; 32 px white tile,
  name 12.5/500, sub 11 px, state label 11.5/500 in the card colour.
- **Key caps** — `rgba(36,31,56,.06)`, radius 9, 14 px monospace, padding 10 px 14/20.
- **Recording list** — 5 rows, radius 11, padding 9/11; first row `rgba(74,56,166,.07)`, rest
  transparent. 52 px tabular time column (12 px `#2c2350` over 10.5 px `rgba(36,31,56,.42)`
  duration), title 12.5 px `rgba(36,31,56,.72)` truncated, then a 7 px dot with border
  `rgba(74,56,166,.4)` — hollow = mic only, filled `rgba(74,56,166,.4)` = mic + system.
  Footer rule + "~/Splay · 214 recordings · everything older is just files".
- **Toggle list** — 3 rows, radius 11, `rgba(36,31,56,.035)`, label 12.5 px; switch 38 × 22,
  radius 12, knob 16 px white with `0 1px 3px rgba(0,0,0,.2)`; on `#4A38A6`, off
  `rgba(36,31,56,.16)`. Rows: Record system audio too (on) · Launch at login (on) ·
  Play a sound when it starts (off). Footer: "This is the entire settings surface."

---

## Interactions & behaviour
- ⌥Space starts recording; pressing it again stops. No modes, no pre-flight choice.
- The island transitions Dormant → Ready (while the shortcut is held) → Recording →
  Transcribing → Done → Dormant. Copied is a brief substitution of the Done glyph
  (~1.2 s) before the island goes quiet.
- Dropping an audio file on the island goes straight to Transcribing.
- Warnings never open anything by themselves — the light turns amber and recording continues.
  Only if the user needs to act does a card appear.
- Failure keeps the audio, so nothing is ever recorded twice.
- Geometry changes should be animated (width/height/radius, ~.28 s ease); the light colour
  should cross-fade rather than snap.
- Accessibility permission is never requested — Splay does not type into other apps.

## State
`islandState` (dormant | ready | recording | transcribing | done | copied | warning | failed |
dropped), `level` (0–1, drives the light), `card` (nil | one of the card ids), `destination`,
and the three settings booleans.

## Design tokens
- Ink `#241f38`; secondary ink `#2c2350`; brand `#4A38A6`; accent `#A99BF5`.
- Danger `#B3352F` (card) / `#F0837A` (island glyph); warning `#F4BE59`.
- Island surface `#0B0813`; card surface `rgba(252,251,255,.98)`.
- Type: Inter Tight (400/500/600) for UI; Instrument Serif for the wordmark; ui-monospace
  for keys and file previews.
- Radii: 9 / 11 / 12 / 13 / 14 / 16 / 999.
- Spacing: 6 / 7 / 8 / 11 / 14 / 16 / 20 / 26.

## Assets
The Splay mark is the three-stroke wind glyph, `viewBox="180 180 640 660"`, three paths at
100% / 90% / 60% opacity — it is inline in the prototype; lift it from there as an SVG/PDF asset.
No other imagery.

## Files
- `Splay Island Fiber.dc.html` — the design (open in a browser; needs `support.js` beside it)
- `support.js` — runtime for the prototype only; not part of the product
