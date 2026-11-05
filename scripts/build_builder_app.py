#!/usr/bin/env python3
# Builds Slotless (dm/builder), the Mac app that runs build_ipa_from_nsp.py without a terminal, into dm/builder/build/Slotless.app, or the path -o names.
# The Command Line Tools are enough for this (a game's build needs Xcode, which the app checks for). The app keeps this checkout's path in its Info.plist, as the script it runs lives here.
# --release makes an app for other people instead, and its zip beside it: no path of this checkout, but the commit it was built from, which the app downloads from GitHub at its first start. So the commit must be pushed.
# It is signed ad-hoc: a player opens it the first time through System Settings > Privacy & Security > Open Anyway.
# Usage: build_builder_app.py [-o <app>] [--open] [--release [--allow-unpushed]]   (exit 1 on error)
import argparse, plistlib, re, shutil, struct, subprocess, sys, tempfile, zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SOURCES = REPO / 'dm/builder'
MINOS = '15.0'


# The app's icon, drawn here so that a build needs no image tools or stored image: the site's mascot, a cartridge standing on a circuit board, on Apple's icon grid
MASCOT = ['..kkkkkkkk..', '.krrrrrrrrk.', '.krrrrrrrrk.', '.krwwwwwwrk.', '.krwkwwkwrk.', '.krwkwwkwrk.', '.krwwwwwwrk.', '.krwwkkwwrk.', '.krwwwwwwrk.', '.krrrrrrrrk.', '.krRRRRRRrk.', '..kkkkkkkk..', '..kk....kk..', '..kk....kk..']
COLOURS = {'k': (0x15, 0x10, 0x4a), 'r': (0xff, 0x4d, 0x6d), 'R': (0xc9, 0x2a, 0x4b), 'w': (0xff, 0xff, 0xff), 'sky': (0x3a, 0x2b, 0xe8), 'yolk': (0xff, 0xd2, 0x3f)}


def icon_png(size):
    tile, inset, radius, ground = 1024, 100, 185, 712   # in units of a 1024 icon: the rounded square's inset and corner, the board's top
    cell = 34                                           # one mascot pixel
    left, top = (tile - 12 * cell) // 2, ground - 14 * cell
    rows = []
    for py in range(size):
        row = bytearray([0])   # PNG's filter byte
        for px in range(size):
            x, y = (px + .5) * tile / size, (py + .5) * tile / size
            dx, dy = max(abs(x - tile / 2) - (tile / 2 - inset - radius), 0), max(abs(y - tile / 2) - (tile / 2 - inset - radius), 0)
            edge = (dx * dx + dy * dy) ** .5 - radius                                   # the distance from the rounded square, negative inside
            cover = max(0., min(1., .5 - edge * size / tile))
            colour = COLOURS['sky']
            if y >= ground:
                colour = COLOURS['k']
                if ground + 44 <= y < ground + 68 and int(x) % 128 < 72: colour = COLOURS['yolk']
            mx, my = int((x - left) // cell), int((y - top) // cell)
            if 0 <= mx < 12 and 0 <= my < 14 and MASCOT[my][mx] != '.': colour = COLOURS[MASCOT[my][mx]]
            row += bytes((*colour, round(cover * 255)))
        rows.append(bytes(row))

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')


def make_icon(icns):
    with tempfile.TemporaryDirectory(prefix='slotless_icon_') as t:
        iconset = Path(t) / 'Slotless.iconset'
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            (iconset / f'icon_{points}x{points}.png').write_bytes(icon_png(points))
            (iconset / f'icon_{points}x{points}@2x.png').write_bytes(icon_png(points * 2))
        subprocess.run(['iconutil', '-c', 'icns', '-o', icns, iconset], check=True)


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
        (app / 'Contents/Resources').mkdir()
        make_icon(app / 'Contents/Resources/Slotless.icns')
    with open(app / 'Contents/Info.plist', 'wb') as f:
        plistlib.dump({'CFBundleName': 'Slotless', 'CFBundleDisplayName': 'Slotless', 'CFBundleIdentifier': 'org.nxnative.builder', 'CFBundleExecutable': 'Slotless', 'CFBundleIconFile': 'Slotless',
                       'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.6', 'CFBundleVersion': '6', 'LSMinimumSystemVersion': MINOS, 'NSHighResolutionCapable': True,
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
            subprocess.run(['ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', args.out.resolve(), zipped], check=True)
            print(zipped)
    except (subprocess.CalledProcessError, OSError) as e:
        print(f'[RED] the app was not built: {e}', file=sys.stderr)
        return 1
    print(args.out.resolve())
    if args.open: subprocess.run(['open', args.out.resolve()], check=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
