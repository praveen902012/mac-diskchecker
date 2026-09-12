# Build and publish Disk Checker

Run these commands from the project root in Terminal. Stop if any step fails; resolve the error before continuing.

## 1. Prepare your Mac

You need macOS, Swift 6, Python 3, Git, Homebrew, and the GitHub CLI (`gh`). Apple's Command Line Tools provide Swift and the icon utilities used by the build.

```sh
xcode-select --install
brew install gh
gh auth login
```

Skip installation or authentication steps that are already complete. Check the toolchain and repository:

```sh
swift --version
python3 --version
gh auth status
git remote -v
git status --short
```

The `origin` remote should be `https://github.com/praveen902012/mac-diskchecker.git`. Start from `main` and update it before making release changes:

```sh
git switch main
git pull --ff-only origin main
```

Commit or otherwise preserve any existing work before switching branches or resolving conflicts.

## 2. Set the new version

Edit `scripts/package.sh` and increment both Info.plist values. For example, after version `0.1.1` / build `2`, use:

```xml
<key>CFBundleShortVersionString</key><string>0.1.2</string>
<key>CFBundleVersion</key><string>3</string>
```

Use a new version for each published build. Do not replace the ZIP of an existing release: Homebrew verifies it against the committed checksum. Update the version mentioned in `README.md` as well.

## 3. Test and build

```sh
./scripts/test.sh
./scripts/package.sh
open "dist/Disk Checker.app"
```

Quit any already-running Disk Checker copy before opening the new build. Check the icon, folder scanning, navigation, cancellation, and cleanup confirmation screens. Test cleanup only with disposable files.

The packaging script builds the Swift app, generates all icon sizes, creates the app bundle, and applies an ad-hoc signature. Outputs are in `dist/`, which is excluded from Git.

**Signing status:** this procedure currently produces a development build, not an Apple-notarized app. Gatekeeper may block it. For a production release, apply Developer ID signing, notarization, and stapling to the built app before the next step. Do not rerun `package.sh` after doing that, because it replaces the signature.

## 4. Generate the release ZIP and Homebrew cask

Package the app you just built and tested:

```sh
python3 scripts/homebrew-release.py --skip-build
```

This reads the repository from `packaging/homebrew/release.json` and generates:

- `dist/Disk-Checker-VERSION-arm64.zip` on an Apple silicon build machine.
- The matching `.zip.sha256` checksum file.
- `Casks/disk-checker.rb` with the version, download URL, and checksum.

The script detects the binary's architecture; Intel and universal archives have different suffixes. The examples below assume the currently supported Apple silicon build.

Read the version from the built app and verify the archive:

```sh
RELEASE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "dist/Disk Checker.app/Contents/Info.plist")
RELEASE_ARCHIVE="Disk-Checker-${RELEASE_VERSION}-arm64.zip"
(cd dist && shasum -a 256 -c "${RELEASE_ARCHIVE}.sha256")
codesign --verify --deep --strict "dist/Disk Checker.app"
cat Casks/disk-checker.rb
```

Confirm the cask's SHA-256 matches the checksum file. Signature integrity passing does not mean the app is notarized. Keep this exact ZIP for upload; regenerating the archive can change its checksum.

## 5. Write release notes

Create `dist/release-notes.md` describing the actual changes and validation. For example:

```sh
cat > dist/release-notes.md <<'NOTES'
Describe the changes in this version here.

Requires Apple silicon and macOS 14 or later.

Development prerelease: ad-hoc signed and not Apple-notarized.
Gatekeeper may block launch.

Record the tests and manual checks completed for this release.
NOTES
```

Replace the example wording with accurate release notes before uploading.

## 6. Commit and push

Review the files, then stage the release source and documentation. Keep ZIPs, signing credentials, and build output out of Git.

```sh
git status --short
git diff
git add .gitignore README.md BUILD_AND_RELEASE.md PLAN.md Package.swift Sources Tests Assets scripts packaging Casks
git diff --cached --stat
git diff --cached --check
git commit -m "Release Disk Checker ${RELEASE_VERSION}"
git push origin HEAD:main
RELEASE_COMMIT=$(git rev-parse HEAD)
```

