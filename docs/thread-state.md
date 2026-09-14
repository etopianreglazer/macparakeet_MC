# Thread State — Splay (modified MacParakeet-MC fork)

> **What this is:** a handover of *where we left things*, written for the next session to
> resume cold. It is **not** a briefing (the "what's planned" lives in
> `docs/fork-product-model.md`) and **not** a build plan (`docs/plans/fn-rework.md`). This is
> the "you are here" pin.
>
> **Last updated:** 2026-09-13 **thread 12 (cont.) — SLICE 2 DEVICE-FREE HALF DONE ON BRANCH `ios/utility-layer`: AVFoundation converter, iOS audio session, and the iOS app (app + widget) COMPILE FOR iOS; NOTHING RUN ON A DEVICE YET.**
> Branch `ios/utility-layer` off `main` (owner asked for a branch; main is untouched after slice 1). Commits:
> `d32c6958` AVFoundation converter (+7 tests); then the iOS audio session + the `ios/Splay/` app skeleton (see
> `docs/plans/splay-ios-utility-layer.md` § Slice 2 log for the full shape). Owner decisions this stretch: **design
> v5** (mock at claude.ai artifact "Splay Island for iPhone": no light, Now-Playing idiom, 84 pt expanded row, Record/
> Pause/Resume only, HIG sizes) is what `SplayLiveActivity.swift` implements; **clipboard always** on save;
> **auto-paste = a paste-only keyboard extension later (slice 6)** because iOS lets only keyboards insert text.
> Vet ran on each unit (converter clean; audio session had an unbalanced activate/deactivate — fixed, deactivate only
> in `stopEngine()` + on failed start; the app skeleton got 13 findings, all fixed: on-disk DB instead of the in-memory
> test initializer, the Mac's aliveness algorithm for *Input dead* + `mode == .stopped` as a hard failure that finalizes
> and releases the lease, `finishTranscriptionAttempt` on every failure path, no orphaned Live Activity on restart
> (+ lingering ones ended at launch), Retry only when a stopped session exists (`ContentState.canRetry`), Pause accepted
> in Input dead, `placeholder` rename, one title/tint mapping, Recents errors surfaced, and the iPhone scripts share
> `scripts/dev/lib/iphone_common.sh` with a real exit status and JSON device discovery). Vet was **not** re-run on
> that follow-through (owner asked not to restart it); worth one pass next thread. ⚠️ **Still blocked on the owner for anything on-device:** Apple ID in Xcode ▸
> Settings ▸ Accounts, phone on a cable. Then: `scripts/dev/install_iphone_bench.sh` (numbers), then
> `scripts/dev/install_iphone.sh` (the app; verify the Control-started recording, the Live Activity, the clipboard).
>
> **Prior block (slice 1):** **thread 12 — iPHONE PORT, SLICE 1: SplayCore COMPILES FOR iOS; BENCH HARNESS BUILT, NOT YET RUN ON DEVICE.**
> Owner decisions this thread (recorded in `docs/plans/splay-ios-utility-layer.md`, now ACTIVE): the phone
> is the priority; **no app you ever open** — Action Button (Control) primary, Back Tap (Shortcut) secondary,
> a Now-Playing-style **Live Activity in the Dynamic Island** as the indicator with one Stop button;
> **Parakeet v3 first, verbatim, no clean-up ever in capture** (names/brands parked as an editing decision);
> no keyboard (iOS forbids mic in keyboard extensions); no cloud. Platform facts verified: `AudioRecordingIntent`
> (iOS 18) lets a Control start recording without foregrounding *if* a Live Activity is started and kept alive;
> Back Tap→Shortcut may need a `ForegroundContinuableIntent` flash — verify on device. Dev loop: direct Xcode
> install at the desk, TestFlight for the remote loop (Mac stays home; owner drives via Remote Control).
> (1) **`Package.swift` declares `.iOS("18.0")`** (string form: tools-version 5.9 predates `.v18`).
> (2) **`SplayCore` builds for iOS** via both `swift build --target SplayCore --triple arm64-apple-ios18.0 --sdk
> $(xcrun --sdk iphoneos --show-sdk-path)` and `xcodebuild -scheme SplayCore -destination generic/platform=iOS`
> (xcodebuild works on this machine again). GRDB/FluidAudio/WhisperKit compile for iOS unchanged. Everything
> macOS-only is **gated `#if os(macOS)`, never forked** — whole-file: `SystemAudioStream`, `AudioDeviceManager`
> (`normalizedUID` + iOS `AudioDeviceID` typealias moved to new `Audio/AudioDevicePortable.swift`),
> `PasteShortcutKeyResolver`, `ClipboardService`, `LaunchAtLoginService`, `AccessibilityService`,
> `SystemMediaController`, `BinaryBootstrap`, `ChildProcessWaiter`; surgical: `AudioCaptureDiagnostics`
> (labels read `session` on iOS), `MicrophoneEnginePlatform` (HAL default-input listener no-op on iOS; the
> default explicit-device setter is now resolved inside the init — `inputDeviceSetter: InputDeviceSetter? = nil`
> — because a public init's default arg can't name an internal symbol), `MeetingAudioCaptureService`
> (system-audio factory throws `unsupportedPlatform` on iOS), `PermissionService` (mic both; screen/AX/deep-links
> macOS), `ExportService` (PDF/DOCX macOS; txt/md/srt/vtt/json portable), `ThumbnailCacheService` (frame
> extraction throws on iOS), `AudioFileConverter` (**`convert`/`mixToM4A` throw on iOS** — slice 2 needs an
> AVFoundation converter before the first end-to-end recording, since the meeting pipeline calls `mixToM4A`
> at stop). `SplayViewModels` stays macOS-only by decision (Mac card/panel logic; the phone gets its own VMs).
> `Sources/SplayCore/Audio/README.md` has a new § Platforms listing all of this.
> (3) **Bench harness `ios/SplayBench/`** (XcodeGen `project.yml` + one SwiftUI file + a 73 s `say`-synthesised
> 16 kHz WAV fixture; `brew install xcodegen` was done this thread): runs Parakeet v3 through `STTClient`,
> prints per-run RTF, a 10-run sustained RTF, `phys_footprint`, thermal state to stdout and a JSON in Documents.
> `scripts/dev/install_iphone_bench.sh` = generate → Release build → `devicectl` install → launch with console
> streaming. **Compiles and links for iOS in Release (25 MB .app, unsigned).** ⚠️ **Device install is blocked on
> the owner:** Xcode has no Apple ID account for team `W72K456DZC` (the Mac loop signs with the cert directly and
> never needed one), so no iOS provisioning profile can be generated — add the account in Xcode ▸ Settings ▸
> Accounts, then run the script with the phone connected + unlocked. The phone (`Mathews iPhone`, iPhone 16 Pro,
> iOS 26.6.1) was paired but `unavailable` during this thread.
> **Validation:** macOS `swift build` green; full suite 1760 XCTest + 16 swift-testing, the **same 5 known
> environmental failures** (AppPaths + 3× SettingsViewModel + AX-gated AppHotkeyCoordinator), zero new.
>
> ### ⭐ WHAT'S NEXT (thread 13)
> 1. **Owner:** Apple ID in Xcode Accounts; phone on a cable. Run `scripts/dev/install_iphone_bench.sh` (slice 1
>    exit numbers), then `scripts/dev/install_iphone.sh` and press the Action Button (assign Splay's Control first).
> 2. **On-device verification list** (slice 2 exit): Control-started recording with the app never visible; island
>    compact/expanded per v5; Pause/Resume; Action Button again → Finishing → Saved; `.md` + audio in Files; text on
>    the clipboard; Back Tap → Shortcut path (may need `ForegroundContinuableIntent`); first-run model download UX.
> 3. Then slice 3/4 polish per the plan; slice 6 = paste-only keyboard (auto-paste). Mac list from thread 11 stands.
> Branch is local; nothing pushed (owner pushes).
> Nothing is pushed (owner pushes).
>
> **Last updated (prior):** 2026-08-21 **thread 11 — DOCS REWRITE + POLISH: DONE; RELEASE BUILD: NOTARIZED 0.1.0 CUT (not published).**
> (1) **`CLAUDE.md` / `AGENTS.md` rewritten slim for Splay** (commit `eb757513`): two-surface recorder,
> 4 SwiftPM targets, 3 remaining `AppFeatures` flags, the binding-vs-superseded ADR list, the kept
> identifiers, the non-obvious rules (dead≠silent, island never key, STT via scheduler, licensing
> plumbing stays), the 5-known-failures test baseline, `install_local.sh` as the dev loop. README fixed
> (file drop = **menu bar icon**, not the island; no YouTube/AI-provider mention; default transcript
> folder named). (2) **Polish:** 13 stale `plans/active/…`/`docs/telemetry.md`/`integrations/` comment
> pointers reworded to "upstream MacParakeet plan …" (those files are not in this repo);
> `AppFeatures` points at `docs/plans/fn-rework.md`; **TEMP `f125f21d` `post_present` snapshot stripped**
> from `SplayCardController` (the `src=` click tags stay); `docs/distribution.md` → HISTORICAL;
> `docs/launch-checklist.md` ticked for everything threads 8–10 landed. **`meetingVadLiveChunkingEnabled`
> left ON by decision:** it only affects live-preview chunking, has a fixed-chunker fallback, and the
> final transcript is unaffected — nothing to gain by cutting it. (3) **Launch gate §A2:** **`dist/Splay.dmg` is a notarized, stapled 0.1.0** — version `0.1.0`,
> build `20260822010535`, commit `eb757513`, built via `build_app_bundle.sh` (xcodebuild, resource bundles
> present) + `sign_notarize.sh`; app + DMG both `spctl` → `accepted / source=Notarized Developer ID`;
> bundle sweep: the only upstream string left is the LICENSE attribution. **DMG = 44 MB** (was 136 MB).
> Sparkle: `sparkle:edSignature="35aL+xrnFMvPhFPKCpk/6VQvKRPBPZ/d5GXUDWG7NjNiE9po0ISCN+1B7uGwwVmBG28KBLTjq54BzIm4wvh+Bg=="
> length="44285355"`, sha256 `f2cebefc…4087` — **this exact file must be the one uploaded** (re-signing
> after any rebuild). Publish steps (`docs/releasing.md` 3.6–3.7) are outward-facing and left to the owner.
> **Validation:** build green; full suite 1760 tests / the same 5 known environmental failures, zero new.
>
> ### ⭐ WHAT'S NEXT (thread 12)
> 1. **Second-Mac test** (`docs/launch-checklist.md` §C5) — the one check only the owner can run:
>    copy `dist/Splay.dmg` to another Mac / fresh user, open without right-click bypass, record once.
> 2. **§C4 visual pass** — glow nudges + the talk-glow live verdict (open since thread 6), dialled in
>    the live HTML tuner, then ported to `SplayGlowTuning` / `SplayTalkGlowTuning`.
> 3. **Owner-only pre-publish items:** back up the Sparkle private key + the Developer ID `.p12`
>    (`docs/releasing.md` Part 4); stand up GitHub Pages for the appcast; rename/detach the repo;
>    decide `--draft` vs public for `gh release create v0.1.0`. **Nothing is pushed** (46 commits ahead).
> 4. Optional: the old `dist/MacParakeet*.app` / `.dSYM` leftovers are untracked junk — safe to delete.
>
> **Last updated (prior):** 2026-08-21 **thread 10 — IN-APP LLM REMOVED: DONE (3 commits, not pushed). ⭐ NEXT
> THREAD = CLAUDE.md / AGENTS.md / README rewrite (now urgent — see below), then the launch gate.**
> This thread: (1) **committed thread 9's uncommitted main-window retirement** as `5995519d` (verified
> build + suite first). (2) **The LLM cut, `4d2e54b4`** (−42,001 lines): meeting **Ask tab removed**
> (panel keeps Notes + Transcript; live notepad still persists onto the saved transcription); dictation/
> transcription **AI-clean removed** (DictationService + TranscriptionService always run the
> deterministic pipeline; formatter notifications, the overlay `.formatting` beat, and the aiFormatter
> defaults keys are gone); **Transforms deleted entirely** (coordinator, hotkey registry/alias/adapter,
> executor, views, VMs, menu items, the `transformsEnabled` flag); **LLM machinery deleted**
> (`Services/LLM/`, AIFormatter, prompt/chat/quick-prompt/transform-history/llm-run models + repos,
> their VMs, the vestigial SettingsTab/SettingsRootViewModel/SettingsSearchIndex/SettingsTabBar layer —
> the live settings card in `Views/Island/SplayCards.swift` needs only `SettingsViewModel`).
> **DB sub-decision taken per the handoff's recommendation (owner not present): tables left DORMANT** —
> no migration, no data loss; built-in prompt/quick-prompt startup reconciliation removed; the minimal
> model set historic migrations still need (`Prompt`, `KeyboardShortcut`, `ChatConversation`, new
> extracted `ChatMessage.swift`) is kept as data-layer-only. ⚠️ If the owner wants a clean schema
> instead, that's a new drop-with-migration task. Licensing/entitlement plumbing untouched.
> ADRs 011/013/018/020/022 headers marked **SUPERSEDED for Splay**.
> (3) **Dead-view sweep + Vet follow-through, `a6ed3a2e`** (−9,679 lines): agentic Vet on the LLM cut
> returned 7 findings (all dead-wiring/docs, zero correctness bugs), all fixed: deleted the last two
> Transforms services (`SelectionCaptureService`/`SelectionReplacementService` — ADR-022 names them),
> the History + Vocabulary view folders and their VMs (+`VocabularyImportExportService`/`VocabularyBundle`;
> the word/snippet **repos and the dictation pipeline that consumes them are untouched** — vocabulary
> editing UI was already unreachable), 12 orphaned components (ModelSelector, MarkdownContent, FlowLayout,
> badges, scrubber/player, mandala, gallery…; **ParticleSystem stays** — onboarding uses `ParticleField`),
> dead wiring (write-only `liveMeetingCoordinator`, no-op `onRecoveredTranscriptionsChanged`, poster-less
> `.macParakeetOpenSettings`, `onHistoryReload`), and the stale Database/TextProcessing subsystem READMEs.
> **Validation:** every commit build-green; full suite after each = the **same 5 known environmental
> fork-debt failures** (AppPaths + 3× SettingsViewModel pre-`-MC`-namespace asserts + AX-gated
> AppHotkeyCoordinator), zero new. Suite is now **1760 XCTest + 16 swift-testing** (was 2548 — deleted
> tests went with their subjects).
>
> ### ⭐ WHAT'S NEXT (thread 11)
> 1. **CLAUDE.md / AGENTS.md / README.md rewrite** (owner already chose "rewrite slim", thread 8) — now
>    *actively wrong*, not just stale: CLAUDE.md still documents Transforms as enabled, the 3-modes+
>    Transforms model, `AppFeatures.transformsEnabled`, `Views/Transforms/`, the CLI, and dozens of
>    deleted paths. Vet flagged this as its highest-severity finding. Rewrite for the two-surface
>    recorder.
> 2. **Launch gate** (`docs/launch-checklist.md` §A2/§C): build, sign, notarize, second-Mac test —
>    plus the deferred glow nudges / talk-glow live verdict (§C4).
> 3. Minor deferred polish: stale `plans/active/…`/`docs/research/…` comment pointers in source;
>    `meetingVadLiveChunkingEnabled` left ON (not in any cut list).
>
> **Last updated (prior):** 2026-08-19 **thread 9 — MAIN-WINDOW RETIREMENT: DONE (uncommitted). ⭐ NEXT THREAD =
> REMOVE IN-APP LLM (owner decided; scope + plan in the ⭐⭐ block below).** The one
> high-risk piece from thread 8's WHAT'S-LEFT #1 is cut. Key insight that made it low *behavioral* risk:
> the main window was **already unreachable** — `AppWindowCoordinator.openMainWindow()` had a
> `guard !AppFeatures.islandReplacesDictationPill else { return }`, so every one of the ~13 call sites was
> already a **no-op** at runtime. So this was a dead-code + dead-menu removal, not a live-surface change.
> **What landed:** (1) re-routed the call sites — onboarding's "Open Splay" now just closes (removed
> `onOpenMainApp` through OnboardingFlowView→WindowController→Coordinator); every "Open Settings" (settings
> observer, transforms `onLLMProviderRequired`, the 3 hotkey/entitlement `NSAlert`s) → `presentSettingsCard()`;
> recovered + finished meetings save (`presentCompletedTranscription(autoSave:true)`) and surface in the
> **recents card** instead of a window (dropped the paired `navigateToTranscription`/`openMainWindow`);
> `applicationShouldHandleReopen` → `presentRecentCard()`. (2) **Menus rebuilt** in `MenuBarCoordinator`:
> deleted the whole **Go** menu, `Window ▸ Show Splay`, `Capture ▸ New Transcription`, `Capture ▸ New
> Transform`, and all their selectors/closures (`onOpenMainWindow`, `onNavigate`, `onNewTranscription`,
> `onCreateTransform`, `navigate(to:)`, `show*`, `SidebarItem` wiring); stripped the `onOpenMainWindow()`
> tails from `transcribeFileFlow`/`handleDroppedFiles`. (3) **`AppWindowCoordinator` slimmed** from a
> 17-view-model window factory to just `applyActivationPolicyFromSettings()` (accessory/regular) + the Dock
> menu (Open→recents card, Settings→settings card, Quit); deleted the Slice-4 overlay path with it. (4)
> **Deleted files:** `MainWindowView.swift`, `SettingsView.swift`, `TranscribeView.swift`,
> `MainWindowState.swift`, `IslandOverlayController.swift`, and 3 now-subjectless tests
> (`MainWindowStateTests`, `SettingsHotkeyConflictMessageTests`, `SettingsDictationHotkeyDisplayTests` —
> the latter two only tested `SettingsView`'s hotkey-picker helper enums, which the card has no equivalent
> of). Relocated the still-live `extension Notification.Name { transformsBindingsChanged /
> transformHistoryChanged }` out of the deleted `MainWindowState.swift` into `TransformsCoordinator.swift`.
> **★ THE LAST UPSTREAM LINK IS GONE:** `grep -rn "macparakeet\.com\|moona3k" --include=*.swift Sources/`
> is now **0** (was 1 — it lived in the deleted `SettingsView.swift:2407`). **Validation:** `swift build`
> green; full suite **2548 XCTest + 16 swift-testing, 6 failures = the known environmental fork-debt only**
 (4× `AppPaths`/`SettingsViewModel` pre-`-MC`-namespace asserts + AX-gated `AppHotkeyCoordinator`), **zero
