# Homebrew distribution

Disk Checker is a macOS GUI app, so it is distributed using a **cask**. The release generator builds the app, verifies its signature, creates a ZIP containing `Disk Checker.app`, calculates SHA-256, and writes a cask with the actual version and supported architecture. It does not upload files or create public repositories.

## Build a local package

From the project root:

```sh
python3 scripts/homebrew-release.py --local
```

Outputs go into `dist/`: the versioned ZIP, checksum, and `homebrew-disk-checker-local/Casks/disk-checker.rb`. The local cask points to the ZIP's absolute file URL. Regenerate it if you relocate the project.

To install through a local tap, first commit the generated tap (Git requires your name/email to be configured):

```sh
git -C dist/homebrew-disk-checker-local init
git -C dist/homebrew-disk-checker-local add Casks README.md
git -C dist/homebrew-disk-checker-local commit -m 'Add local Disk Checker cask'
brew tap disk-checker/local "$PWD/dist/homebrew-disk-checker-local"
brew install --cask disk-checker/local/disk-checker
```

Quit any running copy first. Homebrew will report a conflict if a separately installed `Disk Checker.app` already occupies its destination; move that copy aside intentionally before retrying. Do not force-overwrite it.

```sh
brew uninstall --cask disk-checker/local/disk-checker
brew untap disk-checker/local
```

Uninstall removes the app, not your documents or Trash contents. No `zap` deletion hooks or Gatekeeper bypasses are included.

## Configured GitHub release

The public repository is **praveen902012/mac-diskchecker**. It hosts both the source and `Casks/disk-checker.rb`; a second repository is not required. The release destination is stored in `packaging/homebrew/release.json`.

Generate the release ZIP, SHA-256 file, and cask:

```sh
python3 scripts/homebrew-release.py
```

This updates `Casks/disk-checker.rb` with the exact archive hash and a URL such as:

`https://github.com/praveen902012/mac-diskchecker/releases/download/v0.1.0/Disk-Checker-0.1.0-arm64.zip`

**Generating a cask does not publish that URL.** The cask and source must be committed and pushed, and the exact generated ZIP must be uploaded to the matching GitHub Release before installation works. The generator does not push, create tags, or publish releases.

## Publish a downloadable release

1. Set the version in `scripts/package.sh`'s Info.plist before a new release. Run `./scripts/test.sh` and `./scripts/package.sh`.
2. For public distribution, sign the app with your Developer ID Application certificate, notarize it with Apple, and staple the result. The default packaging script only applies a local ad-hoc signature; it is not a public notarized release.
3. Generate the archive and cask from the finalized app:

   ```sh
   python3 scripts/homebrew-release.py --skip-build
   ```

   `--skip-build` preserves the signature and notarization of the prepared app. An optional `--repo OWNER/REPO` overrides the configured destination.
4. Commit and push the application source, packaging scripts, and generated `Casks/disk-checker.rb` to the configured repository. Tag that release commit `vVERSION`.
5. Upload the exact generated ZIP and checksum to that GitHub Release. Do not rebuild or modify the ZIP after committing its cask checksum. `VERSION` refers to the app's actual release version.
6. Verify on a clean Mac before announcing:

   ```sh
   brew tap praveen902012/disk-checker https://github.com/praveen902012/mac-diskchecker.git
   brew audit --cask praveen902012/disk-checker/disk-checker
   brew install --cask praveen902012/disk-checker/disk-checker
   open -a 'Disk Checker'
   ```

The explicit repository URL on `brew tap` is required because the repository is called `mac-diskchecker`, rather than Homebrew's conventional `homebrew-disk-checker`.

After publication, users can update and uninstall with:

```sh
brew update
brew upgrade --cask praveen902012/disk-checker/disk-checker
brew uninstall --cask praveen902012/disk-checker/disk-checker
```

Installing through a custom tap does not mean the app has been accepted into the official Homebrew cask repository. Homebrew distribution does not implement paid licensing.

The current build is Apple silicon only and requires macOS 14+. The generator can also describe an Intel or universal app if one is supplied, but that is not a claim those builds have been tested.

References: [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [Maintaining a tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap).
