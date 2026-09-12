#!/usr/bin/env python3
"""Create a versioned macOS disk image and SHA-256 checksum from Disk Checker."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true', help='Package the existing built app')
    parser.add_argument('--catalina', action='store_true', help='Package the Intel Catalina compatibility app')
    args = parser.parse_args()
    if not args.skip_build:
        subprocess.run([str(ROOT / ('scripts/package-catalina.sh' if args.catalina else 'scripts/package.sh'))], cwd=ROOT, check=True)
    app = ROOT / ('dist/catalina/Disk Checker.app' if args.catalina else 'dist/Disk Checker.app')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('App version must be MAJOR.MINOR.PATCH')
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    archs = frozenset(subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split())
    suffix = {frozenset({'arm64'}): 'arm64', frozenset({'x86_64'}): 'x86_64',
              frozenset({'arm64', 'x86_64'}): 'universal'}.get(archs)
    if suffix is None:
        raise ValueError(f'Unsupported architectures: {archs}')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    variant = 'catalina-' if args.catalina else ''
    output = ROOT / 'dist' / f'Disk-Checker-{version}-{variant}{suffix}.dmg'
    if output.exists():
        raise FileExistsError(f'Refusing to replace an existing disk image: {output}')
    with tempfile.TemporaryDirectory(prefix='dmg-stage-', dir=ROOT / 'dist') as staging:
        stage = Path(staging)
        subprocess.run(['ditto', str(app), str(stage / app.name)], check=True)
        (stage / 'Applications').symlink_to('/Applications')
        (stage / 'Install.txt').write_text(
            f'Disk Checker {version}\n\n'
            'Quit any running Disk Checker copy.\n'
            'Drag Disk Checker.app into Applications, then eject this disk image.\n'
            'Open Disk Checker from Applications.\n\n'
            'Development preview: ad-hoc signed, not Apple-notarized.\n'
            'macOS Gatekeeper may block launch.\n'
            f"Requires macOS {info['LSMinimumSystemVersion']} or later and a compatible processor.\n"
        )
        subprocess.run(['hdiutil', 'create', '-volname', 'Disk Checker', '-srcfolder', str(stage),
                        '-format', 'UDZO', '-fs', 'HFS+', str(output)], check=True)
    subprocess.run(['hdiutil', 'verify', str(output)], check=True)
    hasher = hashlib.sha256()
    with output.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            hasher.update(block)
    digest = hasher.hexdigest()
    output.with_suffix('.dmg.sha256').write_text(f'{digest}  {output.name}\n')
    print(f'Disk image: {output}\nSHA-256: {digest}')


if __name__ == '__main__':
    main()
