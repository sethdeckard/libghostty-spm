#!/usr/bin/env bash
# scripts/build-xcframework.sh — build GhosttyKit.xcframework from the
# pinned Ghostty submodule.
#
# Source + pin: vendor/ghostty (git submodule; the gitlink commit IS
# the pin — run `git submodule update --init vendor/ghostty` first)
# PLUS patches/, applied to that commit for the duration of this build
# and reverted on exit. See patches/README.md.
# Output: dist/GhosttyKit.xcframework (gitignored build artifact) +
# Sources/GhosttyKitResources/Resources/ (tracked — the resource tree
# ships in-repo via the GhosttyKitResources SwiftPM target, so every
# build regenerates it and `git diff` surfaces any Ghostty drift).
#
# Requires: Homebrew zig@0.15. The vanilla ziglang.org 0.15.2 tarball
# (and asdf/mise installs) cannot link against the macOS 26 SDK — its
# bundled libSystem stubs predate the SDK tbd change that dropped
# plain `arm64-macos`. Homebrew's zig build patches this; Ghostty's
# own Nix devShell pins the brew variant for the same reason.

set -euo pipefail

cd "$(dirname "$0")/.."

GHOSTTY_DIR="vendor/ghostty"
# The xcframework target writes into the Ghostty tree's macos/ dir
# (for its Xcode project), NOT zig-out/. zig-out/ only gets the
# separate libghostty-vt dylib + the share/ resource tree.
ARTIFACT_SRC="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
ARTIFACT_DEST="dist/GhosttyKit.xcframework"
RESOURCE_SRC="$GHOSTTY_DIR/zig-out/share"
# Tracked, NOT under dist/: the resource tree ships inside the package
# (GhosttyKitResources target → Bundle.module), so it must live in the
# committed source tree, regenerated each build.
RESOURCE_DEST="Sources/GhosttyKitResources/Resources"

say()  { printf "build-xcframework: %s\n" "$1"; }
fail() { printf "build-xcframework: error: %s\n" "$1" >&2; exit 1; }

# ── Preflight ──────────────────────────────────────────────────────────
[ -f "$GHOSTTY_DIR/build.zig" ] \
    || fail "$GHOSTTY_DIR is empty — run 'git submodule update --init vendor/ghostty'"
PIN=$(git rev-parse --quiet HEAD:"$GHOSTTY_DIR" 2>/dev/null || echo unknown)
HEAD=$(git -C "$GHOSTTY_DIR" rev-parse HEAD 2>/dev/null || echo unknown)
[ "$PIN" = "unknown" ] || [ "$PIN" = "$HEAD" ] \
    || fail "submodule HEAD ($HEAD) != pinned gitlink ($PIN) — 'git submodule update vendor/ghostty'"
DESCRIBE=$(git -C "$GHOSTTY_DIR" describe --tags --always 2>/dev/null || echo unknown)

# ── Patches ────────────────────────────────────────────────────────────
# vendor/ghostty tracks upstream exactly; local engine changes live as
# patch files here and are applied for this build only, then reverted by
# the EXIT trap. That is what keeps `git submodule status` honest — the
# gitlink never carries a commit no remote has — so GHOSTTY_VERSION
# records the patch list as part of the pin.
PATCHES=()
while IFS= read -r patch_file; do
    [ -n "$patch_file" ] && PATCHES+=("$patch_file")
done < <(find "$PWD/patches" -maxdepth 1 -name '*.patch' 2>/dev/null | sort)

if [ "${#PATCHES[@]}" -gt 0 ]; then
    PATCH_NAMES=""
    for patch_file in "${PATCHES[@]}"; do
        PATCH_NAMES="${PATCH_NAMES:+$PATCH_NAMES }$(basename "$patch_file")"
    done
else
    PATCH_NAMES="none"
fi

# Tracked traceability: package tags are independent SemVer; this
# records exactly which Ghostty (and which patches on top of it) each
# build/release maps to.
printf 'ghostty: %s\ncommit:  %s\npatches: %s\n' \
    "$DESCRIBE" "$HEAD" "$PATCH_NAMES" > GHOSTTY_VERSION
say "Ghostty submodule @ $DESCRIBE ($HEAD)"
say "patches: $PATCH_NAMES"

