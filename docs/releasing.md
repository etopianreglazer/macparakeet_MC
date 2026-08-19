# Releasing Splay — first-release guide

> Status: **ACTIVE**. Written 2026-08-18 for the first public release.
> The gate that decides *whether* to release is `docs/launch-checklist.md`. This file is
> the *mechanics* of doing it. Replaces `docs/distribution.md` (upstream's R2 flow), which
> does not apply to Splay.

Splay ships as a **notarized DMG attached to a GitHub Release**, with a Sparkle appcast
served from GitHub Pages for in-app updates.

Your values, already confirmed on this machine:

| Thing | Value |
|---|---|
| Apple Team ID | `76K8473JHR` |
| Signing identity | `Developer ID Application: Mathew Cleveland (76K8473JHR)` (created 2026-08-19, expires 2027-02-01) |
| GitHub account | `etopianreglazer` |
| Sparkle public key | `UjG8RmU9eOGL2ZNFdfc72QUhFH5z6KgYWTYBgmRJ6no=` |
| Sparkle private key | in your login keychain (service `https://sparkle-project.org`, account `ed25519`) |
| Bundle id | `com.macparakeet.mc` (kept deliberately — see `docs/BRANDING.md`) |

---

# Part 1 — One-time Apple setup

**These steps are yours to do — they involve your Apple account and a password, so do them
yourself rather than having an agent do them.**

> **Steps 1.1–1.3 are DONE** (2026-08-19). The certificate exists, signs cleanly, and
> obtains an Apple secure timestamp. Kept below for the next time — and for re-issuing
> when it expires on 2027-02-01.

### 1.1 Confirm you have the *paid* Developer Program

A free Apple ID is not enough. Developer ID certificates require the **Apple Developer
Program** ($99/year), and your account needs the **Account Holder** or **Admin** role.
Check at [developer.apple.com/account](https://developer.apple.com/account) — if you see
"Certificates, Identifiers & Profiles", you are enrolled.

> Right now you only hold `Apple Development: clevelandmathew@googlemail.com`. That is a
> *development* certificate: it runs the app on your own machine only. Anyone else who
> downloads it gets blocked by Gatekeeper. You need a **Developer ID Application**
> certificate, which is a different thing.

### 1.2 Create a Certificate Signing Request

> **Shortcut, used here:** with full Xcode installed, skip the manual CSR entirely.
> **Xcode → Settings → Accounts →** select the team **→ Manage Certificates… → + →
> Developer ID Application.** Xcode makes the keypair, sends the CSR, and installs the
> certificate with its private key into the login keychain. The manual route below is the
> fallback when Xcode is not available.

1. Open **Keychain Access**.
2. Menu: **Keychain Access → Certificate Assistant → Request a Certificate From a
   Certificate Authority…**
3. Enter your email and name. Select **Saved to disk**. Leave CA Email empty.
4. Save as `SplayCSR.certSigningRequest`.

### 1.3 Request the Developer ID Application certificate

1. Go to [developer.apple.com/account/resources/certificates/list](https://developer.apple.com/account/resources/certificates/list).
2. Click **+**.
3. Choose **Developer ID Application**. (Not "Mac Development", not "Developer ID Installer".)
4. Upload `SplayCSR.certSigningRequest`.
5. Download the resulting `.cer` and **double-click it** to install into your login keychain.

Verify — you should now see a second identity:

```bash
security find-identity -v -p codesigning
```

You are looking for a line containing `Developer ID Application: ... (76K8473JHR)`.

### 1.4 Create an app-specific password for notarization

Notarization needs to authenticate to Apple. Never use your main Apple ID password.

1. Go to [account.apple.com](https://account.apple.com) → **Sign-In and Security** →
   **App-Specific Passwords**.
2. Generate one, name it `notarytool`, and copy it.

### 1.5 Store the notarization credentials in your keychain

Run this yourself and paste the app-specific password when prompted:

```bash
xcrun notarytool store-credentials "splay" --apple-id "clevelandmathew@googlemail.com" --team-id "76K8473JHR"
```

Verify it works:

```bash
xcrun notarytool history --keychain-profile "splay"
```

An empty history is a success — it means Apple accepted the credentials.

---

# Part 2 — One-time GitHub setup

### 2.1 The repository

The code currently lives at `etopianreglazer/macparakeet_MC`, which is a fork of
`moona3k/macparakeet`. Two things to decide before going public:

- **Name.** `macparakeet_MC` does not read as its own project. `splay` does. Renaming on
  GitHub keeps redirects working.
- **Fork relationship.** A GitHub fork shows "forked from moona3k/macparakeet" and its
  issues/stars behave like a fork's. To present Splay as its own project you generally
  want a **standalone repo**, not a fork — GitHub Support can detach a fork, or you can
  push the history into a fresh repo. Either way, keep the git history: it is the honest
  record of the derivation, and GPL-3.0 wants your changes attributable.

> Detaching or renaming is your call to make — it is outward-facing and I have not touched
> your remotes.

### 2.2 GitHub Pages for the appcast

The bundle now points Sparkle at `https://etopianreglazer.github.io/splay/appcast.xml`.
To serve that: repo **Settings → Pages → Source: Deploy from a branch**, pick `main` and
`/ (root)` (or `/docs`). Then `appcast.xml` at the repo root becomes that URL.

If you rename the repo to something other than `splay`, update `SUFeedURL` in
`scripts/dist/build_app_bundle.sh` to match.

---

# Part 3 — Cutting a release

Everything below is repeatable and scriptable.

### 3.1 Pre-flight

```bash
swift test
```

Expect the 7 known environmental failures and nothing else (see the launch checklist).

Decide the version. This is Splay's **first** release, and the current
`CFBundleShortVersionString` of `0.6.0` is inherited from upstream. Starting at `0.1.0`
says "this is a new project at its beginning", which is both true and what you want if
Splay is not presenting as a MacParakeet fork.

### 3.2 Build the app bundle

```bash
APP_NAME=Splay BUNDLE_ID=com.macparakeet.mc VERSION=0.1.0 scripts/dist/build_app_bundle.sh
```

### 3.3 Sign and notarize

```bash
APP_NAME=Splay SIGN_IDENTITY="Developer ID Application: Mathew Cleveland (76K8473JHR)" NOTARYTOOL_PROFILE=splay scripts/dist/sign_notarize.sh
```

This signs every nested binary, submits to Apple, waits for the verdict, staples the
ticket, builds the DMG, signs and notarizes that too. Notarization usually takes 2–15
minutes. A rejection comes back with a log URL that names the offending binary.

**Watch for:** the bundled `yt-dlp` is a PyInstaller binary and needs
`com.apple.security.cs.disable-library-validation`. Without it, fresh installs fail at
first YouTube use with a Team ID mismatch. The script handles this — just don't "clean it up".

### 3.4 Verify before you publish

```bash
spctl -a -vv -t install dist/Splay.app
xcrun stapler validate dist/Splay.app
codesign -dv --verbose=2 dist/Splay.app 2>&1 | grep -E "Authority|TeamIdentifier"
```

You want `source=Notarized Developer ID` and `accepted`. If you see `Apple Development`
in the authority, you signed with the wrong identity.

The real test: **copy the DMG to a different Mac** (or a fresh user account) and open it.
That is the only way to know a stranger's first launch works.

### 3.5 Sign the DMG for Sparkle

```bash
.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Splay.dmg
```

This prints `sparkle:edSignature` and `length`. Keep both.

> **The file you sign must be the exact file you upload.** If you rebuild the DMG after
> signing, the signature no longer matches and Sparkle rejects the update as improperly
> signed. Sign last, upload that file, change nothing.

### 3.6 Publish the GitHub Release

```bash
gh release create v0.1.0 dist/Splay.dmg --title "Splay 0.1.0" --notes "First release."
```

Add `--draft` to review it before it goes public. Copy the DMG's download URL from the
release page — you need it for the appcast.

### 3.7 Update the appcast

Create/edit `appcast.xml` at the repo root and **prepend** a new `<item>` (keep the older
ones — Sparkle shows notes for every version newer than the user's):

```xml
<item>
  <title>0.1.0</title>
  <pubDate>PASTE_OUTPUT_OF_date_-R</pubDate>
  <sparkle:version>BUILD_NUMBER_FROM_INFO_PLIST</sparkle:version>
  <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.2</sparkle:minimumSystemVersion>
  <description><![CDATA[<p>First release.</p>]]></description>
  <enclosure
    url="https://github.com/etopianreglazer/splay/releases/download/v0.1.0/Splay.dmg"
    length="LENGTH_FROM_SIGN_UPDATE"
    type="application/x-apple-diskimage"
    sparkle:edSignature="SIGNATURE_FROM_SIGN_UPDATE" />
</item>
```

Commit and push; GitHub Pages serves it within a minute or two. Verify:

```bash
curl -s "https://etopianreglazer.github.io/splay/appcast.xml" | head -20
```

`sparkle:version` must be the **build number** (`CFBundleVersion`), not the short version —
Sparkle compares builds to decide whether an update exists.

---

### 3.3a If signing fails with `errSecInternalComponent`

```
Downloader.xpc: errSecInternalComponent
```

This is **not** a problem with your bundle or the script. It means `codesign` could not
use the private key because the key's keychain ACL wants interactive confirmation, and
the process had no way to show the prompt. The tell: the identical command **works when
run in a foreground terminal and fails when run in the background, over ssh, or from CI.**

One-time fix — authorise the Apple tools to use the key without prompting:

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db
```

It prompts for your **login (Mac) password** — leave `-k` off, as above, so the password
never lands in shell history. You will likely get a "want to allow access" dialog as well;
choose **Always Allow**.

Then re-run step 3.3. This is a per-keychain, per-key setting: do it once after creating
the certificate and it holds until you create a new one.

Symptoms that look similar but are not this:
- *"The specified item could not be found in the keychain"* — the identity string in
  `SIGN_IDENTITY` does not match. Copy it verbatim from `security find-identity`.
- *"ambiguous (matches multiple identities)"* — you have two certs with the same name;
  pass the SHA-1 hash instead of the name.

# Part 4 — First-release-only gotchas

- **There is no upgrade path to test yet.** With one release, Sparkle has nothing to
  compare against. The update flow is genuinely exercised only at release #2 — so treat
  0.2.0 as the moment you verify auto-update actually works, and keep 0.1.0 installed
  somewhere to update *from*.
- **Gatekeeper caches verdicts.** If you test a rejected build and then fix it, test the
  fixed one from a fresh download path, not the same file location.
- **Never reuse a build number.** Sparkle and macOS both key off it.
- **The private Sparkle key exists in exactly one place** — your login keychain. If you
  lose it you cannot ship an update that existing installs will accept; they would all
  have to reinstall manually. Export a backup and store it somewhere safe:
  ```bash
  ./.build/artifacts/sparkle/Sparkle/bin/generate_keys -x splay-sparkle-private-key.txt
  ```
  Put that file somewhere private. It must **never** be committed.

---

# Part 5 — Quick reference

```bash
# 1. test
swift test

# 2. build
APP_NAME=Splay BUNDLE_ID=com.macparakeet.mc VERSION=X.Y.Z scripts/dist/build_app_bundle.sh

# 3. sign + notarize + DMG
APP_NAME=Splay SIGN_IDENTITY="Developer ID Application: Mathew Cleveland (76K8473JHR)" NOTARYTOOL_PROFILE=splay scripts/dist/sign_notarize.sh

# 4. verify
spctl -a -vv -t install dist/Splay.app && xcrun stapler validate dist/Splay.app

# 5. sign for Sparkle (keep the output)
.build/artifacts/sparkle/Sparkle/bin/sign_update dist/Splay.dmg

# 6. publish
gh release create vX.Y.Z dist/Splay.dmg --title "Splay X.Y.Z" --notes "..."

# 7. appcast: prepend an <item>, commit, push, verify
curl -s "https://etopianreglazer.github.io/splay/appcast.xml" | head -20
```
