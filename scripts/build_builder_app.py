#!/usr/bin/env python3
# Builds Slotless (dm/builder), the Mac app that runs build_ipa_from_nsp.py without a terminal, into dm/builder/build/Slotless.app, or the path -o names.
# The Command Line Tools are enough for this (a game's build needs Xcode, which the app checks for). The app keeps this checkout's path in its Info.plist, as the script it runs lives here.
# --release makes an app for other people instead, and its zip beside it: no path of this checkout, but the commit it was built from, which the app downloads from GitHub at its first start. So the commit must be pushed.
# It is signed ad-hoc: a player opens it the first time through System Settings > Privacy & Security > Open Anyway.
# Usage: build_builder_app.py [-o <app>] [--open] [--release [--allow-unpushed]]   (exit 1 on error)
import argparse, plistlib, re, shutil, subprocess, sys, tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SOURCES = REPO / 'dm/builder'
MINOS = '15.0'


def git(*args):
    return subprocess.run(['git', '-C', REPO, *args], check=True, capture_output=True, text=True).stdout.strip()


def engine_info(allow_unpushed):   # the commit a released app downloads, as an archive of the repository on GitHub
    origin = git('remote', 'get-url', 'origin')
    m = re.search(r'github\.com[:/]([^/]+/[^/]+?)(\.git)?$', origin)
    if not m: raise OSError(f'origin is not a GitHub repository: {origin}')
    commit = git('rev-parse', 'HEAD')
    if not allow_unpushed:
        if git('status', '--porcelain', '--untracked-files=no') or git('ls-files', '--others', '--exclude-standard', 'dm/builder', 'scripts'):
            raise OSError('this checkout has uncommitted changes, which the released app would not download: commit and push them first')
        if not git('branch', '-r', '--contains', commit):
            raise OSError(f'{commit[:12]} is not pushed: the released app could not download it. Push it first')
    return {'NXEngineURL': f'https://codeload.github.com/{m.group(1)}/tar.gz/{commit}', 'NXEngineCommit': commit}


def build(app, release=None):
    with tempfile.TemporaryDirectory(prefix='slotless_') as t:
        exe = Path(t) / 'Slotless'
        sdk = subprocess.run(['xcrun', '--show-sdk-path'], check=True, capture_output=True, text=True).stdout.strip()
        subprocess.run(['xcrun', 'swiftc', '-sdk', sdk, '-target', f'arm64-apple-macos{MINOS}', '-O', '-swift-version', '5', '-parse-as-library', '-module-cache-path', Path(t) / 'module-cache',
                        '-o', exe, *sorted(SOURCES.glob('*.swift'))], check=True)
        if app.exists(): shutil.rmtree(app)
        (app / 'Contents/MacOS').mkdir(parents=True)
        shutil.copy2(exe, app / 'Contents/MacOS/Slotless')
    with open(app / 'Contents/Info.plist', 'wb') as f:
        plistlib.dump({'CFBundleName': 'Slotless', 'CFBundleDisplayName': 'Slotless', 'CFBundleIdentifier': 'org.nxnative.builder', 'CFBundleExecutable': 'Slotless',
                       'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.1', 'CFBundleVersion': '1', 'LSMinimumSystemVersion': MINOS, 'NSHighResolutionCapable': True,
                       'LSApplicationCategoryType': 'public.app-category.developer-tools', **(release or {'NXRepoRoot': str(REPO)})}, f)
    subprocess.run(['codesign', '--force', '--sign', '-', app], check=True, capture_output=True)


def main():
    ap = argparse.ArgumentParser(description='Build Slotless, the Mac app that builds games without a terminal.')
    ap.add_argument('-o', '--out', type=Path, default=SOURCES / 'build/Slotless.app', help='the app to write (default: %(default)s)')
    ap.add_argument('--open', action='store_true', help='open the app when it is built')
    ap.add_argument('--release', action='store_true', help='an app for other people, with its zip: it downloads the pushed commit it was built from')
    ap.add_argument('--allow-unpushed', action='store_true', help='--release from a commit not pushed yet or with uncommitted changes, to test the app')
    args = ap.parse_args()
    try:
        release = engine_info(args.allow_unpushed) if args.release else None
        build(args.out.resolve(), release)
        if release:
            zipped = args.out.resolve().with_suffix('.zip')
            subprocess.run(['ditto', '-c', '-k', '--keepParent', args.out.resolve(), zipped], check=True)
            print(zipped)
    except (subprocess.CalledProcessError, OSError) as e:
        print(f'[RED] the app was not built: {e}', file=sys.stderr)
        return 1
    print(args.out.resolve())
    if args.open: subprocess.run(['open', args.out.resolve()], check=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