If Git rejects the push, reconcile the remote changes before continuing. Do not force-push. If source changes during reconciliation, rebuild, retest, and regenerate the archive/cask before publishing.

## 7. Publish on GitHub

Check that the version has not already been released:

```sh
gh release list --repo praveen902012/mac-diskchecker --limit 10
```

Publish the exact archive and checksum, targeting the full pushed commit SHA:

```sh
gh release create "v${RELEASE_VERSION}" \
  "dist/${RELEASE_ARCHIVE}" \
  "dist/${RELEASE_ARCHIVE}.sha256" \
  --repo praveen902012/mac-diskchecker \
  --target "$RELEASE_COMMIT" \
  --title "Disk Checker ${RELEASE_VERSION} — Development Preview" \
  --notes-file dist/release-notes.md \
  --prerelease
```

GitHub creates the version tag at that commit. Keep `--prerelease` while the build remains a development preview. Publishing the cask alone is not enough: its ZIP URL only works after the release assets are available.

## 8. Verify the published download

```sh
VERIFY_DIR=$(mktemp -d "$PWD/dist/release-verify.XXXXXX")
gh release download "v${RELEASE_VERSION}" \
  --repo praveen902012/mac-diskchecker \
  --pattern "$RELEASE_ARCHIVE" \
  --dir "$VERIFY_DIR"
cmp "dist/${RELEASE_ARCHIVE}" "$VERIFY_DIR/$RELEASE_ARCHIVE"
```

`cmp` produces no output and exits successfully when the uploaded ZIP exactly matches the local release archive.

## 9. Install or update through Homebrew

First installation:

```sh
brew tap praveen902012/disk-checker https://github.com/praveen902012/mac-diskchecker.git
brew install --cask praveen902012/disk-checker/disk-checker
```

Update an existing installation:

```sh
brew update
brew upgrade --cask praveen902012/disk-checker/disk-checker
```

Quit the development copy before launching the installed app:

```sh
open "/Applications/Disk Checker.app"
```

If Homebrew says it is installed but that path is missing:

```sh
brew reinstall --cask praveen902012/disk-checker/disk-checker
open -R "/Applications/Disk Checker.app"
```

`open -R` reveals the actual installed copy in Finder. Capture any macOS launch warning rather than assuming reinstallation resolves a signing problem.

## DMG release asset

Build once with `./scripts/package.sh`, then run:

```sh
python3 scripts/dmg-release.py --skip-build
```

This creates `dist/Disk-Checker-VERSION-arm64.dmg` and its `.dmg.sha256` file (with the matching architecture suffix). The image contains the app, an Applications shortcut, and installation notes. The script checks the app signature and verifies the disk image; it refuses to overwrite an existing DMG.

Upload both DMG files alongside the ZIP and ZIP checksum in the versioned GitHub release. Installer binaries stay in release assets; commit the source, version, packaging scripts, and Homebrew cask to Git. Include all four asset paths in `gh release create`, or use `gh release upload vVERSION DMG_PATH CHECKSUM_PATH` for an existing release. Do not replace published assets.

After upload, download both archives and compare them with the local originals. To check the DMG locally, mount it read-only with `hdiutil attach -readonly -nobrowse`, verify the mounted app with `codesign --verify --deep --strict`, and detach it with `hdiutil detach` when finished.

## Catalina compatibility build

Use `scripts/package-catalina.sh` on an Intel Mac with Swift 5.3+ Command Line Tools. The script targets macOS 10.15.7 and builds the AppKit entry point together with the shared scanner and cleanup code. Run `scripts/test-catalina.sh` on that Mac before installation. Modern Apple silicon toolchains may omit the Intel compatibility libraries, so use the Intel host's native compiler instead of assuming cross-compilation will work.

The resulting app is `dist/catalina/Disk Checker.app`. Run `python3 scripts/dmg-release.py --skip-build --catalina` to create a separate `catalina-x86_64` installer. Do not change the Apple silicon Homebrew cask to point at this edition. Verify the bundle's minimum OS, architecture, signature, and launch behavior on Catalina before distributing it.
