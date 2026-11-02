#!/usr/bin/env python3
# Stands in for scripts/build_ipa_from_nsp.py in NXNative Builder's checks: it writes the JSON events of docs/frontends.md and exits as the script does. --app-name picks what it does, so the app
# needs no test mode: finish (the default), fail, or hang (runs a child and waits to be interrupted, FAKE_CHILD_PID naming a file for its pid). FAKE_DELAY: seconds per progress step.
import json, os, signal, subprocess, sys, time


def ev(event, **f): print(json.dumps({'ev': event, 't': time.time(), **f}), flush=True)


def main():
    argv = sys.argv[1:]
    mode = argv[argv.index('--app-name') + 1] if '--app-name' in argv else 'finish'
    delay = float(os.environ.get('FAKE_DELAY', '0'))
    out = argv[argv.index('-o') + 1] if '-o' in argv else os.path.join(argv[0], 'Game.ipa')
    ev('say', msg=f'[12:00:00] game: {argv[0]}')
    stages = ['nx_extract', 'extract v0', 'rewrite', 'shader split', 'iOS shaders', 'IPA build', 'IPA pack']
    for k, name in enumerate(stages, 1):
        ev('stage', k=k, n=len(stages), name=name, step='working')
        for i in range(1, 11):
            ev('progress', k=k, name=name, step='working', done=i * 2**28, total=10 * 2**28, unit='B', est=k % 2 == 0, note='', frac=i / 11, eta=(10 - i) * delay, elapsed=i * delay)
            time.sleep(delay)
        if mode == 'fail' and k == 3:
            ev('stage_end', k=k, name=name, ok=False, summary='', elapsed=10 * delay)
            ev('say', msg='---- last lines of /tmp/logs/rewrite.log ----\nsomething failed')
            ev('say', msg='[RED] patch_nso.py exit code 1 (full output: /tmp/logs/rewrite.log)')
            print('a line on stderr', file=sys.stderr)
            return 1
        if mode == 'hang' and k == 2:
            child = subprocess.Popen(['/bin/sleep', '600'])
            with open(os.environ['FAKE_CHILD_PID'], 'w') as f: f.write(str(child.pid))
            ev('say', msg='waiting')
            child.wait()
            return 130 if child.returncode == -signal.SIGINT else 3
        ev('stage_end', k=k, name=name, ok=True, summary=f'{name} summary', elapsed=10 * delay)
    if '--prepare-xcode' in argv:   # the messages an install goes on from, and the project's resource list
        project = os.path.join(argv[0], 'build/xcode/DmIOS.xcodeproj')
        os.makedirs(project, exist_ok=True); os.makedirs(os.path.join(os.path.dirname(project), 'Gen'), exist_ok=True)
        image = os.path.join(argv[0], 'build/RomFS.img')
        with open(image, 'w') as f: f.write('image')
        with open(os.path.join(os.path.dirname(project), 'Gen/resources.env'), 'w') as f: f.write(f"DM_RESOURCE_ROMFS='{image}'\n")
        bundle = argv[argv.index('--bundle-id') + 1] if '--bundle-id' in argv else 'org.nxnative.fake'
        ev('say', msg=f'[12:00:10] app name: Game; version: 1.0; bundle ID: {bundle}')
        ev('say', msg=f'[12:00:30] game project: {project}')
        return 0
    ev('say', msg=f'[12:00:30] done: {out} (4.2 GB)')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        ev('say', msg='[RED] interrupted')
        sys.exit(130)