> new**; the old `MainWindowState` known-failure is gone with its test. **Uncommitted, not pushed.**
> **Agentic Vet run — 7 findings, all dead-wiring/naming/doc (no correctness bugs); 6 fixed this thread:**
> (a) removed the now-always-false `isHotkeyRecorderActive` flag + its `isHotkeyRecordingActive` callback +
> the startup suspend gate + the now-callerless `TransformsCoordinator.suspendHotkeys/resumeHotkeys`
> (the card has no hotkey recorder, so this whole suspend-taps-while-rebinding path was dead); (b) dropped
> the always-false `originatesFromWindow:` param from `toggleMeetingRecording` and deleted the callerless
> `startMeetingRecordingFromWorkspace()`; (c) **renamed `AppWindowCoordinator` → `AppActivationCoordinator`**
> (file + class + the `windowCoordinator`→`activationCoordinator` var) — it coordinates no window now;
> (d) fixed the relocated `.transformsBindingsChanged`/`.transformHistoryChanged` doc comments + the
> `SettingsSearchIndex` maintenance note that pointed at the deleted `SettingsView.swift`. Build + suite
> re-green after the cleanup.
> **Vet finding #2 — RESOLVED into an owner decision (see ⭐ below):** the cut surfaced that there is now
> **no reachable LLM/AI-provider config surface** in Splay (`LLMSettingsView(` is instantiated nowhere — it
> lived only in the deleted `SettingsView`; the settings card has no AI section; already unreachable pre-cut,
> the cut just made it explicit). Owner's call: **Splay does not need an LLM** — so the answer is *remove*, not
> *add a setup section*. That expands into the next thread's task.
>
> ### ⭐⭐ NEXT THREAD = REMOVE IN-APP LLM (owner decision, this thread)
> **Product line (owner, verbatim intent):** Splay's job is **record / dictate → clean transcript**; the user
> then analyzes that with **their own** LLM. Splay must **not** run its own LLM pass on the transcript — "why
> parse something twice and play chinese whispers." So: **strip all in-app LLM from Splay.** This is a real,
> multi-subsystem cut — comparable in size to the main-window retirement — so **scope + confirm the DB call
> before deleting** (same discipline as the window). **NOT started.**
>
> **The good news — most LLM *UI* is already dead** (0 instantiations, deleted with the main window; the
> file-delete step is mostly a sweep): `TranscriptResultView`, `TranscriptChatView`, `PromptsView`,
> `PromptResultsView`, `LLMSettingsView`, `TransformsView`.
>
> **Still LIVE — the two things whose removal actually changes behavior:**
> 1. **Meeting Ask + memo-steered summaries.** `MeetingRecordingFlowCoordinator.swift:439` shows
>    `MeetingRecordingPanelController` (Notes / Transcript / **Ask**) during recording; Ask + summaries call the
>    LLM (ADR-018/020). **Remove the Ask tab + summary generation; KEEP Notes + live Transcript** (both
>    non-LLM) — that leaves exactly the record→transcript workflow.
> 2. **Dictation "AI clean" mode.** `TranscriptionService` (`shouldUseAIFormatter`/`aiFormatterPromptTemplate`/
>    `processingMode`, default off/`.raw`) runs `AIFormatter` (`Sources/SplayCore/TextProcessing/AIFormatter.swift`)
>    as an opt-in LLM cleanup on dictated text. **Remove it → dictation is always the raw/deterministic pipeline
>    (ADR-004).** Wired via `DictationFlowCoordinator` + `AppEnvironment`.
>
> **Machinery to sweep after the two above:** `LLMService` (`Sources/SplayCore/Services/LLM/`),
> `LLMSettingsViewModel` + `LLMSettingsDraft`, the provider config store (`llmConfigStore`/`llmService` — ~38+10
> refs), `AIFormatter`, and the now-orphaned prompt/quick-prompt/chat view models + repos. Plus the vestigial
> `SettingsTab` / `SettingsRootViewModel` / `SettingsSearchIndex` / `SettingsTabBar` / `SettingsSearchResultsList`
> and the Ask pane's "Set up AI" deep-link (`LiveAskPaneView.swift:290` posts `SettingsTab.ai`; producer side is
> live + test-covered by `AppSettingsObserverCoordinatorTests` — update/delete that test with it).
>
> **Owner decisions captured (this thread):** (1) meeting Ask + summaries → **REMOVE** (panel keeps Notes +
> Transcript). (2) dictation AI-clean → **REMOVE** (always raw). (3) chat/prompt/quick-prompt **DB tables** →
> **recommendation: leave DORMANT** (remove code + UI, no migration, no data loss — same pattern as the kept
> YouTube metadata columns); drop-with-migration only if the owner wants a clean schema — **CONFIRM this one at
> kickoff** (it's the only open sub-decision). ⚠️ Licensing/entitlement plumbing stays (CLAUDE.md rule) —
> LLM removal is orthogonal to it.
> **ADRs to update / mark superseded-for-Splay after the cut:** 011 (LLM providers), 013 (prompt library /
> multi-summary), 018 (live Ask), 020 (memo summaries), 022 (Transforms — already hidden). Note AI-clean removal
> in the dictation/text-processing story too.
> **Fold in the dead-view sweep:** the LLM cut and the orphaned-sub-view sweep (Dictations, Vocabulary, the full
> Library grid, Meetings browse, History panels, the Settings sub-panels + the search-index trio above) overlap
> heavily — do them together.
>
> **State at handoff:** this thread's work (main-window retirement + Vet cleanup) is **UNCOMMITTED, not pushed**;
> build + full suite green (6 known-environmental failures only). LLM removal **not started**. `swift test`
> baseline is now **2548 XCTest + 16 swift-testing / 6 failures** (was 3166/8 — dropped because deleted tests +
> the retired MainWindowState failure).
>
> **Last updated (prior):** 2026-08-19 **thread 8 — THE BIG CLEAN-UP: mostly DONE.** 10 cleanup commits
> landed (all build + full-suite green = the known-7 environmental failures only; **40 commits ahead
> of `origin/main`, still NOT pushed**). Removed, each its own commit: upstream junk assets + About
> reword; repointed the 4 surviving identity links → `github.com/etopianreglazer/splay`; **dropped the
> `macparakeet-cli` target** (−29 MB); **removed telemetry reporting** (networking class + upstream URL
> deleted, No-Op wired; CrashReporter rides the same seam so it's inert too); **removed Feedback**
> (the worst upstream endpoint); **removed Discover** (last two upstream endpoints — a shared
> `MerkabaShape` was rescued from its folder to `Views/Components/`); **removed YouTube entirely**
> (DB migration `v0.21` remaps old `sourceType='youtube'` rows → `file` before the enum case is
> deleted; `node`+`yt-dlp` bundling gone → ~half the download); **removed calendar auto-start**
> (ADR-017; the misnamed `CalendarNotificationAuthorization` was the generic notification helper —
> moved to `Services/System/NotificationAuthorization.swift`, transcription banner still works);
> **pruned upstream docs** (kept `spec/adr/` only; moved the 6 Splay plans to `docs/plans/`; dropped
> `plans/ integrations/ marketing/ brand-assets/ docs/research|agents|audits|blog|planning` + 8 upstream
> `docs/*.md`; −48,776 lines); **hid Transforms** (`AppFeatures.transformsEnabled=false`, code dormant).
> **Upstream sweep** `grep -rn "macparakeet\.com\|moona3k" --include=*.swift Sources/` is down from 13
> to **1** — only `SettingsView.swift:2407` (telemetry-docs link), which dies with the main-window Settings.
>
> ### ⭐ WHAT'S LEFT (start here)
> 1. **✅ DONE (thread 9) — Main-window retirement.** See the thread-9 block at the very top for the full
>    scope. The last upstream link went with the deleted `SettingsView.swift`. What now remains is the
>    optional **dead-view sweep** of the orphaned sub-views SwiftPM still compiles.
> 2. **`CLAUDE.md` / `AGENTS.md` rewrite** for Splay (owner chose "rewrite slim") — both still describe
>    MacParakeet (3 modes, Transforms, calendar, the CLI, the 9-item nav). Now also reference many
>    now-deleted `spec/`, `plans/`, `docs/` paths.
> 3. **Minor:** ~24 stale `plans/active/…md` / `docs/research/…` *comment* pointers left in source
>    (non-functional; deferred polish). `meetingVadLiveChunkingEnabled` left ON (not in the cut list).
>    Empty `Sources/SplayCore/Calendar/` dir may linger (git ignores empty dirs).
> 4. Then the launch gate proper (`docs/launch-checklist.md` §A2/§C: build, sign, notarize, second-Mac
>    test) — unchanged from before.
>
> **Owner decisions captured this thread:** YouTube→remove+migrate; CLI→drop; spec/plans→adr-only;
> CLAUDE/AGENTS→rewrite slim; Transforms→hide; brand-assets→drop; docs/research→drop; calendar→remove.
> The `NotificationAuthorization` move + the `v0.21` migration + keeping the youtube metadata columns
> are the load-bearing safety calls. **Not pushed; owner has not asked to push.**
>
> **Last updated (prior):** 2026-08-19 **thread 7d/7e** — ⭐ **NEXT THREAD = THE BIG CLEAN-UP.** The menu-reopen
> bug is **fixed and user-confirmed live** ("Yeeees, it worked"). Launch prep is done as far as it can go
> without cutting things. **29 commits ahead of `origin/main`, still NOT pushed.**
>
> ## What the next thread is for
>
> **Cut the junk out of the app.** This is `plans/active/splay-two-surface-rebuild.md` **Phase 6**, plus
> everything the publish audit turned up. Three motivations that all point the same way:
> (1) only the two surfaces should exist; (2) **half the 136 MB download is YouTube support**; (3) most
> remaining **upstream-infrastructure pointers die with the features that use them**.
> The authoritative work lists are **`docs/launch-checklist.md` §B + §A6** and
> **`docs/publish-inventory.md`**. Read both before starting — they are precise and grounded, not
> aspirational.
>
> ### The cut list, concretely
>
> **Code / surfaces (Phase 6):**
> - `AppWindowCoordinator.openMainWindow()` / `openMainWindowToSettings(tab:)` — **10+ live call sites**
>   across `AppDelegate` + `MenuBarCoordinator`. Re-route to cards or delete. Then retire the main window.
> - The `Go` menu still lists Transcribe · Library · Dictations · Meetings · Vocabulary · Transforms ·
>   Feedback · Settings…; `Capture` still offers New Transcription · Start Dictation · File Transcription ·
>   Record Meeting · Create Transform; `Window` still has *Show Splay*. Rebuild menus for two surfaces.
> - Dead Slice-4 overlay path: `IslandOverlayController`, `openSettingsOverlay`, `openLibraryOverlay` —
>   left in place *specifically for Phase 6 to delete*.
> - Feature flags all still `true`: `meetingRecordingEnabled`, `calendarEnabled`, `transformsEnabled`,
>   `meetingVadLiveChunkingEnabled`, `islandReplacesDictationPill`.
> - ⚠️ **Hide before deleting.** `CLAUDE.md` forbids removing licensing/entitlement plumbing and
>   meeting-recovery artifacts as "dead code" without explicit owner sign-off.
>
> **Bundled junk (verified present in the notarized artifact):**
> - 🚨 `Sources/Splay/Resources/voices/altman-v-altman-complaint-2025-01-06.pdf` — **657 KB PDF of an
>   unrelated court complaint, referenced by no code**, shipping to every user since upstream. Delete the
>   whole `voices/` folder. Owner has not yet said why it is there — ask, then delete.
> - `menubar-icon@2x.png` (unreferenced); `discover-fallback.json` + `parakeet-mark.png` (die with Discover).
> - `node` **113 MB** + `yt-dlp` **36 MB** = YouTube only. Cutting YouTube roughly **halves** the download
>   (136 MB → ~70 MB). `ffmpeg` 63 MB stays (file/video import). `macparakeet-cli` 29 MB — **open question:
>   does Splay ship a CLI at all?** Upstream treats it as a public contract; Splay has no stated CLI audience.
>
> **Upstream infrastructure still in shipping code (checklist §A6) — 5 endpoints, 7 links:**
> - 🚨 `FeedbackService` → `macparakeet.com/api`: the in-app feedback form posts the user's message,
>   optional **email** and screenshot to upstream's function, which files a **GitHub Issue on Daniel Moon's
>   repo**. Worst of the set. Remove or repoint.
> - `TelemetryService` → `macparakeet.com/api` (already defaulted **opt-in/off** this thread; endpoint unchanged).
> - `DiscoverService` + `DiscoverThoughtsService` → upstream (Discover is cut).
> - Help menu → `macparakeet.com`; 7 links to `github.com/moona3k/macparakeet` incl. `FeedbackView`'s
>   "Issues" link and two CLI help strings.
> - **Re-run before release:** `grep -rn "macparakeet\.com\|moona3k" --include="*.swift" Sources/`
>
> ### Open decisions the owner has NOT answered (ask early, they gate real work)
> 1. `spec/` (38) + `plans/` (81) + `integrations/` + `marketing/` — **125 of the repo's 166 markdown files
>    are upstream's**, describing in prescriptive present tense an app Splay is cutting apart.
>    *Recommendation: keep `spec/adr/` only; drop the rest; move `plans/active/splay-*.md` into `docs/`.*
> 2. `docs/research/` (11 files: competitor reverse-engineering, WisprFlow deep dives) — *recommend exclude*.
> 3. `CLAUDE.md` / `AGENTS.md` — rewrite for Splay, or keep private?
> 4. `brand-assets/` — MacParakeet's parakeet marks + coral palette. Replace or exclude?
> 5. About card still says *"a personal fork of MacParakeet"* — reword to match README/CREDITS?
> 6. Delete `Resources/voices/`? (agent would, absent a reason)
> 7. Does Splay ship `macparakeet-cli`?
>
> ## What got DONE this thread (all committed, none pushed)
>
> **1. The menu-reopen bug — fixed, live-confirmed (`59101f91`).** Root cause was *not* exotic: the island
> had exactly **one** working click path — the **global** monitor — and AppKit never reports an app's own
> events to a global monitor. Proof from the log: `monitor_rejected src=local` **0 times** in 1.4 MB while
> `src=global` 35 times, and **all 14** island clicks were followed by `present … app_active=false`. Zero
> island clicks had *ever* succeeded while Splay was active. `present` calls `NSApp.activate`; the Close
> button leaves it active; the island went dead. "Once per activation" was literally "once per *de*activation."
> Fix = (a) `.nonactivatingPanel` on `IslandPanel` (it was the lone `.borderless`-only panel; every sibling
> floating panel already had it), (b) the local monitor made real — screen-space resolution, accepts
> window-less own-app clicks, logs its declines, (c) `SplayCardController.yieldActivationIfIdle` hands the
> foreground back after teardown. `dispatchClick` now logs `src=local|global|mouseDown`. **Live test passed.**
>
> **2. Apple release setup — COMPLETE.** Developer ID Application cert created via Xcode → Settings →
> Accounts → Manage Certificates (no manual CSR needed with full Xcode). `Developer ID Application: Mathew
> Cleveland (76K8473JHR)`, **expires 2027-02-01** (short — likely pinned to membership renewal; timestamped
> signatures survive expiry). notarytool keychain profile **`splay`** stored and authenticated.
>
> **3. 🏆 First notarized build exists and passed.** Dry run `0.0.1` build `20260819211955`:
> `spctl` → `accepted / source=Notarized Developer ID` for **both app and DMG**, tickets stapled, chain to
> Apple Root CA, hardened runtime on, every nested binary (Sparkle XPC, yt-dlp, ffmpeg, node, CLI) cleared.
> **The release pipeline is proven end to end.** `dist/Splay.dmg` = 136 MB.
> ⚠️ **Second-Mac test still outstanding** — the one check neither agent nor owner has run.
>
> **4. Killed the Sparkle footgun (`A1`).** The bundle shipped `SUFeedURL=macparakeet.com/appcast.xml` +
> upstream's `SUPublicEDKey` (whose private half we never had) with auto-checks on; owner's defaults showed
> `SULastCheckTime` and a stored update-alert frame — it had already offered an update that would have
> replaced Splay.app with MacParakeet.dmg. Generated **Splay's own EdDSA keypair**
> (`UjG8RmU9eOGL2ZNFdfc72QUhFH5z6KgYWTYBgmRJ6no=`, private half in login keychain, service
> `https://sparkle-project.org` / account `ed25519`), pointed the feed at
> `https://etopianreglazer.github.io/splay/appcast.xml`, cleared the stale defaults.
> ⚠️ **The private key is backed up nowhere. Losing it = no existing install can ever update.**
> ⚠️ `SparkleUpdateGuard` was never protecting us — it only blocks versions literally `0.0.0`/`dev`/empty/`pdx`.
>
> **5. Identity + legal.** `LICENSE` now carries Splay's copyright **alongside** Daniel Moon's with a dated
> derivation statement (GPL-3.0 §5(a)). `README.md` rewritten as Splay's own product (original archived at
> `docs/README-macparakeet-original.md`). **`CREDITS.md`** written — the thank-you letter, MacParakeet first
> and at length, plus Talkify (dead-≠-silent) and DynamicNotchKit (blur-into-focus).
> `THIRD_PARTY_LICENSES.md` **verified accurate** against all 11 `Package.resolved` deps.
>
> **6. New docs (read these first next thread):** `docs/launch-checklist.md` (the "r2launch" gate),
> `docs/releasing.md` (first-release mechanics + the `errSecInternalComponent` trap),
> `docs/publish-inventory.md` (every asset/doc classified SHIP/REWRITE/HISTORICAL/EXCLUDE).
>
> ## Gotchas learned this thread
> - **`errSecInternalComponent` when signing** = keychain ACL wants interactive confirmation and the process
>   is backgrounded. Identical command works in foreground. Fixed permanently by the owner running
>   `security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db`
>   (no `-k`, so the password stays out of history). **Signing now works backgrounded.**
> - **The dev install and the release build load resources differently.** `install_local.sh` uses
>   `BUILD_SYSTEM=swiftpm`, which emits **no** SwiftPM resource bundles — `/Applications/Splay.app` has no
>   `Splay_Splay.bundle` and resolves `Bundle.module` out of `.build/` **on this machine only**. The release
>   path (`xcodebuild`, the default) copies them correctly. **Every live test so far ran on a build whose
>   resource loading is machine-dependent.** Verify resource-backed UI (menu bar mark) on release artifacts.
>   This also refines the old note: `run_app.sh`'s xcodebuild is broken here, but `build_app_bundle.sh`'s is fine.
> - Piping a long background command through `| tail -N` buffers all output until exit — you see nothing
>   mid-run. Poll `xcrun notarytool history --keychain-profile splay` instead.
> - `swift test` baseline is **3166 tests / 8 failures = the same known 7 environmental fork-debt cases**.
> - Commit messages with apostrophes break `git commit -m "…'…"` in this shell — use `git commit -F -`.
>
> **Still open from older threads:** the deferred glow "nudges" (`SplayGlowTuning`: drift visibility /
> brightness / extend sway to ready) and the **talk-glow live verdict** (open since thread 6) — both queued
> for the final visual pass (`docs/launch-checklist.md` §C4), to be dialled in the live HTML tuner.
> **TEMP `f125f21d` diagnostic markers** are still in the tree; strip the `post_present` snapshot, keep the
> `src=` click tags.
>
> **Last updated (prior):** 2026-08-18 **thread 7d** — ⭐ **MENU-REOPEN BUG: ROOT-CAUSED + FIXED, committed
> `59101f91` (NOT pushed). LIVE TEST PENDING — that is the one thing to do next.**
> **The cause was not event-routing exotica; it was that the island had exactly one working click path
> and that path is off whenever Splay is active.** Proof from `~/Library/Logs/MacParakeet/dictation-audio.log`
> (the `f125f21d` diagnostics): `monitor_rejected src=local` occurs **0** times in the whole 1.4 MB log while
> `src=global` occurs **35**; and all **14** logged `splay_island click` lines are followed by
> `splay_card present … app_active=false` — **zero** island clicks have ever succeeded while Splay was the
> active app. AppKit never reports an app's own events to a *global* monitor, so that monitor is silent by
> definition while Splay holds the foreground. `present` calls `NSApp.activate`; the **Close button** leaves
> the app active; the island then had no live click path at all. Click-*away* dismissal never broke it
> because the click hands focus to another app, restoring the inactive state the global monitor needs.
> Hover kept working throughout because tracking areas don't care about activation — which is exactly what
> made this look like a delivery mystery for two threads.
> **WHAT SHIPPED (`59101f91`, 3 parts):** (1) `IslandPanel` gains **`.nonactivatingPanel`** — the style mask
> that lets an ambient never-key companion take a click in *both* activation states; it was the lone
> `.borderless`-only panel in the app (dictation overlay, meeting pill, transform pill all already had it).
> (2) The **local monitor became a real path**: resolves the click in *screen* space (so it agrees with the
> global monitor by construction), accepts a **window-less own-app click** instead of silently returning,
> still declines clicks tagged with a *different* Splay window (the card frame can overlap the island's), and
> **logs every decline inside the panel frame** — that silent `guard event.window === panel` early-return is
> precisely why the log carried no local evidence to reason from. (3) `SplayCardController` **yields
> activation** (`NSApp.deactivate()`) after teardown when no other Splay window can hold focus — an accessory
> app should rest inactive with only its ambient panels up. `dispatchClick` now carries **`src=local|global|
> mouseDown`** so the log states which path delivered.
> **NEXT THREAD — run the live test (installed build is ready, app relaunched):** click mark → card opens →
> close with the **Close button** → click the mark again **without touching any other window**. Expected: it
> opens, every time. Then `grep 'splay_island click src=' ~/Library/Logs/MacParakeet/dictation-audio.log` —
> **`src=local` lines are the proof the real fix (parts 1+2) works**; if you only ever see `src=global` then
> only part 3 is carrying it and parts 1+2 need another look (the island would still be dead any time Splay
> is active for some other reason). Also sanity-check: clicking the mark does **not** steal focus from the
> app you were typing in, and the card's Settings controls + Esc still work.
> **THEN:** strip the TEMP `f125f21d` diagnostic markers (the `post_present` snapshot, and decide whether the
> `src=` tags are worth keeping — they are cheap and genuinely diagnostic, so probably keep).
> **Validation done:** build clean; `swift test` 3166 tests / 8 failures = the same known 7 environmental
> fork-debt cases, zero new; agentic Vet clean after two comment-accuracy fixes.
> **Installed:** `/Applications/Splay.app` built from `59101f91`. `install_local.sh` does not relaunch and
> `open` right after the swap can fail with `-600` — wait ~2s and `open` again.
>
> **Last updated (prior):** 2026-08-17/18 **thread 7c** — ⭐ **OPEN BUG, START HERE NEXT THREAD: menu card opens
> only once per activation.** Repro (user-confirmed, 100%): click mark → menu opens → close with the
> **Close button** (staying in Splay) → further mark clicks do NOTHING until Splay is deactivated (click
> any other window/screen), then it works once again. Dismissing by clicking *away* (resign-key path)
> never breaks. **Evidence (TEMP diagnostics committed `f125f21d`, still in tree + installed build —
> read `~/Library/Logs/MacParakeet/dictation-audio.log`):**
> (1) every open that fires logs the full healthy chain `splay_island click → splay_card menu_requested
> → menu_loaded → present → post_present visible=true key=true frame=(586,260,556,597) entry_flag=true`
> — so when the chain runs at all, the card IS visible/correct (invisible-card + wrong-screen theories
> dead; user has ONE screen 1728×1117);
> (2) in the broken phase **hover still works** (`hover=enter/exit` logged, island reveals, user
> confirmed) but a mark click logs **NOTHING** — no dispatch, no `click_rejected`, no
> `monitor_rejected src=local` and no `src=global` → the mouseDown reaches NEITHER our local monitor
> (app-delivered events) NOR the global monitor (other-app events); it is swallowed below our code;
> (3) dismiss reasons are tagged — Close button = `reason=card_button_or_margin`, click-away =
> `reason=resign_key`;
> (4) **app-active alone is NOT the trigger**: externally activating Splay (`open /Applications/
> Splay.app`) then clicking the mark WORKED once — then Close → broken. The wedge is created by the
> **card-dismiss-while-active** path specifically, not by activation;
> (5) ruled out: competing local mouseDown monitors (none), `acceptsFirstMouse` (already true on the
> tracker), window-stack occlusion while healthy (probe: island layer 101 frontmost in its strip; the
> layer-25 Splay anchor is `ignoresMouseEvents`); the thread-7b hover-race fix (`ecf912af`) is a
> different, fixed bug (geometry-level swallow — this one is event-delivery-level).
> **HYPOTHESES + NEXT EXPERIMENTS:** (a) in the BROKEN state (never probed yet!) run a CGWindowList
> stack probe over the island strip (trivial ~30-line swift tool; last thread's lived in the session
> scratchpad — rebuild it) + log `NSApp.keyWindow`/`mainWindow` — the dead card panel (delegate'd,
> orderOut'd in `dismiss()`'s +0.34s work item) may still be referenced as key, wedging event routing;
> (b) log from a `NSApplication.sendEvent` override or an in-app event tap whether the mouseDown even
> reaches the app; (c) ⭐ **cheap likely fix to try FIRST: `NSApp.deactivate()` (or
> `NSApp.hide`/yield) after the card's teardown completes in `SplayCardController.dismiss`** — it
> restores exactly the app-inactive state in which island clicks always work (and matches the user's
> manual workaround); decide if the UX is acceptable (two-surface design has no other windows open, so
> deactivating after the card closes should be invisible); (d) also compare `makeKeyAndOrderFront` vs
> `orderFrontRegardless` + never-key for the card. **Strip the TEMP `f125f21d` markers once closed.**
> **Installed build:** diagnostic build 20260818022223 (tree = `f125f21d` content). `install_local.sh`
> does not relaunch and `open` right after the swap can fail with `-600` — wait ~2s and `open` again.
>
> **Last updated (prior):** 2026-08-17 **thread 7** — "dead ≠ silent": stall guillotine removed + amber waiting
> light + error card; **committed `79567ad0`** (+ docs commit; **NOT pushed**).
> **thread 7b (same day): mark-click hover-race fix, committed `ecf912af`.** User: "the splay icon button
> does not always pick up a click." Root cause: the mark only resolves in `.idleHover`, but `mouseDown`
> can outrun the tracker's hover flip (or the 28pt stay-margin drops hover between aim and click) — the
> click then hit the *dormant* geometry: partly swallowed by the hit-rect gates (the revealed mark pokes
> outside the nub rect), partly misrouted to record. **Fix = recency-gated reveal resolution:**
> `hoverDroppedAt`/`recentlyRevealed` (`IslandLayout.hoverRaceGrace` 0.7s) gates BOTH
> `currentActiveRect()` (the one source for the container hitTest + both click monitors) AND the new pure
> `IslandLayout.clickVisual(...)` in `dispatchClick` — a racing idle click resolves against the revealed
> pill; a **cold dormant click is never rerouted** (click-anywhere-records + pass-through pixels stay; the
> old "dormant click opened the card" bug stays fixed). ⚠️ Vet earned its keep: revision 1 (no recency
> gate) was BOTH unreachable for the swallowed region (gates filtered first) AND reintroduced the
> dormant-card bug — both caught by Vet, fixed in rev 2, re-review clean. New
> `IslandClickRoutingTests` (6). Full suite: baseline-identical (the known 7 environmental). **Live-test
> pending:** quick aim-and-click on the mark should now open the menu card every time.
> **Also from the live test:** recording with warm AirPods worked (2 clean saves, first buffer ~100ms) —
> the amber never showed because the mic was never dead (correct); user: seeing amber "doesn't really
> matter". **Talk-glow visual verdict still not confirmed** (user wasn't watching for it).
> **THE INCIDENT (what "crashed again mid recording" actually was):** no crash — two events. (1) The app
> quit at 15:28:04 on 08-14 via a Quit AppleEvent = **the user's own quit/relaunch** (confirmed); zero
> crash reports, clean `NSTerminateNow` exit. (2) The recording after relaunch got **zero buffers** from
> freshly-reconnected AirPods (cold A2DP→HFP, ~10s warm-up; no `-10868` this time — CoreAudio was fine)
> and the coordinator's **10s stall guillotine** killed it at 10.2s → `noAudioCaptured` → session folder
> deleted, no DB row, no visible explanation. The guillotine was **fork-added** (`55be635d`), NOT
> upstream — upstream never kills silent recordings and shows `.showError` text in its panel/pill, both
> surfaces the fork deleted. User verdict: "we tried to be accurate but that made things worse."
> **WHAT SHIPPED (`79567ad0`):** (a) guillotine **removed** — silence never fails a recording (genuine
> engine-death check kept); (b) **dead ≠ silent** (doctrine adopted from **Talkify**, MIT,
> tornikegomareli/Talkify — a sibling notch-island dictation app; clone in this session's scratchpad):
> the 1 Hz health poll derives "frames arriving?" (2s startup grace / 2s stale) → new `onAudioAlive`
> channel → `IslandChromeModel.audioAlive` → while recording with a dead input the whole light (bloom,
> fiber, halo, status LED, mark) holds a **motionless `.warning` amber** (Breathe suppressed), easing
> 0.42s back to breathing red when buffers flow; self-healing; log marker `meeting_audio_alive=`;
> (c) **failures now speak**: `.showError` retains `heldFailureMessage`; clicking the failed island
> clears it AND opens a danger card ("Recording failed") with the actual text
> (`AppDelegate.presentErrorCard`; card header draws the SF Symbol as `Image` — the shell's glyph tile
> renders `Text`, a Vet catch); `noAudioCaptured` copy now explains cold-Bluetooth. **Validation:** build
> clean; 3160 tests → 8 failures = the same 7 known environmental fork-debt cases, zero new; agentic Vet
> run, both findings fixed. **Installed + running:** `/Applications/Splay.app` build 20260817220049
> commit `79567ad0` (note: `install_local.sh` does NOT auto-relaunch — `open` it after).
> **⚠️ LOG GOTCHA:** an unrelated build (version 0.7.3, commit `d6321f87`, dist-xcodebuild) also writes
> `~/Library/Logs/MacParakeet/dictation-audio.log` (sessions 08-15/16) — the log dir is shared across
> MacParakeet-family apps; match `pid`/`commit` before trusting lines. **STILL OPEN:** the thread-6
> **talk-glow live-test** (item 4) — now much easier to run: AirPods-from-cold survives (watch amber →
> red as HFP wakes), then speak and check the wash/rim react; dial `SplayTalkGlowTuning` / the Settings
> "Talking glow" slider. Also verify live: amber waiting register look, the failure card, error-card
> copy.
>
> **Last updated (prior):** 2026-08-14 **thread 6** — recording/transcribing island light; **committed `83410f57`**
> (now **12 ahead of `origin/main`**; the docs commit makes 13; **NOT pushed**).
> **(A) Transcribing = semantic amber (item 3 — DONE, user-confirmed "color scheme works").** `.transcribing`
> left the brand/themed bucket for a semantic "processing" amber (`#F6C86B`) in `SplayIslandLight.palette`;
> spinner arc + mark + fiber + desktop bloom all go amber, so the lifecycle reads red→amber→green. Spinner
> takes its colour from the transcribing palette (`SplayIslandSpinner(color:)`).
> **(B) Voice-reactive recording glow — the "moving-head wash" (IMPLEMENTED + builds clean; live-test still
> PENDING — see ⚠️).** A smoothed mic envelope drives the recording glow: sweep amplitude+speed grow with
> voice (`SplayMotion.talkVector`), a secondary "gobo" wobble adds texture, and wash/pill-halo/fiber-rim
> brighten. Values dialed in a live HTML tuner (`[[visual-tuning-with-live-tuner]]`) → `SplayTalkGlowTuning`
> (baseSway 7, swayGain 7, speedGain 0.3, goboAmount 0.45, brightGain 0.5, smoothing 0.95). Master strength =
> persisted **Settings "Talking glow" slider** (`SplayGlowSettings.shared.talkIntensity`, default 0.8;
> **0 = full revert** to the calm sway). `TalkEnvelope` is a frame-rate-independent follower (quick attack,
> calm release).
> **★ ROOT-CAUSE FIX (why the first talk-glow build "didn't change much"):** the island read mic level off the
> shared `pillViewModel`, updated only at **1 Hz** by `startPillPolling`; the **fast ~30 fps**
> `startPillGlowPolling` deliberately bypasses that VM (the Transcribe tile reads `pillViewModel.micLevel`, so
> 30 fps writes would relayout it) and feeds the floating pill (CALayer) + panel orbs via *isolated* channels
> — the **island was never on the fast path**. Added its own isolated channel:
> `MeetingRecordingFlowCoordinator.onLiveAudioLevel` (pushed each fast tick) → `IslandController
> .updateLiveAudioLevel` → `IslandChromeModel.liveLevel`, read by `IslandView` + `SplayGlowView` (only island
> surfaces observe that model, already re-rendering per-frame while recording → no tile churn).
> **⚠️ LIVE-TEST BLOCKED, NOT A CODE BUG:** the last AirPods-from-start recording captured **ZERO buffers**
> (`mic_first_buffer=false mic_frames=0`, CoreAudio **-10868** on the bluetooth route) — the wedged-CoreAudio
> state after **146** test sessions today. **No crash occurred** (no crash/hang/jetsam report anywhere; the
> process stayed alive; the "vanish" the user saw was `install_local.sh`'s `osascript quit` swapping the
> bundle mid-use). Built-in-mic recordings on these *same* builds captured audio fine (`mic_first_buffer=true`,
> 10⁵–10⁶ frames), so the glow feed works — there was just no signal. **NEXT THREAD:** un-wedge CoreAudio
> (`sudo killall coreaudiod`, needs the user's password) **or** test with the **built-in mic**; record + speak,
> confirm the wash/rim react (offer to tail `~/Library/Logs/MacParakeet/dictation-audio.log` for `mic_frames`
> climbing + non-zero level), then dial the feel via the Settings slider or the `SplayTalkGlowTuning`
> constants. Installed build = talk-glow fast-channel fix (`/Applications/Splay.app`, 15:46). **Still unpushed;
> user has not asked to push.**
>
> **Last updated (prior):** 2026-08-11 **thread 5** — cleared the two queued NEXT-THREAD items (both committed,
> **NOT pushed**; now **10 ahead of `origin/main`**). **(1) Menu card top-anchored resize** (`7958953c`):
> `SplayCardController.refit` pins the panel's current top edge (`panel.frame.maxY`) and grows *downward*
> instead of re-centring on `screen.midY`, so flipping Recents/Settings/About no longer makes the top hop.
> **(2) Identity + code rename** (`4b5acbad`): SwiftPM package + modules `MacParakeet*`→`Splay*`
> (`Sources/Splay`, `SplayCore`, `SplayViewModels`, `SplayObjCShims`, `Tests/SplayTests`; every `import`;
> `Package.swift`; `build_app_bundle.sh` SwiftPM product/bin/dSYM/`-scheme` refs → `Splay`; the colocated
> `Sources/SplayCore/**` subsystem READMEs; `docs/BRANDING.md` rewritten). **KEPT** (data/permission/CLI/
> plist contracts): bundle id `com.macparakeet.mc`, defaults domain `com.macparakeet.MacParakeet`, data
> namespace `MacParakeet-MC` (`AppPaths.appFolderName`), `macparakeet-cli` (target `CLI`), and the
> `MacParakeet*` Info.plist keys. **Validation:** `swift build` clean; `swift test` = 3160 tests, only the
> **7 pre-existing/environmental** fork-debt failures (AppPaths + 3× SettingsViewModel assert the pre-`-MC`
> namespace; MainWindowState expects the pre-trim nav; 2 AppHotkeyCoordinator are `AXIsProcessTrusted`-gated)
> — verified **rename-invariant** by reading each assertion against the kept `MacParakeet-MC` value + full-
> suite enumeration; the rename introduced **zero** new failures (thread-4's "green" was loose — these were
> already failing per thread-1's note). **Intentionally left** (optional follow-up polish): `run_app.sh`
> (xcodebuild dev-runner, broken/unused here) and the `MacParakeetApp` / `Sources/CLI/MacParakeetCLI.swift`
> type+filenames (not module identity; the CLI keeps its name). **Only item 3 (transcribing amber dot)
> remains open.**
>
> **Last updated (prior):** 2026-08-11 **thread 4** — island interaction pass, **committed `9166348c`**
> ("Splay: island interaction pass…"; 8 ahead of `origin/main`, **NOT pushed**). Reworked the record dot
> into ONE persistent **light-red status LED** — base is full `recordRed` now (the dimmed 0.5-opacity
> version read as a dark/muddy red over the black pill), glows **only while recording**, hit region
> tightened **52→16pt** centred on the drawn dot. The **splay mark (left) now opens the menu**; the dot /
> rest of the bar records (idle) or stops (recording). **Idle stays a bare hidden nub** — the mark + dot
> **reveal on hover** (the earlier "permanent dot on the resting bar" made idle look expanded; user
> rejected it). Added **hover pop + physical key-press feedback**: `hoverPop` (hover = scale 1.20 +
> brightness + saturation 1.30 + tight glow; press = `pressPulse`/`onControlPress` depress to 0.95, auto-
> released) — the pop values were dialed in a **live HTML tuner** (`[[visual-tuning-with-live-tuner]]`)
> then ported (final: brightness 0.25, sat 1.30, glow 3, scale 1.20, no hue shift, press depth 0.95 /
> 0.20s). The two one-shot cards became one **tabbed `SplayMenuCard`** (Recents · Settings · **About** =
> version + GPL-3.0 attribution + Sparkle "Check for Updates") reusing `SplayCardView` via a pluggable
> `header`; `SplayCardController.refit(animated:)` resizes the panel on tab switch. Full `swift test`
> green; **3 Vet passes clean of logic issues** (only doc-hygiene findings, all fixed).
>
> **★ NEXT-THREAD NOTES (user-requested, 2026-08-11):**
> 1. ✅ **DONE (thread 5, `7958953c`).** Menu card tab-switch resize is now **top-anchored** —
>    `SplayCardController.refit` pins `panel.frame.maxY` and grows downward, so the top no longer hops.
> 2. ✅ **DONE (thread 5, `4b5acbad`).** Identity + code rename `MacParakeet*`→`Splay*` shipped — see the
>    thread-5 "Last updated" block above for exact scope + the KEEP list. Optional follow-up only: the
>    `MacParakeetApp` / `Sources/CLI/MacParakeetCLI.swift` type+filenames and `run_app.sh` were left as-is.
> 3. ✅ **DONE (thread 6, `83410f57`).** Transcribing is now semantic **amber**. User picked "amber spinner
>    + amber light" (kept the spinner form, recolored accent→amber; the whole transcribing light goes amber).
> 4. **OPEN — talk-glow live-test + tune (thread 6, code committed):** the voice-reactive recording glow is
>    built but never validated with real audio (AirPods gave zero buffers, -10868). Un-wedge CoreAudio or use
>    built-in mic, record + speak, confirm the wash/rim react, then dial the Settings "Talking glow" slider or
>    `SplayTalkGlowTuning`. If too subtle even with audio: bump `swayGain`/`brightGain` or raise the slider.
>
> **thread 3** — installed Imbue **Vet** as a Claude Code skill (see
> `[[vet-code-review-tool]]` memory / `~/.claude/skills/vet/`; run via `vet "goal" --agentic --agent-harness
> claude` — no API key on this machine), ran it on `452b806f`, and applied its **low-risk** cleanups:
> stripped the TEMP `record_dot_clicked`/`stop_clicked` diagnostics from `IslandController`, fixed stale
> `MicrophoneCapture` recovery-kick docs (removed phantom `recoveryGrace`/`maxRecoveryKicks` param docs +
> `recovery_kick`/`recovery_exhausted` comment), removed dead `waitUntil` (test) + write-only
> `SplayRecordingRow.micAndSystem`, and retired `mic-capture-resilience.md` → `plans/completed/`
> (HISTORICAL — it described the rejected recovery-kick approach). **STT engine is now Whisper**
> (`speechRecognitionEngine=whisper` set in the **`com.macparakeet.mc`** defaults domain — NOT the CLI's
> `com.macparakeet.MacParakeet`; WhisperKit `large-v3-turbo` model cloned into the fork namespace; first
> load paid a ~681s one-time CoreML compile, warm after). Vet's **deferred** findings (held capture-failure
> silently swallows fn/menu; `isAwaitingFailureDismissal` over-matches non-capture `.error`; no tests for
> `SharedMicrophoneStream.restart()`/`followDefaultInputChange()`) await a design call.
> **thread 2** — mic-capture forgiving rewrite + click-to-record. **Jump to
> the "▶ NEXT SESSION STARTS HERE" section below** for the current state (corrected diagnosis, the
> `MacParakeet-MC` data-namespace gotcha, what's installed in the 16:53 build, and what's still open).
> **Committed** as `452b806f` ("Splay: forgiving mic capture, click-to-record, audio pairing") — 4 commits
> ahead of `origin/main`, **not pushed**. The thread-1 summary that
> follows is kept for context but is **superseded** by that section (its "empty transcript discards audio"
> model was wrong — the real cause is a zero-buffer capture failure).
>
> _(thread 1, superseded — kept for context)_ This session, all
> **uncommitted on `main`** at `55be635d` (14 modified + 2 new files; do **not** push; 3 commits ahead of
> `origin/main`), in order: **DynamicNotchKit blur-transition harvest** (DNK rejected as substrate;
> accepted, "elegant"); **micro-UI polish** ×2 (card shadow-clip→subtle, copy-to-clipboard recents, visible
> recording **stop square** + reworked record button, **hover-pop**); **mic-capture resilience increment 1**
> (patience + engine-restart "kick"; `plans/active/mic-capture-resilience.md`); and **audio-pairing** (saved
> meetings now copy their `.m4a` into a `Recordings/` subfolder next to the `.md`). Build-clean; AutoSave +
> mic tests green. **⚠️ The installed `/Applications/Splay.app` (12:22 build) = mic-resilience increment 1
> only — it does NOT include the audio-pairing fix.** Phase 3 (cards)+theming+motion remain the last
> COMMITTED work. **Read the "NEXT SESSION STARTS HERE" section — it opens with the live storage/data-loss
> item and two questions the user still owes answers to.** Everything below the "CURRENT DIRECTION" section describes the *previous*
> island-as-router approach, now **superseded** *and deleted* (the router files are gone). Kept for the
> panel mechanics/gotchas, not as the product direction.
>
> **DECISION RESOLVED (2026-08-10) — DynamicNotchKit is NOT our substrate.** Read all of DNK 1.1.0's
> source against our design. Four sourced dealbreakers *for Splay specifically*: (1) `NotchView` hard-
> masks all content to a solid-black `NotchShape`, so our light that spills *outside* the pill (leaning
> halo, fiber rim, desktop bloom) gets clipped — and the mask is private, so unmasking = fork; (2) its
> panel is `level = .screenSaver` (top of everything), so it **cannot host our below-windows glow** at
> `.normal − 1` — we'd keep our own glow panel regardless; (3) it's **ephemeral** — creates the window
> on `expand()/compact()`, destroys on `hide()` — vs. our always-on idle nub; (4) the non-notch floating
> fallback is a **frosted-glass** `VisualEffectView(.popover)` popover that slides down from the top (the
> exact glass we rejected) with **no compact/idle state on floating screens** — so external/non-notched
> displays would have no idle indicator at all. Its SwiftUI-native `.onHover`/Button interaction also
> can't transfer, since our idle nub must stay non-key (never steal focus). **Keeper:** its
> `.blur(intensity:)` transition — content resolves *into focus* as it scales/fades, softer than our bare
> scale+opacity. Ported first-party as `AnyTransition.splayBlur(intensity:)` in
> `Views/Island/SplayTransitions.swift` (MIT-derived, ~30 lines, no dependency). Applied to the face-
> cluster `spawn` (6), the whole-island appear (8), and the card breathe-open (blur 10). References worth
> keeping (not adopted): DNK's `NotchShape` (animatable top/bottom radii, the authentic flared silhouette)
> and its notch-detection via `auxiliaryTopLeftArea`/`safeAreaInsets`. **boring.notch** (GPL-3.0) remains
> a technique reference only. A clone of DNK 1.1.0 sits in this session's scratchpad for reference.

---

## ⭐ CURRENT DIRECTION (2026-08-07) — two-surface rebuild

**The final design arrived and it changes the skeleton.** The authoritative design is now
`docs/design/splay-island-handoff/` (README = final intent + tokens; `Splay Island Fiber.dc.html`
= interactive prototype). The active plan is **`plans/active/splay-two-surface-rebuild.md`**.
`plans/active/island-only-lean-roadmap.md` is now **HISTORICAL** (its island-as-router model is
rejected).

**The model:** exactly **two surfaces**. ① the **island** = a flat-black pill hanging from the
notch, **indicator only** — its identity is the *light behind it* (ambient bloom + fiber stripe)
that breathes red while recording; nothing is drawn on its face beyond one/two glyphs. ② the
**card** = a centred modal over a dimmed scrim, carrying *everything else* (first run, permissions,
recents, settings, alerts). No in-island router, no dropdown, no settings window, no second window.
Trigger = **double-tap fn** + an on-screen clickable **fn** chip (⌥Space was dropped as unreadable,
2026-08-07). System audio is a persistent toggle.

**Decisions locked (2026-08-07):**
- File-first **and** keep paste: the file is *always* written; the *destination* is the post-save
  handoff (Folder / Obsidian / Claude / Clipboard / **Paste-into-app**). Accessibility only if paste on.
- Storage = **iCloud Drive** `Splay/` folder (`~Library/Mobile Documents/com~apple~CloudDocs/Splay`,
  `~/Splay` fallback). One flat folder, `.md` + paired `.m4a`, sorted by date. Enables a future
  iPhone app with no backend (Phase 7).
- Phase order: 1 light+indicator → 2 trigger (fn + on-screen fn chip) → 3 card system →
  4 storage+destinations → 5 first-run cards → 6 retire old surfaces + cut list → 7 (later) iPhone.

**Phase 1.1 tuning (2026-08-07 live-test feedback):** removed the leftover lavender notch-cue
seam/glints (the "bright bar" the user spotted); added hover hysteresis (`IslandLayout.hoverStayRect`
+ wider `notchRevealRect`) so reaching the notch activates ready and it stays active on the tile;
replaced the unreadable `⌥␣` with a clickable system-font **fn** chip (right cluster of the ready
pill, `SplayIslandIndicator.fnButton`) whose hit region is `IslandLayout.fnButtonRect` →
`tracker.onRecordClick` → `onRecord(.microphoneOnly)`. Ready pill widened 248→264 to seat the chip.

**Phase 1.2 tuning (2026-08-07, second live-test round):**
- **Desktop glow.** The big ambient bloom was moved OFF the pill panel onto its **own panel below app
  windows** so the light sprays onto the wallpaper instead of hovering over the user's work. New
  `SplayGlow.swift` (`SplayGlowView` + `SplayIslandState.resolve`); `IslandController` builds a
  `glowPanel` at `NSWindow.Level.normal - 1`, `ignoresMouseEvents`, `.canJoinAllSpaces/.stationary`,
  positioned to the idle frame (`installGlowPanel`/`positionGlowPanel`), re-ordered in
  `restoreAmbientVisibility`, torn down in `hide`. The pill keeps only a small local shadow-glow +
  the fiber stripe so it still reads as alive on top. `Breathe` + `SplayMotion.bloomIntensityScale`
  moved to `SplayIslandLight.swift` (shared by indicator + glow).
- **fn chip** shrunk (11→10.5pt, tighter padding) and made a **Capsule** to echo the island's rounding.
- **Mark** given more breathing room (face horizontal padding 6→14, clears the corner curve) + its own
  soft **breathing accent glow** (`.shadow` on the glyph).
- Build clean; signed install pending user live-test. **Key thing to verify:** open a window over the
  top of the screen and confirm the recording glow now sits *behind* it (on the desktop), while the
  pill + fiber stay visible on top.

**Phase 1.3 tuning (2026-08-07, third live-test round):**
- **Record dot replaces the fn chip.** Ready state now shows a simple Voice-Memos-style red circle
  (`SplayIslandIndicator.recordButton`, `SplayLight.recordRed` #FF5A52); `fnButtonRect` renamed
  `recordButtonRect`. ("fn" felt random.)
- **Smoother fades.** Island morph curve 0.32→**0.42s** `.smooth`; the desktop glow now cross-fades
  between states via `.id(state)` + `.transition(.opacity)` + `.animation(.easeInOut(0.42), value:)`
  (gradient colours don't interpolate, so it dissolves instead of snapping). `SplayIslandState` is
  now `Hashable`.
- **Glow ~25% stronger** — bumped `bloomL1`/`bloomL2` base opacities and the gradient `endFraction`
  (0.72/0.70 → 0.80/0.78). Deliberately mid-strength (user: "leaning closer to what we have now").

**Phase 1.4 tuning (2026-08-07, fourth live-test round):**
- **Record dot** shrunk 18→13pt to match the mark's visual weight.
- **Spawn/pop animation** — island morph curve is now a `.spring(response:0.3, damping:0.72)` (was a
  slow 0.42 fade, which felt like it "encompassed static elements"). The island pops in via
  `.scale(0.85, anchor:.top)+opacity`; cluster elements (mark/record dot/glyphs) scale-in via a
  shared `spawn` transition; the desktop glow bursts via `.scale(0.8)+opacity` on a spring.
- **Glow wraps AROUND the island (3D)** — instead of more downward spread, the bloom is now centred
  on the pill's vertical middle (`SplayAmbientBloom` offset = pillHeight/2, was the CSS downward
  bias) and widened sideways (`bloomL1`/`bloomL2` widths up ~15%); heights unchanged. Panel widened
  720→840 to contain the 740px recording bloom.
- **Fiber no-gap** — the rim light now traces the pill's exact edge (removed the −1/−3 outward inset
  + radius+1 that caused the visible gap in the screenshots).

### ▶ NEXT SESSION STARTS HERE (mic capture: forgiving rewrite — 2026-08-10, thread 2)

**⚠️ FIRST, THE CORRECTED DIAGNOSIS (thread-1's model was wrong).** The vanishing was **NOT** "empty
transcript = silently dismiss discards audio." It is a **zero-buffer capture failure**: a cold Bluetooth
(AirPods) mic delivers *no buffers*, the original **2-second first-buffer watchdog guillotined** the
recording (`capture_failed`), and `MeetingRecordingService.swift:577-591` (`noAudioCaptured`) then deletes
the whole session folder → no DB row, no `.m4a`. Recordings that captured **any** audio were always saved
(even empty-transcript ones save fine as `.completed`). Proven from the log (5+ identical
`mic_frames=0 capture_failed=true` deaths) and the DB.

**★★ THE DATA-NAMESPACE GOTCHA (cost real time — READ THIS):** the fork stores everything under
`~/Library/Application Support/**MacParakeet-MC**/` (bundle id `com.macparakeet.mc`), **NOT** the upstream
`…/MacParakeet/`. DB = `…/MacParakeet-MC/macparakeet.db`; recordings =
`…/MacParakeet-MC/meeting-recordings/<UUID>/{microphone,system,meeting}.m4a`. Querying the upstream dir shows
stale/empty results and makes recordings look "vanished" when they're fine. `[[macparakeet-mc-fork]]` memory
carries this. Probe audio with `/Applications/Splay.app/Contents/Resources/ffmpeg`.

**WHAT LANDED THIS THREAD (committed as `452b806f`; installed `/Applications/Splay.app` 16:53 build;
4 ahead of `origin/main`, NOT pushed):**
- **Simplified the mic layer (the big one).** *Removed* the fragile recovery-"kick" (restart-on-no-buffer);
  a cold start now just **waits patiently** (`MicrophoneCapture` watchdog is log-only:
  `meeting_mic_no_first_buffer_yet`, no guillotine, no restart). **Silence is never a failure.** This fixes
  the cold-AirPods vanishing at the root — the recording waits and captures when buffers arrive (~100ms when
  AirPods work). Live-proven: 23:48 AirPods-from-start recording succeeded.
- **Follow Apple's default input.** `MicrophoneEnginePlatform` already *observed* default-input changes
  (log-only); now `SharedMicrophoneStream.followDefaultInputChange()` re-points the engine onto the new
  device with backoff retry (0.3/0.8/2s). **`restart()` is now non-fatal** — a failed re-point NEVER kills
  the recording (removed the `onEngineDeath` firing; guard is subscriber-based; sets `engineRunning=true` on
  success). Markers: `shared_mic_follow_default_input` / `…_ok attempt=N` / `…_retry` / `…_gave_up`.
- **Genuine failure = sound + hold (not silence).** `SoundManager.play(.errorSoft)` on `.showError`;
  `.captureFailed` no longer auto-dismisses (holds the failed island until the user clicks it to clear —
  `MeetingRecordingFlowCoordinator.isAwaitingFailureDismissal` / `dismissFailure()`, wired via
  `AppEnvironmentConfigurer` `onOpenCard`). Only fires for real engine death now, not silence.
- **Click-island-to-record.** `IslandController.dispatchClick` idle cases (`.idleCollapsed`+`.idleHover`) now
  call `onRecordClick` — a click ANYWHERE on the idle island records (no hover, no tiny dot). Fixes "record
  button is buggy / doesn't start" (clicks were landing as `onOpenCard`). Recents card is now **menu-bar
  only** ("Open Splay"); user may want right-click→card added.
- **Diagnostic markers added** (keep for now): `meeting_capture_failed …` (file-visible, was os_log-only) in
  `MeetingRecordingService.failCapture`; `meeting_mic_engine_death_stall` in `MicrophoneCapture.deathDispatch`.
- Tests green: `MicrophoneCaptureTests`/`SharedMicrophoneStreamTests` (47), `MeetingRecordingFlowStateMachineTests` (18).

**REMAINING / OPEN:**
- **Mid-recording AirPods *insert* still goes silent after the switch.** Follow succeeds structurally
  (recording survives, `capture_failed=false`) but freshly-connected AirPods deliver no buffers for ~10s
  (cold A2DP→HFP), so post-switch audio is lost (22:27 test: 15.4s recording, 4.35s audio). Real fix =
  "don't drop the working mic until the new one is actually delivering" (keep old device, switch the tap only
  once the new one produces). Gated on whether the user actually switches mid-recording (their real workflow
  is AirPods-from-start = already fixed).
- **`noAudioCaptured` (zero-bytes-at-stop) still deletes + errors.** Rare now (patience + follow), but a
  truly-dead-mic recording still hits it. Possible follow-up: keep a stub / don't error on zero-capture.
- **TEMP click diagnostics** — **DONE (thread 3):** stripped from `IslandController` in the Vet-driven
  cleanup commit (build + focused audio/meeting tests green).
- **Audio quality on AirPods is inherently telephony-grade** (8 kHz mix, high ambient noise floor from HFP
  AGC). Not a bug — it's AirPods-as-mic. User accepted "follow system default"; declined force-built-in
  (walking-around dictation needs AirPods). No device-surfacing indicator wanted (redundant).
- **Environment caveat:** repeated Bluetooth insert/remove/record thrashing wedges CoreAudio (built-in mic
  starts returning zero buffers, `-10868` everywhere). Reset with `sudo killall coreaudiod` before trusting
  a test.

---

#### Earlier this session — mic-capture resilience (increment 1)

**Latest = making the recorder "Voice-Memos-patient" so a cold Bluetooth mic stops killing recordings.**
Plan: `plans/active/mic-capture-resilience.md`. All uncommitted; do not push. Signed install built.

- **Root cause (confirmed from the log):** AirPods mic starts but delivers **zero buffers** because the
  A2DP→HFP route switch hadn't completed; a hard **2s first-buffer watchdog** guillotined the recording
  (`capture_failed`). Buffers *were* coming, just not in 2s. Not a button bug (record-dot click works 100%);
  hits fn recordings too. User's framing: "most software is pretty dumb" / how does Voice Memos do it —
  answer: it's **patient** (waits for the route), **self-heals**, and **follows the route**; we hand-rolled
  a trigger-happy watchdog.
- **Design decision (keeps blast radius tiny):** recovery lives **entirely in the audio layer, BELOW the
  meeting state machine**, bounded to finish under the coordinator's 10s stall poll. So the tested invariant
  "capture failure → `.error`, never `.completed`" is **untouched** — a *recoverable* stall simply never
  becomes a capture failure; only exhausted recovery emits the existing terminal `.error`. No state-machine,
  coordinator, or new-event changes needed. Verified: all 253 audio/meeting-flow tests + the invariant tests
  green.
- **Increment 1 — DONE (patience + engine-restart "kick"), the piece most likely to fix the AirPods case:**
  - `SharedMicrophoneStream.restart()` (new) — tears down + rebuilds the physical engine and re-runs the
    device chain **without dropping subscribers** (re-installs the fan-out tap). A fresh engine drops the
    CoreAudio aggregate and re-negotiates the route — the "kick." Uses only existing platform API, so no
    protocol/mock churn.
  - `MicrophoneCapture` watchdog reworked: first-buffer grace **2s→3.5s** (patience), and on timeout it
    **restarts the engine up to `maxRecoveryKicks` (2×)** with a short re-grace before surfacing a stall.
    Worst case ≈ 3.5 + 2×2.5 ≈ 8.5s, under the 10s poll. Grace/kicks are **injectable init params**
    (defaults 3.5/2.5/2) so tests run in ms.
  - Tests: `testZeroBufferStartRecoversViaEngineRestartKick` + `…StallsOnlyAfterRecoveryExhausted` (green).
  - **New diagnostic markers** (in `~/Library/Logs/MacParakeet/dictation-audio.log`): `meeting_mic_recovery_kick
    attempt=N`, `shared_mic_engine_restarted`, then `meeting_mic_first_buffer` = **recovered**; or
    `meeting_mic_no_buffers_recovery_exhausted` = the kick didn't shake it loose.
- **To verify live (the critical experiment):** record with AirPods from a cold start (idle a while first).
  Does it now record instead of dying at 3s? Pull the log: a `recovery_kick` followed by `first_buffer`
  means the kick worked; `recovery_exhausted` means it didn't (→ built-in fallback becomes the real fix).
- **Increment 2 (next, gated on the live-test):** built-in-mic fallback (platform restart advancing past the
  last-succeeded device) + mid-recording resilience (ongoing mic heartbeat + route observers → same
  recovery, so a mid-session drop restarts+continues). See the plan.
- **Still open from before:** the record-dot TEMP click diagnostics are still in (strip before commit); the
  "should the dormant nub click record vs open the card?" question is unanswered.

---

#### Earlier this day — micro-UI polish, round 2 (2026-08-10)

**Latest = a second live-test loop on the micro-UI.** All uncommitted on `main` at `55be635d` + working-tree
edits; do **not** push. Signed `/Applications/Splay.app` rebuilt for live-test.

- **★ Record-dot "non-clickable / stops itself" — DIAGNOSED, and it is NOT the button.** The diagnostic log
  (`~/Library/Logs/MacParakeet/dictation-audio.log`) is decisive: every `splay_island record_dot_clicked
  has_handler=true` is followed by `meeting_recording_started` — the click works 100%. The recordings die
  ~3s later via `meeting_recording_health … capture_failed=true mic_first_buffer=false mic_frames=0` on a
  **`transport=bluetooth`** mic: the engine starts but delivers **zero buffers**, so the health watchdog
  auto-stops it. **No `stop_clicked` ever fired** — the stop square was never involved. And `capture_failed`
  hits fn/menu recordings too (7 failures total, only 4 button) while many fn recordings succeed
  (mic_frames in the 10⁴–10⁶). ⇒ an **intermittent Bluetooth mic-capture issue**, not button-specific, not
  caused by this session. Next step is the user's controlled test (fn vs button, Bluetooth vs built-in/wired
  mic) — if it reproduces on built-in mic AND only via the button, *then* investigate a button-path cause
  (leading theory: the non-activating island click leaves the app inactive, vs fn; unverified). Secondary:
  after `capture_failed` the island sits in `.failed`/done and the record dot doesn't return until the flow
  resets to idle → "can't record again via button" (fn still works). The **click-path TEMP diagnostics**
  (`record_dot_clicked` / `stop_clicked` `AudioCaptureDiagnostics.append`) are still in — keep until the mic
  issue is closed, then **strip before commit**.
- **Card shadow** re-tuned twice: was heavy (`0.35`, r35, y24) → clipped-fix bumped padding to 80 → user
  said still too much → now a subtle two-layer macOS-style shadow (`0.10 r3 y1` contact + `0.14 r22 y11`
  ambient) with padding back to **48**.
- **Hover-pop strengthened** (user: "buttons not alive enough, no pop"): scale up (record 1.22 / stop 1.2 /
  folder 1.16) **plus a soft coloured halo** on hover (`hoverPop` now adds a `.shadow` bloom) so a control
  answers even with a stationary cursor. Mechanism unchanged (tracker `mouseMoved` → `hoveredControl` →
  indicator); if still not visible live, add a hover diagnostic to confirm `hoveredControl` is updating.
- **Copy-to-clipboard recents** confirmed working (user copied a real transcript; test rows with no
  transcript are correctly disabled).

#### Round 1 (earlier same day) — island micro-interactions + card polish, on the accepted blur harvest.
All uncommitted; signed install for live-test. Blur transition user-accepted ("elegant, a keeper").

- **Card drop-shadow was clipped** → fixed. `SplayCardFloat` padded only 44pt but the card shadow
  (`radius 35, y 24`) reaches ~60pt below; the fit-to-content panel clipped its bottom into a hard
  "unrendered" edge. Padding bumped to **80** (`SplayCardController.swift`).
- **Recents rows are now copy-to-clipboard.** They were inert (trailing mic/system dot). The whole row
  now copies that recording's transcript (`cleanTranscript ?? rawTranscript`) — trailing clipboard glyph
  flashes a checkmark, hover highlights the row + pops the glyph. `SplayRecordingRow` gained a `transcript`
  field; `SplayRecordingList`/`SplayCards.recent` gained an `onCopy`; `AppDelegate.presentRecentCard` wires
  it to `appEnvironment.clipboardService.copyToClipboard`. Rows with no transcript are disabled ("No
  transcript yet"). The mic/system dot was dropped (field kept). *Folder stays the archive; copy saves the trip.*
- **Island record/stop button reworked** (`SplayIslandIndicator` + `IslandView`/`IslandController`):
  - New `IslandControl` enum (`.none/.record/.stop/.open`). Recording now shows a **visible red stop
    square** (Voice-Memos: circle = start, square = stop) instead of the old invisible 38pt right-edge
    zone — resolves "the red button is on idle but recording has no button, and the dot's a gimmick."
  - Hit-rects unified: `IslandLayout.controlRect(for:)` + `control(at:visual:notchAttached:)` are the one
    source for *both* the click router and hover, so drawn glyph ↔ hit-rect can't drift. `stopHitWidth`
    replaced by `controlHitWidth = 52`.
  - **Clickability diagnosis is instrumented, not yet proven.** `onRecordClick`/`onStopClick` now
    `AudioCaptureDiagnostics.append("splay_island record_dot_clicked / stop_clicked has_handler=…")`
    (**TEMP — strip before commit**). The click architecture is unchanged (monitors + `dispatchClick`);
    if the dot still doesn't record, read `AudioCaptureDiagnostics.diagnosticLogURL()` — if the marker
    fires, the handler ran (look at meeting toggle / `coordinatorRefs.meeting`); if not, it's
    delivery/geometry. Suspected real cause is the **hover-gated dot**: click the *dormant* nub → opens
    card (`idleCollapsed → onOpenCard`); the record dot only exists after hover establishes `.ready`, so a
    too-quick click lands as a card-open. Open question for the user: should clicking the dormant nub
    *record* rather than open the card? (Two-surface design currently says nub-click = card.)
- **Hover "pop" on island buttons** (user: island moves but buttons feel static / "want a visual haptic").
  The AppKit tracker's `mouseMoved` now computes the hovered control in every state and feeds
  `IslandChromeModel.hoveredControl` → `SplayIslandIndicator.hoverPop(...)` lifts the record dot (1.16),
  stop square (1.14), and folder button (1.12) with a soft spring; disabled under Reduce Motion. Pointer-
  cursor was intentionally **not** added (forcing a cursor across the 840px transparent panel would
  override the underlying app's cursor); revisit with proper cursor rects if wanted. Card controls already
  had hover feel; recents rows got it this round.
- **To verify live:** (1) card shadow renders as a soft even halo, no hard bottom edge; (2) recents rows —
  hover highlights + glyph pops, click copies (checkmark flash), paste to confirm; (3) hover the record
  dot / stop square / folder → each pops smoothly; (4) **the key one**: click the record dot → does it
  start recording? click the stop square → does it stop? If not, pull the diagnostic log (path above).

---

#### Earlier this session — the blur-transition harvest (accepted)

**DynamicNotchKit evaluation → rejected as substrate; blur transition harvested.**
See the "DECISION RESOLVED" note at the very top for the full rationale. Net code change is small and
additive; nothing from the DNK library is a dependency. **User verdict: "elegant, I like it" — keeper.**

- **What landed (uncommitted, on `main` at `55be635d` + working-tree edits):**
  - **New file** `Views/Island/SplayTransitions.swift` — `AnyTransition.splayBlur(intensity:)`, a
    first-party port of DNK's `.blur(intensity:)` transition (content blurs across insert/remove so it
    resolves *into focus* instead of hard-popping).
  - **Three callsites upgraded** to `…scale…combined(opacity)…combined(splayBlur)`:
    `SplayIslandIndicator.spawn` (intensity **6** — the face glyphs that swap on every state change; the
    most-seen effect), `IslandView`'s whole-island appear transition (**8**), and — as a direct animated
    `.blur(radius: visible ? 0 : 10)` (the card breathes via a `visible` bool, not an `AnyTransition`) —
    `SplayCardFloat` in `SplayCardController`.
  - **Deliberately skipped** the desktop glow (`SplayGlow`): it's already blurred ~90px, so a transition
    blur is invisible there. Reduce-motion stays honored (all three are gated by nil animations already).
  - `intensity` is the single knob at each site if the effect reads too soft/strong live.
- **To verify live (hand-off checklist):** watch the **face glyphs** as state changes
  (dormant→ready→recording→transcribing→done) — each swapped glyph (mark / record dot / spinner / check /
  folder) should now *blur into focus* rather than snap; the **whole island** should soften on show/hide;
  the **card** should resolve into focus as it breathes open and soften as it dismisses. Confirm none of
  it feels sluggish or mushy (dial `intensity` down if so), and that the pill's tuned recording glow /
  light-vector sway are unchanged.

---

#### Superseded next-step note (Phase 3, landed 2026-08-08)

**Prior session = Phase 3, the card system (the second surface).** Build-clean; a signed
`/Applications/Splay.app` install was produced for live-test. All uncommitted; do not push.

- **What landed (see `plans/active/splay-two-surface-rebuild.md` → Phase 3 for the full list):**
  - **Three new files** in `Views/Island/`: `SplayCard.swift` (reusable `SplayCardView` shell +
    all five body blocks + `SplayCardPalette`), `SplayCardController.swift` (full-screen scrim panel,
    behind-window blur, Esc + click-away), `SplayCards.swift` (the two wired cards).
  - **Two cards wired to real data:** **Recent recordings** (last 5 from `TranscriptionLibraryViewModel`,
    "Open folder" reveals the current save folder) and **Settings** (three live toggles + Quit).
  - **Router retired / deleted:** `ExpandedIslandView.swift`, `IslandRoute.swift`,
    `IslandRoutePages.swift` are gone. `IslandView` is now a pure indicator; `IslandController` lost all
    expand/collapse/route/resize code and gained a single `onOpenCard` callback. The island **never
    expands into a control surface** anymore.
  - **Entry points → cards:** menu-bar "Open Splay" and app-reopen → recents card; every Settings
    menu item → settings card; island idle/done click → recents card. A finished recording no longer
    force-opens a surface (island lights `done`, file is waiting).

- **To verify live (hand-off checklist):** open the recents card (click the idle island, or menu-bar
  "Open Splay") and the settings card (menu-bar "Settings…"); confirm both render faithfully vs
  `docs/design/splay-island-handoff/` (scrim dim + blur, card shell, list/toggles); Esc dismisses;
  clicking the scrim outside the card dismisses; toggling "Record system audio too" / "Launch at login"
  sticks; the island itself still records/transcribes and no longer grows into a card.

- **Polish round after first live-test (2026-08-08b):**
  - **Card is no longer a modal.** Dropped the full-screen scrim + backdrop blur; the card is now a
    small **floating window** centred on screen (panel sized to card + a 44pt shadow/dismiss margin),
    nothing dimmed or locked. Dismiss via Esc, Done/Close, a click in the margin, or a click outside
    the panel (armed `resignKey`). See `SplayCardFloat` in `SplayCardController.swift`.
  - **Feedback feel on card controls.** Buttons (`SplayCardButton` + `SplayPressStyle`: hover
    lift/brighten + press dip + pointer cursor), the switch (hover scale/brighten + pointer), and
    destination rows (hover highlight + pointer) all now "answer" to hover/press. Shared pointer toggle
    = `SplayHoverCursor`.
  - **Pill morph fixed (was "static").** Root cause: `SplayIslandIndicator.body` swapped between an
    `if/else` (animated `TimelineView` vs static pill), which breaks SwiftUI geometry interpolation → the
    width/radius/colour snapped. Now **one stable render path** (a single `TimelineView(.animation(paused:
    !animated))` — paused when idle so the always-on island still costs nothing), so the pill glides
    between states. Parent morph spring relaxed 0.26→0.34 response.

- **Colour palette — DONE (2026-08-08c).** User provided `SevenAccentsColorVariations.zip` (Claude
  design export; canonical file preserved at `docs/design/splay-accents/Wind Palette Export.dc.html`).
  Seven accents — Ember/Marine/Amber/**Iris**/Fern/Rose/Coral — each with accent / hover / `accent-dark`
  (bright-on-dark) / ground gradient. **Iris (`#4A38A6`, bright `#A99BF2`) is the current lavender** and
  the default. Implemented:
  - New `Views/Island/SplayTheme.swift` — `SplayAccent` (the 7 presets + hex→Color) and
    `@MainActor @Observable SplayTheme.shared` (persists `splay.accent` to UserDefaults). Reading
    `SplayTheme.shared.accent` in any SwiftUI body recolours **live**.
  - **Only BRAND surfaces are themed:** the island's dormant/ready/transcribing bloom+fiber+mark, the
    transcribing spinner, the done "folder" button, and the card brand (buttons, glyph tile, toggle-on,
    selection, list dots). **Status colours stay semantic** (recording red, done green, warning amber) —
    per the export's `--state-*` "never themed" note, and to protect the tuned recording glow.
  - **Picker:** a 7-swatch `SplayAccentPicker` row in the Settings card (with an "Accent" label); pick →
    island + open card recolour together, persisted.

- **Motion — DONE (2026-08-08c), per "breathing" direction:**
  - **Card breathes in/out.** Replaced the rise-from-bottom (`riseC`) with a centred scale: grows from
    0.86 → settles with a soft spring overshoot (`response 0.42, damping 0.66`), and **contracts + fades
    on dismiss** (panel torn down after the exit). Driven by `SplayCardPresentation` in
    `SplayCardController`; no Y translation — it grows "out of itself".
  - **Idle island holds open with the card.** `IslandChromeModel.heldOpen` + `IslandController.setHeldOpen`;
    presenting a card sets it (island morphs to ready and stays), dismissing releases it (both close
    together). Wired via `SplayCardController.onDismiss` → `setHeldOpen(false)`.
  - Pill morph identity fix + spring 0.34 from the previous round remain.

- **Coral accent tuned + kept (2026-08-08c).** User: the export's coral (`#D8583C`) read as plain orange;
  retuned Coral to a vibrant Living-Coral (`#FB5E4D` / hover `#FF7263` / bright `#FF9A8C`) in
  `SplayTheme.swift`. User verdict: "Love the coral. That's a keeper."

- **Research done — reuse over rebuild (2026-08-08c).** Looked for an existing "Dynamic-Island element."
  Findings: **DynamicNotchKit** (MIT, macOS 13+, SwiftUI, ~446★) is the one real *library* — it owns the
  notch window / insets / non-notch floating fallback / compact↔expanded morph; MIT is fine in our
  GPL-3.0 tree. **boring.notch** (GPL-3.0) is a full app but a good technique reference (Core Animation
  transitions, non-intrusive event handling). Atoll / Notchy / SuperIsland / DynamicIsland_Mac are apps,
  reference-only. Decision deferred to next thread (see top note).

- **Glow nudges = deferred to final review (per user):** the three `SplayGlowTuning` one-liners (drift
  visibility, brightness, extend sway to ready) are intentionally untouched this session; dial them at
  the very end.

- **Then:** Phase 4 — file-first storage + destinations (iCloud `~/Splay`, always-write `.md` + paired
  `.m4a`, destination handoff incl. paste). The recents card's folder + the persisted
  `splay.playSoundOnStart` toggle get their real behaviour there. Phase 5 wires the first-run + alert
  cards (the shell + destination/permission/key-cap blocks already exist). Phase 6 deletes the now-unused
  Slice-4 overlay path (`IslandOverlayController`, `AppWindowCoordinator.openSettingsOverlay/…`).

---

#### Earlier this day — the island-feedback + glow-motion round

- **Done & user-accepted this session (all live-tested, verdict "looking good"):**
  - **Widths de-wobbled.** Was 6 near-identical pill widths; now 3 — dormant 206, ready 248, and a
    single active max **280** (`SplayGeometry.size` + its twin `IslandLayout.pillSize`). Recording
    sits at the max; no width change across recording→transcribing→done. `SplayGeometry.maxWidth`.
  - **Mark/glyphs recolor per state** — `markColor = palette.fiber` (recording coral, done green, …)
    in `SplayIslandIndicator`. Done state cut to **one** "folder" icon (two buttons were vanishing
    behind the notch dead-zone at 280 width).
  - **Hover resize fixed** — `panel.acceptsMouseMovedEvents = true` in `IslandController.show()`. The
    resting nub now grows on hover; before, hover-enter lived entirely in `mouseMoved`, which an
    NSPanel doesn't deliver unless this flag is set. (Reusable gotcha.)
  - **Transitions tightened** — `IslandView.motion` spring 0.26/0.82; `spawn` scale 0.8.

- **THE BIG ONE — the glow is now a "light-vector" model, NOT a pulse** (settled after ~5 iterations):
  One soft, **dim** (peak 0.20), **contained** (footprint 490), **very-blurred** (90) light whose
  *direction* slowly sways on an organic Lissajous path. There is **no visible moving source** — only
  the island's own lighting shifts. The user's reference: **Philips Ambilight** bias light (soft,
  enhancing, not flashy). Earlier failed framings (kept here so we don't relitigate): a brightness
  *pulse* (too heartbeat-y), *visible orbiting blobs* (don't want to see the source), a *big field
  pouring outward* (must stay concentrated at the island).
  - **All tunables live in one block: `SplayGlowTuning`** (top of `SplayIslandLight.swift`). Values
    were dialed by the user in a live HTML slider tuner, then ported. Current: footprint 490,
    blurL1 90 / blurL2 63, peak 0.20, sway 15, speed 0.20, swirl 2.1, haloRadius 26, haloOpacity 0.64,
    rimOpacity 0.40.
  - `SplayMotion.lightVector(t)` returns the sway offset (replaced the removed `bloomIntensityScale`).
    Both bloom layers (`SplayAmbientBloom.sway`) **and** the pill's own halo lean by the same vector,
    so the light moves as one body. The pill halo uses `palette.bloomHue` (opaque) at `haloOpacity`,
    leaning by `sway*0.16` — it carries most of the *visible* light because the wide desktop bloom
    (0.20, on the below-windows glow panel) is faint and often occluded by a window.
  - Only **recording / transcribing / dropped** sway; **dormant idle is untouched** (accepted).
  - Glow panel widened to `IslandLayout.glowPanelWidth` = 1400 (room for the soft wash to fade).

- **Open nudges the user flagged for next time (all one-liners in `SplayGlowTuning`):**
  1. Is the drift **visible enough** live? sway 15 is subtle; bump `sway` and/or the halo lean factor
     (hard-coded `0.16` in `SplayIslandIndicator.pill`).
  2. **Brightness** — SwiftUI blur reads dimmer than the CSS tuner; lift `peak` (0.20) / `haloOpacity`
     (0.64) if too faint in situ.
  3. Optionally extend the light-vector drift to the **ready/hover** state (only active states sway now).

- **Working style that clicked (see auto-memory `visual-tuning-with-live-tuner`):** for subjective
  visual params, build an **inline HTML slider tuner** (`show_widget`, faithful to the SwiftUI params,
  with an Apply→`sendPrompt` button) and let the user dial it live — then port the numbers. This beat
  the ~8-min build→install→eyeball loop by a mile for the glow work.

- **State of tree:** builds clean (`swift build` green); `/Applications/Splay.app` is the installed
  light-vector build. **Everything uncommitted** (many modified + new island files). Do NOT commit/push
  without the user asking.

- **Then (still pending from before):** Phase 3 — the **card system** (centred modal for
  recents/settings/first-run/permissions), retiring the temporary routed-pill "bridge" that still
  opens on pill-body click.

**Phase 1 status (in progress):** rebuilt the island as a pure indicator with the light.
- New files: `Views/Island/SplayIslandLight.swift` (palette/geometry/bloom/fiber/mark from the
  handoff) and `Views/Island/SplayIslandIndicator.swift` (the 9 states + single TimelineView driving
  bloom breath / fiber pulse / mark; recording bloom blends live `micLevel`/`systemLevel` with the
  design's irregular `voice` beat).
- `IslandView.swift`: lifecycle states now render `SplayIslandIndicator`; the old
  face content (dot/waveform/timer/stop) + decorative helpers were deleted; `.expanded` keeps the old
  routed card **only as a temporary bridge** (retired in Phase 3). `IslandLayout` pill sizes updated
  to the handoff geometry so the AppKit tracker hit-rects still match the drawn pill; panel widened
  to 720 to contain the 640px recording bloom.
- **Verified only that `swift build` passes.** A signed `/Applications/Splay.app` release build was
  kicked off for live test; **not yet user-verified.** Do NOT claim the visual is confirmed until the
  user looks at it. Things to eyeball first: bloom vertical position relative to the notch/menu bar,
  fiber-stripe crispness, dormant faintness, recording red breathing with the voice.
- Bridge still active this phase: clicking the pill opens the old routed card so Settings/Library
  stay reachable; fn still records; the recording pill's right ~38px is still a hidden stop zone.

---

## TL;DR — where we are right now (⚠️ describes the SUPERSEDED router approach — see above)

### Current verification checkpoint — 2026-08-06

#### Latest notch companion proof — supersedes earlier notch placement notes

- The installed Splay notch rest now uses two panels: a completely inert
  status-bar-level camera-housing anchor and a separate popup-level,
  `hidesOnDeactivate=false` companion. The companion deliberately starts at
  `screen.frame.maxY` (not `visibleFrame.maxY`) and overlaps only its central
  island width in the menu-bar band. Its actual internal-display WindowServer
  frame is `X=604, Y=0, W=520, H=460` for `screen={{0, 0}, {1728, 1117}}`, at
  level 101; its top is physically the display top.
- The temporary magenta AppKit composition probe was removed. The companion now
  renders a low-opacity lavender halo, 128×4pt seam, and two slow deterministic
  glints. The clean-launch screenshot visibly confirms that cue immediately
  below the menu bar/housing, instead of the former detached 32pt-lower pill.
  Cue decoration and the hardware anchor return `nil` from hit testing / ignore
  mouse events. Expanded hit testing is constrained to the actual route-sized
  black card; transparent companion pixels do not consume menu/status clicks.
- The hover-only reveal zone is 180×56pt and flush to that seam. Click targets
  remain narrow and are aligned to the zero-inset notch visual. On route resize,
  the long-lived companion keeps its top at `screen.frame.maxY`, so Home,
  Library, Settings, Setup, and detail grow downward from the physical edge.
  Transparent pixels remain pass-through; the app restores the existing
  non-key companion after accessory-policy hiding/Space transitions.
- Verification: `swift test --filter IslandPlacementTests` passed 2/2;
  `/Applications/Splay.app` was clean-launched through LaunchServices as PID
  42781, was still alive after 57 seconds, and WindowServer reported its
  companion on screen at the physical top; the screenshot is
  `/private/tmp/splay-physical-top-final-review-2.png`;
  `codesign --verify --deep --strict` passed; installed
  `NSPrefersDisplaySafeAreaCompatibilityMode=false`. No commit or push.

- **Notch placement implementation:** `Automatic` now resolves through public
  `NSScreen.safeAreaInsets.top`: a built-in notched screen uses the Splay notch
  rest position and every notchless/external screen uses the below-menu-bar
  fallback. Settings persistently exposes Automatic, Notch and Below menu bar;
  an unavailable manual Notch choice safely falls back. The notch idle surface
  is lifted eight points into the safe area and leaves a small violet status
  dot plus a 30pt hit target below the cut-out. Deterministic geometry tests
  pass. The signed `/Applications/Splay.app` release build was installed and
  relaunched successfully; process stability was confirmed. Manual physical
  notch/route click review remains the final human acceptance step.

- **Notch hover correction:** the idle click target remains narrow, but the
  AppKit tracking view now has a separate 180×56pt central hover-only approach
  rect below the physical top edge when Notch resolves. Entering it expands the
  same panel without a click; it does not broaden click capture or cover menu
  extras. The current signed installed executable hash matches `dist/Splay.app`
  and is running as `/Applications/Splay.app/Contents/MacOS/Splay`.

- **Splay rebrand installed and launched.** The supplied full Splay icon is the packaged app icon;
  the supplied three-splay mark appears in compact island idle/setup/empty states and the menu bar.
  Island primary/selection/readiness accents now share the restrained lavender/deep-violet Splay
  palette over near-black surfaces; error and warning colors remain semantic red/amber. The app
  bundle displays/executed as `Splay`, but deliberately retains `com.macparakeet.mc` and the
  `MacParakeet-MC` data namespace to preserve existing recordings, settings, and privacy grants.
  `/Applications/Splay.app` deep signature verification and five-second launch stability passed.
  The prior `/Applications/MacParakeet-MC.app` was left untouched. See `docs/BRANDING.md`.

- Island Library and Settings have been replaced locally with purpose-built compact dark pages.
  Library is a single-column saved-recordings list (search, title, date/duration, detail route) and
  excludes remote-video records/categories. Settings now contains only source selection, permission
  status/retry/system-settings actions, plus a small Advanced disclosure for launch/menu-bar
  behavior. Neither page embeds the window-first card/grid views. Release build is installed for
  review; no commit/push.
- Spatial polish is installed too: `IslandLayout.contentInset` is the shared 16pt route inset and
  the adaptive AppKit stage includes the 32pt notch offset plus a 12pt bottom buffer. This prevents
  Home, Library, Settings, and detail controls from clipping or sitting against the rounded edge;
  compact rows/actions maintain 32–46pt minimum hit heights.
- Native motion pass is installed: router mutations, the long-lived panel's anchored frame, and
  route-content crossfades share a restrained 0.32s smooth/ease transition. Reduce Motion uses
  immediate state changes. Automated route-click visual confirmation remains blocked by macOS
  routing synthetic clicks to the app behind the floating panel; the Home reopen morph is visible.
- Setup is now an in-island route, not an old Settings tab. It presents the recommended multilingual
  local Parakeet model (with English-only alternative, quality/speed/size tradeoff), reflects cache
  state, drives the existing warm-up/download/retry service with progress and cancellation, checks
  just the permissions required by the selected recording source, and exposes a final Record now
  action. The signed release build is installed; no commit/push.

- The installed app launches and reopens into the **single expanded island Home panel**, with no
  legacy main window observed. The idle pill is now placed below (not inside) the physical notch.
- A recording health loop polls the service once per second while actively recording. It checks
  engine mode, successful writer append time, in-memory written frames, and output-file byte
  snapshots. A stopped/stalled pipeline (10-second safe threshold) now ends in an explicit island
  error and finalizes partial audio only for recovery; it **does not** transcribe/publish a normal
  completion. Paused capture is explicitly exempt.
- `MeetingRecordingFlowStateMachineTests` passes 18/18, including the new invariant that a capture
  failure is an error rather than a completed transcription. Release build, bundle signature, and
  process launch all passed.
- Synthetic pointer automation can open Home through app reopen, but cannot yet provide a reliable
  Settings/Library click assertion on this desktop because `System Events` sends those coordinate
  clicks to the app behind the floating surface. The host was changed from `nonactivatingPanel` to
  a borderless key-capable panel specifically to eliminate that first-click forwarding path; user
  live verification remains required for the full click loop and a real microphone smoke recording.

Personal fork **MacParakeet-MC**: slimmer, grass-green, **ambient "island"** interface, installed
side-by-side with upstream and **working**. The island is live and the user has live-confirmed it:

- **Idle** = tiny flat grey nub (bottom-center). **Hover** = grows to a 2-line hint
  ("Press **fn** to record" / "Double-tap for calls · Click to open").
- **Recording → Transcribing → Done** lifecycle pill morphs in place (red dot + waveform + timer +
  stop → spinner + bar → ✓ "Saved · N min"), driven by the shared `MeetingRecordingPillViewModel`.
- **Click the nub → expanded "Spotlight card"** grows smoothly *out of the hover pill* (same
  `.smooth` morph, same centered panel): search field (typable) + Record + Mic/Mic+System toggle +
  recents + Settings / Library / Reveal-in-Finder chips. Esc / click-away collapses it back down.
- **Fn** still records (single = mic, double = mic+system); **clicking** the nub opens the card.

## ⚠️ Immediate live state (check first next session)

- `main` has the committed island work at `3cb2d62b` (**Island UI: lifecycle pill + expanded card
  as one morphing surface**). It is currently **one commit ahead of `origin/main`**; do not push
  without the user's instruction.
- **Slice 4 is implemented but uncommitted.** Its exact state and acceptance criteria live in
  `plans/active/island-slice-4-overlays.md`.
- `swift build --skip-update -q` and `git diff --check` passed on 2026-08-05. This verifies the
  active changes compile and contain no whitespace errors; it does not replace live UI testing.
- App installed at `/Applications/MacParakeet-MC.app` includes Slice 4 plus the uncommitted
  top-center placement/color work. The release bundle was built, signed, and signature-verified on
  2026-08-05. The remaining acceptance test is user interaction; synthetic pointer automation
  cannot reliably operate the non-activating island on this machine.
- **Finder path checkpoint passed:** all 7 local meeting records resolve to an existing stored
  `meeting.m4a`; Library, transcript detail, and Meetings share the same guarded reveal action.
  `MeetingAudioFileTests` passed 20/20. A disabled Show in Finder action indicates a missing/stale
  source file, not a routing defect.
- **4 pre-existing test failures** remain (fork rebrand debt, NOT island-related): `AppPathsTests`,
  `MainWindowStateTests.testPrimarySidebarOrderRespectsMeetingFeatureFlag`,
  `AppHotkeyCoordinatorTests.testRefreshAllHotkeysIsSkippedWhileSuspended`, 3×`SettingsViewModelTests`
  default-folder asserts. They fail identically on a clean baseline. A background task was spawned to
  realign them; the island work added **zero** new failures.

## Done & verified this fork so far

- ✅ **Green reskin · nav slim (8→4) · data namespaced (`MacParakeet-MC`) · local install workflow**
  (earlier sessions).
- ✅ **Fn rework** — single-tap = mic-only, double-tap = mic+system; both route through the meeting
  pipeline → saved transcript → auto-export `.md` to `~/Documents/MacParakeet-MC/Meetings/`. ⌘⇧M +
  push-to-talk retired.
- ✅ **Island Chunk A** — `IslandController` + `IslandView` (`Sources/MacParakeet/Views/Island/`):
  one long-lived bottom-center non-activating panel; a single morphing rounded shape (capsule→card)
  with cross-fading content, `.smooth` animation; flat dark fill (NOT frosted glass — user prefers
  understated); old right-center sacred-geometry meeting pill suppressed under
  `islandReplacesDictationPill`.
- ✅ **Island Chunk B** — expanded "Spotlight card" is the `.expanded` morph **state of the same
  pill** (not a separate window). `ExpandedIslandView` is its foreground; the panel becomes key on
  expand so the search field types; Esc/click-away collapses. Chips currently open the **windowed**
  Settings/Library in the committed build.
- ✅ **Island Slice 4 (uncommitted; build-verified)** — Settings and Library chips now summon a
  shared dark floating overlay through `IslandOverlayController`, reusing the same `SettingsView`,
  `TranscriptionLibraryView`, and view models as the main app. Library transcript selection still
  dismisses the overlay and opens the transcript in the main window by design (Slice 7 owns that
  transition). The current overlay is intentionally flat-dark, titled/closable, and explicitly
  dismissed with close/Esc; it stays visible when the user switches apps.
- ✅ **Top-center island layout/color (uncommitted; build + visual verified)** — the shared
  `IslandLayout` now top-anchors the complete lifecycle surface. `IslandController` places the
  fixed stage on the physical display center (`screen.frame.midX`) and below
  `NSScreen.visibleFrame`'s menu-bar boundary. This avoids the 25pt right-shift caused when a
  left-side Dock narrows `visibleFrame`. Idle is near-black in both appearances; active semantic
  red/green states are unchanged. The installed build sits at the MacBook sensor/notch area
  without covering menu-bar controls.

## What's NEXT — remaining island work

Target visuals: `docs/design/final-lookbook.html`. Direction: `docs/fork-product-model.md`.

**Product direction reset (2026-08-05):** use `plans/active/island-only-lean-roadmap.md` as the
active roadmap. The island becomes the primary/sole workflow in phases; do not conflate its basic
meeting recorder with the separate dictation pipeline. First safe implementation slice is hiding
YouTube entry points only, retaining underlying code/data until replacement verification. That
slice is now implemented locally and build-verified; it still needs live review alongside the
uninstalled dark-overlay palette change.

**Surface invariant (user-locked):** the small top-center pill is the idle/resting state of the
same single morphing `IslandPanel` as the authoritative expanded black panel. It must never open
a separate overlay/window. Library, Settings, detail, export, recording, transcribing, done, and
optional live preview are router substates inside this one adaptive surface; Back/Close returns
within it, normally to the idle pill.

**Unified-host progress:** Home, Library, and the existing full SettingsView now route inside the
long-lived island panel (build-verified). This is not yet the finished island-only product:
transcript detail/export/reveal and removal of obsolete overlay/window callbacks remain.

1. **Finish combined Slice 4 + top-center review** — have the user live-test the installed build:
   confirm the top position is comfortable and does not block the menu bar, then open the island, Settings,
   Library, search/type in both, repeatedly close/reopen and switch between them, close with Esc and
   close control, switch apps and return, select a transcript (which must open the main-window
   detail), and invoke every available Show in Finder action from Library/transcript contexts. If
   accepted, commit the six active files and update the plan to COMPLETE.
2. **Settings cleanup (slice 5)** — drop the now-inert push-to-talk + ⌘⇧M rows.
3. **Retire the main window (slice 6)** — once overlays stand alone.
4. **Transcript/summary layering (slice 7, separate track)** — verbatim + **Flag** pass, Distill/Decide
   as summary ops, **drop Polish**, stacked positional hotkeys.
5. **Glassiness (deferred polish)** — current fill is intentionally flat dark (`Color(white:0.13)`).
   Real `NSVisualEffectView` vibrancy bled past rounded corners; if revisited, round it via
   `maskImage`, not SwiftUI `.clipShape`.

## Tribal knowledge / gotchas (hard-won this session)

- **★ COPY WORKING ELEMENTS BEFORE REINVENTING.** AppKit floating-panel click/render/animation is a
  minefield; every island fix came from copying an existing *working* element and adjusting its
  properties — not hand-rolling. When something UI-ish doesn't work, find the element in this app that
  already does it and copy that first.
- **Island click delivery (the big one):** the host must be a borderless, key-capable panel—not a
  `nonactivatingPanel`, which can forward a first click to the app behind it. Idle interaction also
  uses an **`NSEvent` global/local monitor** (see `IslandController.installClickMonitors`). A `hitTest` that returns the **contentView itself** is
  treated as a window-background click and drops `mouseDown` — the hit target must be a **subview**
  (mirrors the meeting pill's `PillContentView`).
- **Clean rounded card = a titled window.** The expanded card reads clean because chrome (rounded
  corners + shadow) is **OS-drawn** — borderless + hand-drawn shadow/`compositingGroup` cast a visible
  rectangle. But for the **morph** we render the card in the **same ambient panel** as a SwiftUI
  `.expanded` state (not a window), so it grows with the identical `.smooth` curve as hover. (The
  earlier separate-window approach `flew in` / mis-centered — superseded.)
- **The morph trick:** one `RoundedRectangle(cornerRadius: min(height/2, 20))` = capsule at small
  heights, 20pt card when large → morphs capsule↔card as the frame animates. `IslandLayout` is the
  single source of truth for sizes; the AppKit tracker derives hit-rects from it.
- **`.expanded` wins in `IslandLayout.visual(...)`**; `IslandChromeModel.isExpanded` drives it; the
  tracker steps aside (`hitTest → nil`) when expanded so SwiftUI controls get clicks.
- **Decorative waveform** in the recording pill is self-animating (TimelineView), NOT metered audio —
  matches the lookbook.
- **`os_log` `.info` is not persisted** — use `.notice`+ for `log show` to retrieve it. (All island
  diagnostic logging was stripped before commit.)
- **xcodebuild is BROKEN here.** Use `swift build` + `scripts/dev/install_local.sh` (release build
  ~5–10 min, signs, installs to `/Applications/MacParakeet-MC.app`) → `open` it. Only the **user can
  live-test** the panel behavior — build, install, hand off.

## Authoritative references (read to resume)

- `Sources/MacParakeet/Views/Island/` — `IslandView.swift` (states + morph + layout),
  `IslandController.swift` (panel, tracking, click monitors, expand/collapse, key handoff),
  `ExpandedIslandView.swift` (card foreground).
- `Sources/MacParakeet/App/AppEnvironmentConfigurer.swift` — where the island is created + wired
  (record/select/settings/library/reveal callbacks). `AppDelegate.swift` retains it.
- `plans/active/island-slice-4-overlays.md` — **current execution state and acceptance boundary**.
  `Sources/MacParakeet/Views/Island/IslandOverlayController.swift` — Slice 4 panel host;
  `AppWindowCoordinator.swift` — overlay construction and Library → main-window transition.
- `plans/active/island-slice-5-top-center.md` — placement/color work layered on top of Slice 4;
  `IslandView.swift` / `IslandController.swift` own its geometry and screen placement.
- `docs/fork-product-model.md` — north star. `docs/design/final-lookbook.html` — visual target.
- Auto-memory: `~/.claude/projects/-Users-mathewcleveland-macparakeet-MC/memory/`.

## Working style (user preferences)

- **Copy working UI/effects elements before reinventing the wheel** (stated explicitly, and proven out
  this session).
- Prefers **understated/flat** over heavy frosted glass for the ambient surfaces.
- Open, exploratory conversation; builds in installable slices and live-tests each personally.
- Firm principle: **a transcript is never polished; only a summary can be.**
