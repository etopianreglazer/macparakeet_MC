# Splay notch island

> Status: **HISTORICAL** — the lavender single-island direction, superseded by `splay-two-surface-rebuild.md`.

## Goal

Adopt Claude's dark, lavender, single-island direction without creating a second
window or changing capture semantics. The long-lived island remains the sole
user-facing surface.

## Screen/state coverage

| State | Existing baseline | Decision |
| --- | --- | --- |
| Idle/reveal/hover | pill + hover hint | On a built-in display with public notch geometry, use two coordinated panels: a tiny inert status-bar anchor behind the camera housing, plus a narrow popup-level visible companion whose top is exactly the physical screen top. The companion intentionally overlaps only the central menu-bar band, renders a lavender seam/halo, and owns a 180×56pt hover-only reveal zone. Other screens default to Bottom. |
| Recording / transcribing / done | existing pill lifecycle | Preserve them; use violet brand treatment only, retaining red failures and amber warnings. |
| Capture failure / recovery | explicit existing error state | Preserve explicit recovery/error; no success-like completion. |
| Home / Library / transcript detail | existing island routes | Preserve compact, same-panel routes and Markdown/Finder actions. |
| Settings | compact island settings | Add persistent Island position: Automatic, Notch, Bottom. |
| Setup/model/permissions/ready | existing setup route | Preserve all existing safe setup states. |
| External/non-notched display | current top layout | Default Bottom; manual Notch safely becomes Bottom because no public notch geometry exists. |

## Mockup gaps and decisions

Claude's mockup is a dictation-style listening/result concept and does not
specify meeting stop, capture-health failure, Library, detail/reveal, Settings,
model download, permission recovery, display choice, or external-display
behaviour. Existing Splay routes are retained as the functional baseline.
Bottom means a compact, menu-safe top-centre fallback beneath the menu bar,
matching the existing product's stable interaction geometry. Detection uses
public screen geometry (`safeAreaInsets`, auxiliary top areas, and built-in
display state); CPU generation is never used.

## Implementation / verification

1. ✅ Add deterministic placement resolver and focused geometry tests.
2. ✅ Bind placement to a persisted preference; Automatic resolves Notch only
   on supported built-in displays, with the existing Bottom fallback intact.
3. ✅ Keep a noninteractive status-bar hardware anchor separate from the
   visible popup-level companion. The companion has no artificial top inset,
   uses the physical display top (the deliberate central menu-bar overlap),
   has a mouse-transparent lavender seam/halo/glints and card-only hit testing
   when expanded. It rejoins all Spaces and restores after accessory-policy
   hiding without becoming key.
4. ✅ `swift test --filter IslandPlacementTests` passed (2/2). A signed local
   build was installed at `/Applications/Splay.app` and launched through
   LaunchServices as PID 42781. At 57 seconds it remained alive and WindowServer
   reported the on-screen companion at `X=604, Y=0, W=520, H=460`, level 101:
   its top is the physical display top, not `visibleFrame.maxY`.
   The installed Info.plist contains
   `NSPrefersDisplaySafeAreaCompatibilityMode=false`; `codesign --verify --deep
   --strict` passed. No commit/push.
