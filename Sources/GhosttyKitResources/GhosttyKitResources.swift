import Foundation

/// libghostty's runtime resource tree, bundled into the package so
/// consumers need neither a separate release asset nor a local Ghostty
/// build to obtain it.
///
/// The directory contains `terminfo/` (the `xterm-ghostty` /
/// `ghostty` compiled entries) and `ghostty/{shell-integration,themes}`,
/// laid out exactly as Ghostty's `zig-out/share` emits it. Point
/// libghostty at `directoryURL` (e.g. via `GHOSTTY_RESOURCES_DIR` or
/// the surface config) so `infocmp`, shell integration, and built-in
/// themes resolve at runtime.
public enum GhosttyKitResources {
    /// Filesystem URL of the bundled resource root.
    ///
    /// Backed by `Bundle.module`; the directory is `.copy`'d verbatim
    /// at build time. A failure here means the package itself is built
    /// wrong (the resource bundle did not ship), not a recoverable
    /// runtime condition.
    public static var directoryURL: URL {
        guard let url = Bundle.module.url(
            forResource: "Resources",
            withExtension: nil
        ) else {
            fatalError(
                "GhosttyKitResources: bundled Resources/ not found in "
                + "Bundle.module — the package build is broken"
            )
        }
        return url
    }
}
