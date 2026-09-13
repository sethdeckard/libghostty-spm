# Patches

Local source changes to Ghostty, applied to `vendor/ghostty` for the
duration of a build and reverted when it exits.

`vendor/ghostty` tracks upstream exactly. Nothing is committed into the
submodule, so its gitlink always names a commit that exists on
`ghostty-org/ghostty`, and a fresh clone gets the same source. What this
package changes on top lives here, and `GHOSTTY_VERSION` records which
patches went into a given build.

`scripts/build-xcframework.sh` applies them in lexical order and fails on
the first one that doesn't apply, so a patch may build on an earlier one
in the series. An exit trap reverts the submodule whether the build
succeeds or fails, including a run that stops partway through the series.

The build refuses to start when `vendor/ghostty` already has local
changes. That usually means an earlier run was killed before its trap
fired. Discard them with `git -C vendor/ghostty checkout -- .`, or
capture them as a patch first if they were yours.

## Authoring a patch

Edit the submodule in place, capture the diff, then restore it:

```sh
# ...edit files under vendor/ghostty...
git -C vendor/ghostty add -A
git -C vendor/ghostty diff --cached > patches/0002-your-change.patch
git -C vendor/ghostty reset --hard
```

Stage first. A plain `git diff` skips untracked files, so a patch that
adds or renames a file would capture nothing for it. `git add -N` is not
a substitute: it leaves an index entry that a plain checkout won't clear,
and the next build's dirty check then refuses to start.

The output is a diff, not `git format-patch`. These go through
`git apply`, which wants no commit metadata.

`git -C` resolves paths relative to the directory it switches to, so pass
the patch as an absolute path. A relative one fails with
"can't open patch".

A patch that adds a C export must add that symbol to `REQUIRED_SYMBOLS`
in both `scripts/build-xcframework.sh` and `scripts/release.sh`. The
release gate checks the list against the built archive, so a patch that
quietly stops applying fails the release instead of publishing a lib
without the symbol.

Commit the patch file before cutting a release. `release.sh` refuses to
publish with uncommitted patches, because the tag has to carry the source
the binary was built from.

## On a Ghostty pin bump

Run `make build` after moving the pin. It applies the series in order and
fails with the name of the first patch that no longer applies, which is
the check you want. Checking each patch independently against a pristine
tree gives a false failure for any patch that builds on an earlier one.

Regenerate whatever fails by redoing the change by hand against the new
source.

## Upstreaming

A patch here is a change upstream hasn't taken. Ghostty requires pull
request authors to be vouched, and wants features to go through an
accepted issue first, so carrying a change locally is the ordinary case
rather than a failed contribution. Delete the patch file once an
equivalent lands upstream and the pin moves past it.