if [ "${#PATCHES[@]}" -gt 0 ]; then
    # A dirty worktree means an earlier run died before its trap fired,
    # or someone edited the submodule by hand. Either way the patches
    # below would apply on top of unknown state, so refuse rather than
    # guess.
    [ -z "$(git -C "$GHOSTTY_DIR" status --porcelain)" ] \
        || fail "$GHOSTTY_DIR has local changes — capture them as a patch under patches/, or discard with 'git -C $GHOSTTY_DIR checkout -- .' plus removing any untracked files it lists"

    # Paths the series leaves untracked. `git checkout -- .` restores
    # tracked files but leaves these, and the dirty check above would then
    # refuse the next build. Refreshed after every apply, so a series that
    # fails partway still cleans up what the earlier patches created.
    #
    # Derived from the worktree rather than from `git apply --summary`
    # create-mode lines, which miss rename and copy destinations. The
    # preflight above guarantees the worktree was clean, so anything
    # untracked here came from a patch. A tracked file that a patch
    # deleted is never listed, and `checkout` restores it.
    #
    # Sampled before the build starts: zig and xcodebuild leave untracked
    # files of their own, and those are not ours to delete.
    PATCH_ADDED_FILES=""

    # Armed before the first apply so a failure mid-series still reverts.
    restore_ghostty_tree() {
        local rc=$?
        git -C "$GHOSTTY_DIR" checkout -- . >/dev/null 2>&1 || true
        if [ -n "$PATCH_ADDED_FILES" ]; then
            while IFS= read -r added; do
                [ -n "$added" ] && rm -f "$GHOSTTY_DIR/$added"
            done <<< "$PATCH_ADDED_FILES"
        fi
        exit "$rc"
    }
    trap restore_ghostty_tree EXIT

    # Applied in order, failing on the first that doesn't take. Checking
    # each against the pristine tree first would reject a patch that
    # legitimately builds on an earlier one in the series.
    for patch_file in "${PATCHES[@]}"; do
        git -C "$GHOSTTY_DIR" apply "$patch_file" \
            || fail "$(basename "$patch_file") does not apply to $DESCRIBE — regenerate it against the current pin (see patches/README.md)"
        PATCH_ADDED_FILES=$(git -C "$GHOSTTY_DIR" status --porcelain --untracked-files=all 2>/dev/null \
            | sed -n 's/^?? //p')
    done
    say "applied ${#PATCHES[@]} patch(es) to $GHOSTTY_DIR"
fi

# Resolve the zig toolchain — keg-only Homebrew zig@0.15 only.
if command -v brew >/dev/null 2>&1 \
    && BREW_ZIG15=$(brew --prefix zig@0.15 2>/dev/null) \
    && [ -x "$BREW_ZIG15/bin/zig" ]; then
    ZIG_BIN="$BREW_ZIG15/bin/zig"
    say "using Homebrew zig@0.15: $ZIG_BIN"
else
    fail "Homebrew zig@0.15 not found — 'brew install zig@0.15'. The vanilla ziglang.org 0.15.2 cannot link on macOS 26."
fi

ZIG_VER=$("$ZIG_BIN" version)
case "$ZIG_VER" in
    0.15.*) zig_patch=${ZIG_VER#0.15.}; zig_patch=${zig_patch%%[-.+]*} ;;
    *)      fail "zig $ZIG_VER unsupported — Ghostty needs the 0.15 line (patch >= 2)." ;;
esac
{ [ "$zig_patch" -ge 2 ] 2>/dev/null; } \
    || fail "zig $ZIG_VER too old — needs 0.15.2+. 'brew upgrade zig@0.15'."

# Pin the macOS SDK explicitly. zig probes the bare
# `xcrun --show-sdk-path`, which on some hosts returns a stale or
# missing CommandLineTools path even when Xcode is selected;
# `xcrun --sdk macosx --show-sdk-path` resolves correctly and zig
# honours SDKROOT.
if [ -z "${SDKROOT:-}" ]; then
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null) \
        || fail "could not resolve macOS SDK via 'xcrun --sdk macosx --show-sdk-path'"
    export SDKROOT
