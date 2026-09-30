# .space

Everything that makes this fork differ from [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast).
`main` is never edited by hand beyond this folder: it is regenerated as *upstream main + these patches*.

| File | What it does |
| --- | --- |
| `patches/0001-alias-space.patch` | An exact, case-sensitive user alias + Space opens its entry: rows with inline arguments focus the first field, everything else runs (apps and settings panes keep searching). A backslash right before the Space escapes it into a plain space. |
| `patches/0002-updater-and-links.patch` | The in-app updater and the About link point at this fork; About shows a "✨ Space Edition" chip and reads "Tinycast Space Edition". |
| `patches/0004-querystring-node-coercion.patch` | Extension runtime: `querystring.stringify` coerces `undefined`/`null` to `""` like Node. Without it google-auth-library sends `client_secret=undefined` and Google answers `invalid_client` for any client without a secret (e.g. 2FA Code Finder's Gmail sign-in). `apply.sh` rebuilds `RaycastRuntime.generated.js` after it. |
| `patches/0005-external-hyper-glyph.patch` | Settings → General → Hyper Key: with Hyper Key set to None, "Show ✦ for another app's Hyper key" collapses the Hyper chord to ✦ anyway (for Karabiner/Hyperkey-style remappers) and keeps Include Shift editable. |
| `patches/0006-inline-alias-shortcut-editing.patch` | ⌘K on a launcher entry gains *Change Alias* and *Change Shortcut* rows that edit in place (extension commands included). Ported from [jhasubhash/tinycast](https://github.com/jhasubhash/tinycast/commit/f509d005) (AGPL-3.0); everything lives in the new `InlineEntryEditor.swift`, the rest is one-line hooks marked `tinycast-space`. `apply.sh` regenerates `project.pbxproj` with XcodeGen for the added file instead of patching it. |
| `patches/0008-buffer-blob-file.patch` | Extension runtime: `require("buffer")` exposes `Blob` and `File`, as Node's does. Undici subclasses them, so extensions bundling it (Google Translate) crashed on load with "The superclass is not a constructor". |
| `patches/0009-undici-fetch-dispatcher.patch` | Extension runtime: a bundled undici finds a dispatcher already installed in its global slot (`Symbol.for("undici.globalDispatcher.1")`) that sends every request through Tinycast's `fetch` bridge, so it never reaches for `net` (no sockets, no Node). `stream` gains Node's `isDisturbed`/`isErrored`/`isReadable` probes, which undici asks before reading a body. Google Translate is the reference case. If undici ever renames the slot, it falls back to the old "`net.isIP` is not supported" error, nothing worse. |
| `README.fork.md` | Becomes the repository's `README.md`; `apply.sh` keeps upstream's README verbatim as `README.upstream.md` with a one-line note on top. Never a patch, so upstream README edits can't conflict. |
| `patches/0007-confetti.patch` | Confetti as a system action and as `raycast://confetti`, drawn by the new `ConfettiOverlay.swift` with `CAEmitterLayer` (plus the undocumented `plane` particle type and `drag`/`wave` behaviours the effect needs, each applied defensively). Tunable live through `confetti.*` defaults. |
| `apply.sh` | Applies the patches in order with `git apply --3way`, then points any upstream releases-page link (the Changelog menu item) at this fork, relaxes the system-action harness's hard-coded catalog size (patch 0007 adds one) — a rewrite, not a patch, so a tag without that link still applies. |
| `gate.sh` | Release build + upstream's `Scripts/run-tests.sh`. A harness that also fails on the pristine upstream commit is ignored. |
| `report.sh` | Opens / closes the "blocked" issue. |
| `UPSTREAM` | The upstream commit `main` was last built from. |

## Automation

- **`space-sync.yml`** — every 10 minutes checks upstream `main`. On a new commit (or a manual commit on top
  of the generated one) it rebuilds `main` = upstream + patches on macOS, builds, runs the tests and
  force-pushes `main`. On failure nothing is pushed and a `space-sync` issue is opened.
- **`space-release.yml`** — twice an hour checks upstream's latest stable release. For a tag not yet released
  here it applies the patches to that tag, builds, tests, signs with this fork's `Tinycast Self-Signed`
  identity and publishes the same tag with a DMG and the zip the in-app updater installs.

Upstream's own workflows (`release.yml`, `website*.yml`, `triage.yml`, `coauthors.yml`) are disabled in this
repository's Actions settings.

Secrets: `SIGNING_P12_BASE64`, `SIGNING_P12_PASSWORD` (the signing identity, never rotate it casually —
installed copies only accept updates signed with the same certificate) and `SPACE_PUSH_TOKEN`
(fine-grained token for this repository: Contents + Workflows read/write).

## Changing the patch

Edit the code on `main`, regenerate the affected file with `git diff <upstream-sha> -- <paths> > .space/patches/…`,
commit, and push; the next sync run rebuilds `main` from upstream with the new patch.
