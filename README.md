# libghostty-spm

[Ghostty](https://github.com/ghostty-org/ghostty)'s terminal engine —
renderer, input, parser, and the embeddable surface C API — packaged
as a SwiftPM binary dependency for Apple-platform apps.

Consumers add this package and `import GhosttyKit`; SwiftPM fetches a
prebuilt, checksummed `GhosttyKit.xcframework` from a GitHub release.
libghostty's runtime resource tree (terminfo sentinel +
shell-integration + themes) ships in-repo via the companion
`GhosttyKitResources` product (`Bundle.module`) — no separate asset to
fetch. **No zig, no Ghostty source, no local build on the consumer
side.**

## Why this exists

libghostty is only buildable from source with a very specific
toolchain, and that build is fragile on current macOS:

- Ghostty pins an exact zig minor (0.15.x for the pinned commit). The
  vanilla ziglang.org 0.15.2 tarball — and asdf/mise installs —
  **cannot link against the macOS 26 SDK**: their bundled libSystem
  stubs predate the SDK tbd change that dropped plain `arm64-macos`.
  **Homebrew's `zig@0.15` build patches this**; Ghostty's own Nix
  devShell pins the brew variant for the same reason.
- Xcode 26 split the Metal compiler into a separate component
  (`xcodebuild -downloadComponent MetalToolchain`).
- The full libghostty static lib that exports the embedding C API is
  only assembled when Ghostty's macOS *app* build runs; that app fails
  to link on the macOS 26 SDK (`SwiftUICore` is now restricted), but
  the xcframework is produced *before* that failure. The build script
  tolerates the app-link failure and gates on a symbol check.

This package solves all of that **once**, here, instead of on every
consumer's machine and CI.

## Layout

```
Package.swift                 products: GhosttyKit (.binaryTarget url+checksum),
                              GhosttyKitResources (in-repo, Bundle.module)
Sources/GhosttyKitResources/  tracked resource tree, regenerated each build
vendor/ghostty/               git submodule @ pinned commit — source + pin
patches/                      local Ghostty changes, applied per build
scripts/build-xcframework.sh  brew zig@0.15, the load-bearing flags, symbol gate
scripts/release.sh            build → ditto-zip → compute-checksum → gh release
```

The submodule gitlink **is** the Ghostty pin — git-native, no version
file. `git submodule update --init vendor/ghostty` checks out exactly
the built commit.

Changes this package makes to Ghostty live in `patches/`, not in the
submodule. The build applies them and reverts them on exit, so the
gitlink always names a real upstream commit. See `patches/README.md`.

## Building locally

```sh
brew install zig@0.15
xcodebuild -downloadComponent MetalToolchain   # after every Xcode update
git submodule update --init vendor/ghostty
./scripts/build-xcframework.sh                 # → dist/GhosttyKit.xcframework
```

First cold build is several minutes (zig + Metal shaders). The script
fails fast (one second) if the produced lib lacks the embedding C API.

## Versioning

Package tags are **independent SemVer** (`vX.Y.Z`), not Ghostty's
version — Ghostty's pinned point is often an unreleased main commit
(no clean version to mirror) and the package has its own lifecycle
(build/script/resource fixes ship independently). Soft convention:

- **MINOR** bump when the Ghostty pin changes.
- **PATCH** bump for package-only fixes (build script, resources).

Traceability is exact and one lookup: every build writes a tracked
`GHOSTTY_VERSION` (`git describe` + full commit, e.g.
`v1.3.1-927-ge90b7c9f`), and each GitHub release's notes embed it. So
package tag → exact Ghostty is never ambiguous even though the numbers
don't match.

## Cutting a release

`.binaryTarget(url:checksum:)` needs an asset that doesn't exist until
the release is published — resolved by pinning per tag:

1. `git submodule update --init vendor/ghostty` (verify the intended
   Ghostty commit).
2. `./scripts/release.sh vX.Y.Z` — builds, zips, computes the checksum,
   and (with `gh`) creates the `vX.Y.Z` release with
   `GhosttyKit.xcframework.zip` (the only asset — resources ship
   in-repo, not as a release asset).
3. Commit the printed `repoSlug` / `releaseTag` / `checksum` into
   `Package.swift` **on the `vX.Y.Z` tag** (move the tag to that commit).
4. Consumers pin `.package(url: ..., exact: "vX.Y.Z")`.

## Bumping Ghostty

```sh
cd vendor/ghostty && git fetch origin && git checkout <new-commit>
cd ../.. && git add vendor/ghostty
make build    # applies patches/ in order; names the first that fails
```

Regenerate any patch the build reports as stale, then cut a new
release. Treat every bump as a `ghostty.h` API audit — upstream is
explicit that the libghostty C API is not yet versioned.
If a bump changes Ghostty's required zig minor, install the matching
keg-only Homebrew formula and update the version check in
`scripts/build-xcframework.sh`.

## Consuming

```swift
.package(url: "https://github.com/sethdeckard/libghostty-spm", exact: "vX.Y.Z")
// target deps: "GhosttyKit", "GhosttyKitResources"
```

`GhosttyKit` is the upstream module (umbrella header `ghostty.h`).
`GhosttyKitResources` ships the runtime resource tree (`terminfo`
sentinel + shell-integration + themes) inside the package:

```swift
import GhosttyKitResources
// directory containing terminfo/ and ghostty/{shell-integration,themes}
let dir = GhosttyKitResources.directoryURL
```

Point libghostty at `dir` (via `GHOSTTY_RESOURCES_DIR` or the surface
config). No asset download, no extraction step.

## License

MIT (`LICENSE`), matching Ghostty. That covers the packaging authored
here — the build and release scripts, `Package.swift`, the resources
target, and the docs.

`THIRD-PARTY-NOTICES.md` reproduces Ghostty's copyright notice and
lists what the xcframework and resource tree carry with them — read it
before shipping an app. Most components are MIT or BSD-style, though
several attach conditions of their own (Apache-2.0, MPL-2.0, OFL-1.1,
CC BY). Two merit special attention because they can affect what you
ship: a few Kitty-derived shell-integration scripts are GPL-3.0, and
`libintl` is statically linked under LGPL. Those apply whatever your
app is licensed as; a copyleft app just tends to satisfy them
incidentally. Neither changes this package's license.
