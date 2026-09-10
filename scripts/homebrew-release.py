#!/usr/bin/env python3
"""Build a versioned ZIP and a cask with a real SHA-256 digest."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def ruby_string(value):
    # JSON string literals are also Ruby strings; reject Ruby interpolation.
    if '#{' in value:
        raise ValueError('Ruby interpolation is not permitted in package URLs')
    return json.dumps(value, ensure_ascii=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    destination = parser.add_mutually_exclusive_group()
    destination.add_argument('--repo', help='Override the configured GitHub OWNER/REPO hosting releases')
    destination.add_argument('--local', action='store_true', help='Generate a file-URL test cask instead of a GitHub release cask')
    parser.add_argument('--skip-build', action='store_true', help='Package the existing app (for an already signed/stapled release)')
    args = parser.parse_args()
    if not args.repo and not args.local:
        config = json.loads((ROOT / 'packaging/homebrew/release.json').read_text())
        args.repo = config['repository']
    if args.repo and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*', args.repo):
        parser.error('--repo must be a GitHub OWNER/REPO')
    if not args.skip_build:
        subprocess.run([str(ROOT / 'scripts/package.sh')], cwd=ROOT, check=True)
    app = ROOT / 'dist/Disk Checker.app'
    with (app / 'Contents/Info.plist').open('rb') as handle:
        info = plistlib.load(handle)
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('App version must be MAJOR.MINOR.PATCH')
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    archs = set(subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split())
    architectures = {frozenset({'arm64'}): ('arm64', ':arm64'),
                     frozenset({'x86_64'}): ('x86_64', ':x86_64'),
                     frozenset({'arm64', 'x86_64'}): ('universal', None)}
    if frozenset(archs) not in architectures:
        raise ValueError(f'Unsupported binary architectures: {archs}')
    suffix, restriction = architectures[frozenset(archs)]
    if info['LSMinimumSystemVersion'] != '14.0':
        raise ValueError('Update the cask macOS requirement to match LSMinimumSystemVersion')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    archive_dir = ROOT / ('dist' if args.repo else 'dist/local')
    archive_dir.mkdir(parents=True, exist_ok=True)
    archive = archive_dir / f'Disk-Checker-{version}-{suffix}.zip'
    # ditto must start fresh: reusing a ZIP can preserve obsolete entries.
    archive.unlink(missing_ok=True)
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
    sha256 = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{sha256}  {archive.name}\n')
    tap = ROOT / ('dist/homebrew-disk-checker' if args.repo else 'dist/homebrew-disk-checker-local')
    (tap / 'Casks').mkdir(parents=True, exist_ok=True)
    homepage = f'https://github.com/{args.repo}' if args.repo else ROOT.as_uri()
    url = f'{homepage}/releases/download/v{version}/{archive.name}' if args.repo else archive.as_uri()
    lines = ['cask "disk-checker" do', f'  version "{version}"', f'  sha256 "{sha256}"', '',
             f'  url {ruby_string(url)}', '  name "Disk Checker"',
             '  desc "Explore Mac storage and move selected files and screenshots to Trash"',
             f'  homepage {ruby_string(homepage)}', '']
    if restriction:
        lines.append(f'  depends_on arch: {restriction}')
    lines += ['  depends_on macos: :sonoma', '', '  app "Disk Checker.app"', 'end', '']
    cask = tap / 'Casks/disk-checker.rb'
    cask.write_text('\n'.join(lines))
    if args.repo:
        tracked_cask = ROOT / 'Casks/disk-checker.rb'
        tracked_cask.parent.mkdir(parents=True, exist_ok=True)
        tracked_cask.write_text(cask.read_text())
    (tap / 'README.md').write_text('# Disk Checker Homebrew tap\n\n' +
        ('Release cask. The source repository also contains this cask under `Casks/` and can be used as a custom-URL tap.\n' if args.repo else
         'Local test cask. Its file URL only works on the machine that generated it. Do not publish this cask.\n'))
    print(f'Archive: {archive}\nSHA-256: {sha256}\nCask: {cask}')
    if not args.repo:
        print('Local package only. Omit --local to use the configured GitHub repository.')


if __name__ == '__main__':
    main()