fi
[ -d "$SDKROOT" ] || fail "SDKROOT does not exist: $SDKROOT"
say "SDKROOT $SDKROOT"

# ── Build ──────────────────────────────────────────────────────────────
# Flags, all load-bearing — every one cost real debugging time:
#   -Doptimize=ReleaseFast   release perf for the embedded renderer
#   -Dstrip=false            ReleaseFast defaults strip=true
#       (Config.zig); a stripped static archive loses the embedding
#       symbols. Keep perf, keep symbols.
#   -Demit-xcframework=true  explicitly emit the GhosttyKit xcframework
#   -Dxcframework-target=native
#       arm64-only slice via GhosttyLib.initStatic (libghostty-fat.a).
#
# We deliberately DO NOT pass -Demit-macos-app=false: the full lib
# that exports the embedding C API (ghostty_init / ghostty_app_new /
# ghostty_surface_*) is only assembled when the macos-app path runs.
# That path's final Ld Ghostty.app step fails outside a
# signing-configured env (xcodebuild exit 65) AFTER the xcframework +
# full lib are produced — so tolerate a non-zero zig exit and gate on
# the symbol check below. We don't need Ghostty.app, only the lib.
#
# Always cold. A cache-hit zig build short-circuits the libtool /
# xcframework-assembly steps and leaves a stale or partial libghostty
# (the embedding symbols vanish). Every clean build that ran the full
# path produced the correct lib; every cache-hit re-run regressed it.
# This is a release-artifact builder, not a dev inner loop —
# correctness over speed. (zig's global dep cache in ~/.cache/zig is
# content-addressed and kept; only this build's state is wiped.)
say "wiping prior build state for a cold, reproducible build"
rm -rf \
    "$GHOSTTY_DIR/.zig-cache" \
    "$GHOSTTY_DIR/zig-out" \
    "$GHOSTTY_DIR/macos/GhosttyKit.xcframework" \
    "$GHOSTTY_DIR/macos/build"

say "running zig build (cold build is several minutes)"
set +e
(
    cd "$GHOSTTY_DIR"
    "$ZIG_BIN" build \
        -Doptimize=ReleaseFast \
        -Dstrip=false \
        -Demit-xcframework=true \
        -Dxcframework-target=native
)
zig_exit=$?
set -e
[ "$zig_exit" -eq 0 ] \
    || say "zig build exited $zig_exit (expected: Ghostty.app Ld fails outside a signing env) — verifying the xcframework anyway"

# THE gate — wait for the WRITER to release the artifact, then verify
# once. Mechanism (confirmed across many runs here): zig
# builds the xcframework and the macOS app; the app's Ld step fails
# (xcodebuild exit 65) in any non-Ghostty-CI env, aborting zig build.
# But the xcframework's libtool combine of the ~165MB archive is left
# running ORPHANED and keeps writing for a long, variable time
# (20-40min) after zig returns. Every byte/size-polling gate failed
# because the archive grows the entire time. The deterministic
# completion signal is therefore "no process still holds the artifact
# tree open" (lsof), NOT the file contents. Once the writer exits the
# lib is final; if it's still wrong then, the build is genuinely
# broken. On a clean env where the app links, nothing is writing and
# this passes immediately.
MACOS_DIR="$GHOSTTY_DIR/macos"
[ -e "$MACOS_DIR" ] || fail "expected $MACOS_DIR after zig build — not found"
say "waiting for the orphaned libtool to finish writing the ~165MB"
say "  archive (the slow part — can take 20-40min; lsof-gated)"
hard_cap=$(( $(date +%s) + 3600 ))     # 60min absolute safety net
quiet_streak=0
while :; do
    if lsof +D "$MACOS_DIR" >/dev/null 2>&1; then
        quiet_streak=0                  # something still has it open
    else
        quiet_streak=$(( quiet_streak + 1 ))
        # ~30s of nothing-open = writer truly gone, not a between-
        # write gap or a pre-spawn race.
        [ "$quiet_streak" -ge 3 ] && break
    fi
    [ "$(date +%s)" -ge "$hard_cap" ] \
        && fail "build writers still active after 60min — giving up"
    sleep 10
done
say "build quiesced — verifying the embedding C API"

