# Third-Party Notices

This package is licensed MIT (`LICENSE`), matching
[Ghostty](https://github.com/ghostty-org/ghostty), the terminal engine
it packages. That grant covers the packaging authored in this
repository. The material the package *redistributes* — Ghostty itself,
the dependencies statically linked into `GhosttyKit.xcframework`, and
the resource tree in `GhosttyKitResources` — keeps its own licenses,
summarized below; most are MIT or BSD-style, a few are not.

Ghostty's copyright and permission notice is reproduced in full, as its
license requires of anything that redistributes it.

## Ghostty

```
MIT License

Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## What else ships

`GhosttyKit.xcframework` statically links Ghostty's dependencies, and
`GhosttyKitResources` ships Ghostty's runtime resource tree. The
principal components, verified against the pin in `GHOSTTY_VERSION`
(Ghostty `e90b7c9`):

- **Zig modules** — libxev, zig-objc, libvaxis, zf, uucode, zigimg
  (MIT); z2d (MPL-2.0).
- **C libraries** — FreeType (FreeType License); libpng; zlib;
  Oniguruma (BSD-2); Highway, Wuffs, simdutf, SPIRV-Cross, glslang
  (Apache-2.0); Dear ImGui and dear_bindings (MIT); stb_image (public
  domain / MIT); sentry-native (MIT); Breakpad (BSD-3); GNU libintl
  (LGPL-2.1-or-later).
- **Fonts embedded in the binary** — JetBrains Mono (OFL-1.1); Symbols
  Nerd Font, a composite of many upstream icon sets under mixed terms
  (OFL-1.1, CC BY, MIT). Treat it as mixed-license, not MIT: the pinned
  artifact ships only the Nerd Fonts project's MIT license, which
  covers that project's own code and font patcher rather than the
  aggregated glyphs. See the
  [Nerd Fonts repository](https://github.com/ryanoasis/nerd-fonts) for
  the per-set breakdown.
- **Resources** — themes from
  [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes)
  (MIT); [bash-preexec](https://github.com/rcaloras/bash-preexec)
  (MIT); Ghostty's own fish, elvish, and nushell integrations (MIT);
  and three Kitty-derived shell scripts under **GPL-3.0-or-later** —
  `shell-integration/bash/ghostty.bash`, `zsh/ghostty-integration`,
  `zsh/.zshenv`.

Two items need a decision if you ship an app:

- The **GPL-3.0** shell scripts. They are standalone scripts run by the
  user's shell and are never linked into your app, so they don't reach
  your code — but shipping them is still redistribution, carrying
  notice and source obligations for those files. The source obligation
  is self-satisfying (they ship *as* source), and for the notice
  obligation this package places a copy of the GPLv3 text beside them
  at `shell-integration/GPL-3.0.txt`, so it travels into your app
  bundle automatically. Upstream Ghostty ships no copy of the GPL text;
  ours is added by `scripts/build-xcframework.sh` from
  `licenses/GPL-3.0.txt`. Omitting them is
  coarser than it sounds: `GhosttyKitResources` copies the tree
  wholesale (`.copy("Resources")` in `Package.swift`), so a SwiftPM
  consumer cannot exclude just `shell-integration/bash` and `zsh`.
  Dropping them means not depending on `GhosttyKitResources` at all and
  supplying your own filtered copy of the tree.
- Statically linked **LGPL-2.1** `libintl`, carrying notice and relink
  obligations.

These obligations hold whatever your app is licensed as. A copyleft app
doesn't escape them — it just tends to satisfy them incidentally, by
publishing source anyway. Neither item changes this package's license
or Ghostty's: per-file headers override a project default, which is
exactly how upstream ships them.

Re-check this list when the Ghostty pin moves; note that Ghostty's
dependencies also live in nested `pkg/*/build.zig.zon` manifests and in
vendored source like `src/stb/`, not only the top-level manifest.
