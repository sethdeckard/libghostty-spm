#!/usr/bin/env bash
# scripts/release.sh TAG — build, package, checksum, and (optionally)
# publish a GhosttyKit release.
#
#   ./scripts/release.sh v0.1.0
#
# Steps:
#   1. build-xcframework.sh  → dist/GhosttyKit.xcframework
#   2. zip it with ditto (the SPM-correct way to archive a framework)
#   3. swift package compute-checksum  (the value binaryTarget wants)
#   4. print the exact Package.swift pin (repoSlug/tag/checksum)
#   5. if `gh` is available: create the release + upload the asset
#
# Runtime resources are NOT a release asset — they ship in-repo via
# the GhosttyKitResources target (Bundle.module). Only the xcframework
# (too large to commit) is published here.
#
# The url+checksum chicken-and-egg is resolved here: this prints the
# stanza to commit on the release tag. First release: tag, run this,
# commit Package.swift with the printed values on the tag, push.

set -euo pipefail

cd "$(dirname "$0")/.."

TAG="${1:-}"
[ -n "$TAG" ] || { echo "usage: scripts/release.sh <tag>  (e.g. v0.1.0)" >&2; exit 1; }

say() { printf "release: %s\n" "$1"; }

./scripts/build-xcframework.sh

XCF=dist/GhosttyKit.xcframework
ZIP=dist/GhosttyKit.xcframework.zip

# THE authoritative gate. dist/ is a frozen snapshot (build-xcframework
# copied it after its quiesce wait), so this check is deterministic —
# unlike the in-build check it cannot race the orphaned libtool. If
# the build raced and the dist copy is incomplete, FAIL: never publish
# a libghostty without the embedding C API. Recovery is manual: wait
# for the build to fully settle, re-run release (it rebuilds clean).
DIST_LIB=$(find "$XCF" -name 'libghostty*.a' -path '*macos*' 2>/dev/null | head -1)
if [ -z "$DIST_LIB" ] || ! nm "$DIST_LIB" 2>/dev/null | grep -q ' T _ghostty_surface_new$'; then
    sc=$(nm "$DIST_LIB" 2>/dev/null | grep -c '_ghostty_' || true)
    echo "release: error: dist xcframework lacks the embedding C API (ghostty_surface_new absent; ${sc:-0} ghostty_ symbols). The build raced the orphaned libtool — wait for it to fully settle, then re-run." >&2
    exit 1
fi
say "publish gate OK — embedding C API present in $(basename "$DIST_LIB")"

# Second half of the same invariant. The xcframework ships as a release
# asset built right now; GhosttyKitResources ships from the git tree at
# the resolved tag (Bundle.module resolves from the package checkout,
# NOT this workspace). build-xcframework.sh just wiped+regenerated
# Sources/GhosttyKitResources/Resources from the pinned Ghostty — if
# that differs from what's committed on the tag, the published binary
# would be paired with stale resources. --porcelain catches modified,
# deleted AND new (untracked) files, e.g. themes a pin bump added.
RES_TREE="Sources/GhosttyKitResources/Resources"
if [ -n "$(git status --porcelain -- "$RES_TREE" 2>/dev/null)" ]; then
    echo "release: error: the build regenerated $RES_TREE differently from the committed tree — the published xcframework would be paired with stale in-repo resources. Commit the resource diff onto $TAG, then re-run." >&2
    git status --porcelain -- "$RES_TREE" >&2
    exit 1
fi
say "resources gate OK — committed tree matches the built Ghostty"

say "zipping $XCF (ditto, framework-safe)"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$XCF" "$ZIP"

CHECKSUM=$(swift package compute-checksum "$ZIP")
# GHOSTTY_VERSION is written by build-xcframework.sh: human-readable
# `git describe` + full commit. Independent package SemVer; this is
# the one-lookup map from package tag → exact Ghostty.
GHOSTTY_VER=$(cat GHOSTTY_VERSION 2>/dev/null || echo "ghostty: unknown")
SLUG=$(git config --get remote.origin.url \
    | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')

NOTES="GhosttyKit.xcframework
$GHOSTTY_VER
checksum: $CHECKSUM"

cat <<EOF

────────────────────────────────────────────────────────────────────
Release $TAG
$GHOSTTY_VER
  asset:    $ZIP
  checksum: $CHECKSUM

Commit this on tag $TAG in Package.swift:

    let repoSlug = "$SLUG"
    let releaseTag = "$TAG"
    let checksum = "$CHECKSUM"
────────────────────────────────────────────────────────────────────
EOF

if command -v gh >/dev/null 2>&1; then
    say "publishing release $TAG via gh"
    if gh release create "$TAG" "$ZIP" \
            --title "$TAG" --notes "$NOTES"; then
        say "created release $TAG"
    else
        # `create` fails when the release already exists (reruns) —
        # update its asset in place. A failure HERE is real (auth,
        # network, bad tag): exit non-zero so the run does not appear
        # to succeed without publishing.
        say "gh release create failed — trying upload --clobber (release exists?)"
        gh release upload "$TAG" "$ZIP" --clobber \
            || { say "error: could not publish asset for $TAG"; exit 1; }
        say "updated release $TAG asset"
    fi
else
    say "gh not found — upload $ZIP to the $TAG release manually"
fi
