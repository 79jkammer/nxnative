#!/usr/bin/env python3
# Builds NXNative Builder (dm/builder), the Mac app that runs build_ipa_from_nsp.py without a terminal, into dm/builder/build/NXNative Builder.app, or the path -o names.
# The Command Line Tools are enough for this (a game's build needs Xcode, which the app checks for). The app keeps this checkout's path in its Info.plist, as the script it runs lives here.
# Usage: build_builder_app.py [-o <app>] [--open]   (exit 1 on error)
import argparse, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SOURCES = REPO / 'dm/builder'
MINOS = '15.0'


def build(app):
    with tempfile.TemporaryDirectory(prefix='nxbuilder_') as t:
        exe = Path(t) / 'NXNativeBuilder'
        sdk = subprocess.run(['xcrun', '--show-sdk-path'], check=True, capture_output=True, text=True).stdout.strip()
        subprocess.run(['xcrun', 'swiftc', '-sdk', sdk, '-target', f'arm64-apple-macos{MINOS}', '-O', '-swift-version', '5', '-parse-as-library', '-module-cache-path', Path(t) / 'module-cache',
                        '-o', exe, *sorted(SOURCES.glob('*.swift'))], check=True)
        if app.exists(): shutil.rmtree(app)
        (app / 'Contents/MacOS').mkdir(parents=True)
        shutil.copy2(exe, app / 'Contents/MacOS/NXNativeBuilder')
    with open(app / 'Contents/Info.plist', 'wb') as f:
        plistlib.dump({'CFBundleName': 'NXNative Builder', 'CFBundleDisplayName': 'NXNative Builder', 'CFBundleIdentifier': 'org.nxnative.builder', 'CFBundleExecutable': 'NXNativeBuilder',
                       'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.1', 'CFBundleVersion': '1', 'LSMinimumSystemVersion': MINOS, 'NSHighResolutionCapable': True,
                       'LSApplicationCategoryType': 'public.app-category.developer-tools', 'NXRepoRoot': str(REPO)}, f)
    subprocess.run(['codesign', '--force', '--sign', '-', app], check=True, capture_output=True)


def main():
    ap = argparse.ArgumentParser(description='Build NXNative Builder, the Mac app that builds games without a terminal.')
    ap.add_argument('-o', '--out', type=Path, default=SOURCES / 'build/NXNative Builder.app', help='the app to write (default: %(default)s)')
    ap.add_argument('--open', action='store_true', help='open the app when it is built')
    args = ap.parse_args()
    try:
        build(args.out.resolve())
    except (subprocess.CalledProcessError, OSError) as e:
        print(f'[RED] the app was not built: {e}', file=sys.stderr)
        return 1
    print(args.out.resolve())
    if args.open: subprocess.run(['open', args.out.resolve()], check=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
