# libghostty-spm — Agent Conventions

> Operational conventions for human + AI contributors. `README.md` is
> the overview; this is the directive "how to work here" + the
> hard-won knowledge that must not be rediscovered.

## What this repo is

A binary SwiftPM package that wraps Ghostty's **libghostty** (terminal
renderer + input + parser + the embeddable surface C API) as a
prebuilt, checksummed `GhosttyKit.xcframework` published via GitHub
releases. A companion `GhosttyKitResources` product ships libghostty's
runtime resource tree (terminfo sentinel + shell-integration + themes)
**in-repo** via `Bundle.module` — not a release asset. Consumers
`import GhosttyKit` + `import GhosttyKitResources` and never build zig
or Ghostty. This repo exists so the fragile libghostty build is solved
**once, here**, not on every consumer machine/CI.

The tracked tree under `Sources/GhosttyKitResources/Resources/` is
**build-generated, never hand-edited**: `build-xcframework.sh` wipes
and regenerates it from `vendor/ghostty/zig-out/share` every build, so
`git diff` after a build is the authoritative signal of Ghostty
resource drift on a pin bump. Commit the diff with the pin bump.

## Non-negotiable build facts (do not "simplify")

Every build flag and toolchain choice below cost real debugging time.
Changing any of them silently produces a libghostty that links but
lacks the embedding C API.

- **zig: Homebrew `zig@0.15` only.** The vanilla ziglang.org 0.15.2
  tarball and asdf/mise installs **cannot link the macOS 26 SDK**
  (bundled libSystem stubs predate the SDK tbd dropping plain
  `arm64-macos`). Homebrew's build patches this; Ghostty's own Nix
  devShell pins the brew variant for the same reason. `brew install
  zig@0.15`.
- **Metal Toolchain** is a separate Xcode 26 component:
  `xcodebuild -downloadComponent MetalToolchain`.
- **Build flags** (`scripts/build-xcframework.sh`): `-Doptimize=
  ReleaseFast -Dstrip=false -Demit-xcframework=true -Dxcframework-
  target=native`. `-Dstrip=false` is mandatory (ReleaseFast strips
  the archive, deleting the embedding symbols). Do **not** add
  `-Demit-macos-app=false`: the full embedding lib is only assembled
  when the macOS-app path runs.
- **The Ghostty.app `Ld` step fails** on the macOS 26 SDK
  (`SwiftUICore` restricted, xcodebuild exit 65). This is expected and
  tolerated — the xcframework is produced *before* that failure. The
  script `set +e`s the zig build and **gates on a symbol check**
  (`nm … ' T _ghostty_surface_new$'`). Trust the gate, not zig's exit
  code. If the gate fails the build is wrong — fix flags, do not
  loosen the gate.
- **Never vendor a third-party prebuilt** (e.g. another project's
  xcframework). We build from pinned source. The whole point.

## Source + pin

`vendor/ghostty` is a git submodule; **the gitlink commit is the
pin** — no version file. `git submodule update --init vendor/ghostty`
checks out exactly the built commit. Bump: checkout a new commit in
the submodule, `git add vendor/ghostty`, cut a release. Treat every
bump as a `ghostty.h` API audit (the C API is unversioned upstream).
If a bump changes Ghostty's required zig minor, install the matching
keg-only Homebrew formula and update the version check in the build
script.

## Versioning

Independent package SemVer (`vX.Y.Z`), **not** Ghostty's version.
Soft rule: MINOR bump on a Ghostty pin change, PATCH on package-only
fixes. `GHOSTTY_VERSION` (written by the build, tracked, embedded in
release notes) is the one-lookup map package-tag → exact Ghostty.

## Releases

`.binaryTarget(url:checksum:)` needs an asset that doesn't exist until
published — resolved per tag. `make release TAG=vX.Y.Z`: builds,
ditto-zips, `swift package compute-checksum`, `gh release`. Releases
are built and published **locally** — there is no release CI (the
Ghostty app-link race cannot be won on an ephemeral runner; see
"Build reality"). Commit the printed `repoSlug` /
`releaseTag` / `checksum` into `Package.swift` **on that tag**. The
zip MUST be made with `ditto` (framework-safe), not `zip -r`.

Two release gates, both in `release.sh`, enforcing one invariant —
*committed tree == built tree == the Ghostty the published binary was
built from*: (1) the embedding-symbol `nm` check on the frozen `dist/`
xcframework; (2) a resources-sync check that fails if the build
regenerated `Sources/GhosttyKitResources/Resources` differently from
the committed tree. On a Ghostty pin bump you MUST commit the
regenerated resource diff onto the release tag — the binary is a
release asset but the resources ship from the tagged source, so an
uncommitted diff publishes a binary paired with stale resources.

## Build reality (read before "fixing" the gate)

The build is reproducible — it reliably produces a correct
`libghostty-internal-fat.a` (~165MB, ~101 ghostty symbols incl.
`ghostty_surface_new`). What is NOT reliable is observing completion
*from inside the build script*: Ghostty's `Ld Ghostty.app` step fails
(xcodebuild exit 65) in any non-Ghostty-CI env, aborting `zig build`,
and the xcframework's libtool combine is left **orphaned**, finalizing
the lib minutes later — its completion is decoupled from the build
command. Every in-build gate variant (long poll, size-stability,
lsof-quiesce) loses the same race; the lib is correct seconds-to-
minutes after. This is the documented behavior, not a bug to re-chase.

Consequence: `build-xcframework.sh` only **warns** on the symbol
check. The authoritative pass/fail gate is in `release.sh`, run
against the **frozen `dist/` copy** (a static snapshot → deterministic).
Manual release flow when a build races: wait for it to fully settle
(`lsof +D vendor/ghostty/macos` shows nothing; the lib has
`ghostty_surface_new`), then re-run `make release` — never publish a
libghostty missing the embedding C API.

## Commit messages

Subject ≤ 50 chars, capitalized, imperative, no trailing period;
blank line before body; body wrapped at 72. Enforced by
`.githooks/commit-msg`. Activate once: `make hooks`. Never `--no-verify`.

## Dev surface

`make hooks | submodule | build | release TAG=…`. Don't add a build
system beyond the two scripts + Makefile; this repo is intentionally
small.
