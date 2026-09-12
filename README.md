# Disk Checker

A native macOS storage explorer built with SwiftUI. Requires macOS 14 or later and Swift 6 to build. No third-party dependencies or network requests.

## Install with Homebrew

Version 0.1.2 is a development prerelease for Apple silicon Macs running macOS 14 or later. It has an ad-hoc signature and is **not notarized**; macOS Gatekeeper may block it from launching. This is not yet a production-signed distribution.

```sh
brew tap praveen902012/disk-checker https://github.com/praveen902012/mac-diskchecker.git
brew install --cask praveen902012/disk-checker/disk-checker
```

Downloads and release notes: [GitHub releases](https://github.com/praveen902012/mac-diskchecker/releases).

To update an existing installation:

```sh
brew update
brew upgrade --cask praveen902012/disk-checker/disk-checker
open -a "Disk Checker"
```

## Install with a DMG

Download [Disk Checker 0.1.2 for Apple silicon](https://github.com/praveen902012/mac-diskchecker/releases/download/v0.1.2/Disk-Checker-0.1.2-arm64.dmg). Open the disk image and drag **Disk Checker.app** into **Applications**, then eject the image. Quit any running copy before replacing an existing installation.

This is an ad-hoc signed development preview, not an Apple-notarized release; Gatekeeper may block launch. A SHA-256 checksum is included in the [release assets](https://github.com/praveen902012/mac-diskchecker/releases/tag/v0.1.2).

## Run

```sh
./scripts/package.sh
open "dist/Disk Checker.app"
```

The package script builds for the current Mac's architecture and applies a local ad-hoc signature. This is a local development build, not a notarized distribution release.

Choose **Scan a folder** or a quick scan. Results are sorted largest first. Double-click a folder or use its chevron to explore; use breadcrumbs to go back. The magnifying glass reveals an item in Finder. The filter searches immediate children of the current folder. Click chart segments to explore or reveal their corresponding items.

Scanning runs in the background and can be cancelled. Cancelling preserves any previous completed scan. Ordinary storage scans do not read file contents; the optional AI metadata check reads embedded image metadata. A **Delete** button appears for files and folders whose scanned allocated size is strictly greater than 1 GB (1,000,000,000 bytes) inside your Desktop, Downloads, or Documents folders, including their subfolders. The three top-level folders themselves cannot be deleted. Confirm the full path and size to move the item to the macOS Trash; cancelling makes no changes. Deleting a folder moves all its contents. Results refresh after a successful move, and failures are shown in the app. Items can be restored from Finder’s Trash; disk space is not reclaimed until the Trash is emptied. The app does not empty the Trash.

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

Run `python3 scripts/homebrew-release.py` to build a versioned ZIP and checksum-verified release cask for `praveen902012/mac-diskchecker`. Use `--local` for a local file-URL test cask. The generated release archive and `Casks/disk-checker.rb` must be published before public installation works. See [Homebrew packaging and installation](packaging/homebrew/README.md) for local tap installation and publishing steps.

## Build and publish a release

Follow [Build and Release](BUILD_AND_RELEASE.md) for versioning, tests, app packaging, Git push, GitHub release upload, verification, and Homebrew install/update commands.

## Check AI metadata

After scanning a folder, choose **Check AI Metadata…** to inspect that folder and its descendants. The local background check supports PNG, JPEG, HEIC/HEIF, and TIFF. Cancel keeps partial results clearly marked incomplete. **View AI Metadata Results…** reopens the report until the next disk scan or successful cleanup invalidates it.

Results show the inspected-image count, matches, skipped/unsupported files, and location errors. Matches appear largest first with their path, allocated size, detected tool, expandable evidence, and **Reveal in Finder**. Turn on **Show all inspection outcomes** to include **No hints found**, **Unsupported**, and **Could not inspect** results.

Detection recognizes explicit generator names in software/creator metadata, structured Stable Diffusion parameters, and ComfyUI sampler graphs. Filenames, generic mentions of AI, and ordinary photo-editor tags do not establish a match. Evidence is unverified: metadata can be edited or removed, and no hints found does not mean human-made. The check does not validate C2PA credentials, analyze pixels, upload data, or delete files.

Unlike the ordinary disk scan, this optional action opens files to read embedded metadata. PNG text chunks, compressed text, XMP, and selected EXIF fields are inspected without loading image pixels. Encoded PNG metadata and decompressed text share an 8 MiB budget. JPEG, HEIC, and TIFF use ImageIO; their entire encoded input is conservatively limited to 8 MiB, so larger files are reported as incomplete. Extracted metadata is also limited to 8 MiB. Displayed evidence is shortened to 4,096 characters. Symbolic links, other volumes, and undownloaded cloud placeholders are skipped; the app does not request downloads. Results represent that check, not live monitoring.

## Intel / macOS Catalina compatibility edition

An AppKit edition supports Intel Macs running **macOS Catalina 10.15.7 or later**. It reuses the same storage scanner, AI metadata detector, screenshot recognition, and Trash eligibility rules. The interface provides folder navigation, size charts, filtering, Finder reveal, AI evidence reports, cancellation, and reviewed cleanup using controls available on Catalina.

Build on an Intel Mac with Apple Command Line Tools (Swift 5.3 or newer):

```sh
./scripts/test-catalina.sh
./scripts/package-catalina.sh
open "dist/catalina/Disk Checker.app"
```

To create its installer using Python 3:

```sh
python3 scripts/dmg-release.py --skip-build --catalina
```

The compatibility installer is named `Disk-Checker-0.1.2-catalina-x86_64.dmg`. This is a separate build from the Apple silicon/Homebrew release. It uses an ad-hoc signature and is not Apple-notarized. On Catalina, Full Disk Access is under **System Preferences → Security & Privacy → Privacy**. AI checks remain local and metadata-based, with the same detection limits described above.