# Every C symbol the package promises its consumers. A patch that adds
# a new export adds it here too, so a silently-dropped patch fails the
# release gate rather than surfacing as a link error downstream.
REQUIRED_SYMBOLS=(
    ghostty_surface_new
    ghostty_surface_read_text_format
)

EMBED_LIB=""
MISSING_SYMBOLS=""
while IFS= read -r lib; do
    syms=$(nm "$lib" 2>/dev/null || true)
    # Here-string, not `printf | grep -q`: see the same note in release.sh
    # (pipefail + early grep exit = SIGPIPE = false "missing").
    missing=""
    for sym in "${REQUIRED_SYMBOLS[@]}"; do
        grep -q " T _${sym}\$" <<< "$syms" \
            || missing="${missing:+$missing }$sym"
    done
    if [ -z "$missing" ]; then
        EMBED_LIB="$lib"; break
    fi
    MISSING_SYMBOLS="$missing"
done < <(find "$ARTIFACT_SRC" -name 'libghostty*.a' -path '*macos*' 2>/dev/null)
# NON-fatal here by design. The embedding symbol is finalized by an
# orphaned libtool whose completion is decoupled from this process —
# every in-build gate variant (long poll, size-stable, lsof-quiesce)
# loses the same race, then the lib is correct moments later. So this
# script only WARNS; the authoritative pass/fail gate runs in
# release.sh against the frozen dist/ copy (a static snapshot, so
# that check is deterministic). See AGENTS.md "Build reality".
if [ -z "$EMBED_LIB" ]; then
    any=$(find "$ARTIFACT_SRC" -name 'libghostty*.a' -path '*macos*' 2>/dev/null | head -1)
    sym_count=$(nm "$any" 2>/dev/null | grep -c '_ghostty_' || true)
    say "WARNING: embedding C API incomplete (missing: ${MISSING_SYMBOLS:-unknown}; best candidate ${sym_count:-0} ghostty_ symbols). The orphaned libtool may still be finalizing — re-check dist/ before releasing; release.sh will gate."
else
    say "embedding C API present in $(basename "$EMBED_LIB") (${#REQUIRED_SYMBOLS[@]} required symbols)"
fi

[ -f "$RESOURCE_SRC/terminfo/78/xterm-ghostty" ] \
    || fail "expected the terminfo sentinel under $RESOURCE_SRC — not found"

# ── Install ────────────────────────────────────────────────────────────
# xcframework → gitignored dist/ (republished per release tag).
rm -rf "$ARTIFACT_DEST"
mkdir -p dist
cp -R "$ARTIFACT_SRC" "$ARTIFACT_DEST"

# Resources → tracked in-repo tree (GhosttyKitResources target). Wipe
# and fully regenerate so `git diff` is the source of truth for any
# Ghostty resource drift on a pin bump. Only what libghostty needs at
# runtime: the terminfo sentinel + shell-integration + themes. Skip
# doc/ and locale/.
rm -rf "$RESOURCE_DEST"
mkdir -p "$RESOURCE_DEST/ghostty"
cp -R "$RESOURCE_SRC/terminfo" "$RESOURCE_DEST/terminfo"
cp -R "$RESOURCE_SRC/ghostty/shell-integration" "$RESOURCE_DEST/ghostty/shell-integration"
cp -R "$RESOURCE_SRC/ghostty/themes" "$RESOURCE_DEST/ghostty/themes"

# The Kitty-derived bash/zsh integration scripts are GPL-3.0-or-later
# (each says so in its own header); the rest of the tree is MIT. GPLv3
# §4 wants a copy of the license conveyed alongside them, and Ghostty
# ships none — so place ours beside them, making the bundle we hand to
# consumers self-contained. Must happen here, not by hand: the tree
# above is wiped every build, and a hand-added file would also trip
# release.sh's resources gate as untracked drift.
cp licenses/GPL-3.0.txt "$RESOURCE_DEST/ghostty/shell-integration/GPL-3.0.txt"

say "built $ARTIFACT_DEST"
say "regenerated $RESOURCE_DEST (terminfo + shell-integration + themes)"
say "  Ghostty: $DESCRIBE ($HEAD)"
say "  zig:     $ZIG_VER"
say "  wrote GHOSTTY_VERSION"
