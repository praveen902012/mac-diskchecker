# Disk Checker

A native macOS storage explorer built with SwiftUI. Requires macOS 14 or later and Swift 6 to build. No third-party dependencies or network requests.

## Run

```sh
./scripts/package.sh
open "dist/Disk Checker.app"
```

The package script builds for the current Mac's architecture and applies a local ad-hoc signature. This is a local development build, not a notarized distribution release.

Choose **Scan a folder** or a quick scan. Results are sorted largest first. Double-click a folder or use its chevron to explore; use breadcrumbs to go back. The magnifying glass reveals an item in Finder. The filter searches immediate children of the current folder. Click chart segments to explore or reveal their corresponding items.

Scanning runs in the background and can be cancelled. Cancelling preserves any previous completed scan. The app does not read file contents. A **Delete** button appears for files and folders whose scanned allocated size is strictly greater than 1 GB (1,000,000,000 bytes) inside your Desktop, Downloads, or Documents folders, including their subfolders. The three top-level folders themselves cannot be deleted. Confirm the full path and size to move the item to the macOS Trash; cancelling makes no changes. Deleting a folder moves all its contents. Results refresh after a successful move, and failures are shown in the app. Items can be restored from Finder’s Trash; disk space is not reclaimed until the Trash is emptied. The app does not empty the Trash.

## Storage accounting

- Uses allocated file size, falling back to logical size when unavailable.
- Includes hidden files and descends into app/library packages.
- Skips symbolic links, special files, and other mounted volumes.
- Counts hard-linked data once per scan; the first encountered link receives the size, so another link can appear as zero bytes.
- Reports skipped/unreadable locations. A scan with those warnings is incomplete.
- APFS clones can share physical blocks; summing allocated sizes does not deduplicate those blocks. Snapshots, directory metadata, protected files, and purgeable storage also make scan totals differ from macOS storage figures.
- The chart and folder size describe the selected folder. Volume metrics describe its entire filesystem volume.

For protected folders, enable the packaged app under **System Settings → Privacy & Security → Full Disk Access**, then quit/reopen and rescan. The app does not request administrator access or change permissions itself.

Results live in memory and represent one scan, not a live monitor. Large scans can consume substantial memory. Folder explanations are hints based on names; they do not establish whether data is safe to delete.

## Tests

```sh
./scripts/test.sh
```

The standalone test runner works with Command Line Tools; Xcode/XCTest is not required. Tests cover nested folder accounting, allocated sizes, hidden files, hard-link deduplication, symlink loops, cancellation, empty folders, missing roots, unreadable folders, and deletion eligibility (size boundaries, allowed folders, and symlink escapes). No real user files are moved by the tests.

See [PLAN.md](PLAN.md) for the initial scope and follow-up ideas.

## Delete Desktop screenshots

Use **Delete Desktop Screenshots…** in the sidebar. Review the detected filenames, count, and size, then choose **Move All to Trash**. Cancel leaves every file untouched. This action includes screenshots of any size and only checks files directly on the Desktop, not subfolders or symbolic links.

Detection uses macOS `kMDItemIsScreenCapture` metadata, with a fallback for standard English `Screenshot YYYY-MM-DD at HH.MM.SS` and `Screen Shot` filenames. Renamed or localized screenshots need screenshot metadata to be detected; arbitrary third-party capture filenames may not match. Review the list to confirm that the matched files are screenshots you want to remove.

The batch only moves reviewed files. Files that changed since review are skipped. Individual failures are reported while the remaining files continue, and storage results refresh after successful moves. No permanent deletion or automatic emptying of Trash occurs. Tests use temporary fixtures and a simulated Trash destination, never your Desktop screenshots.

## Homebrew package

Run `python3 scripts/homebrew-release.py` to build a versioned ZIP and checksum-verified local cask. Once the GitHub release repository is configured, use `--repo OWNER/REPO` to generate an HTTPS release cask. See [Homebrew packaging and installation](packaging/homebrew/README.md) for local tap installation and publishing steps.
# mac-diskchecker
