"""Compile Slotless's logic and run dm/builder/tests/builder_check.swift; no window or game needed."""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
BUILDER = REPO / 'dm/builder'


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun'), 'needs the macOS Swift toolchain')
class BuilderAppTests(unittest.TestCase):
    def test_logic_and_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            exe = tmp / 'builder_check'
            built = subprocess.run(['xcrun', '-sdk', 'macosx', 'swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path', str(tmp / 'module-cache'), '-o', str(exe),
                                    str(BUILDER / 'Strings.swift'), str(BUILDER / 'BuildCore.swift'), str(BUILDER / 'Controls.swift'), str(BUILDER / 'Device.swift'), str(BUILDER / 'Environment.swift'), str(BUILDER / 'BuilderModel.swift'), str(BUILDER / 'tests/builder_check.swift')],
                                   capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            work = tmp / 'work'
            work.mkdir()
            r = subprocess.run([exe, BUILDER / 'tests/fake_build.py', sys.executable, work], capture_output=True, text=True, timeout=180)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_the_icon_is_a_png_of_the_size_asked(self):   # its corners clear, its middle solid: iconutil rejects anything else, and Finder would show a blank app
        import importlib.util, struct, zlib
        spec = importlib.util.spec_from_file_location('build_builder_app', Path(__file__).resolve().parents[3] / 'scripts/build_builder_app.py')
        script = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(script)
        png = script.icon_png(32)
        self.assertEqual(struct.unpack('>II', png[16:24]), (32, 32))
        pixels = zlib.decompress(png[png.index(b'IDAT') + 4:png.index(b'IEND') - 8])
        alpha = lambda x, y: pixels[y * (1 + 32 * 4) + 1 + x * 4 + 3]
        self.assertEqual(alpha(0, 0), 0)
        self.assertEqual(alpha(16, 16), 255)

    def test_every_text_has_a_translation(self):
        table = (BUILDER / 'Strings.swift').read_text()
        known = set(re.findall(r'^        "((?:[^"\\]|\\.)*)": "', table, re.M))
        self.assertGreater(len(known), 100)
        used = set()
        for f in BUILDER.glob('*.swift'):
            used |= set(re.findall(r'\bL\("((?:[^"\\]|\\.)*)"', f.read_text()))
        used |= set(re.findall(r'\("(?:[\w-]*)", "([^"]+)"\)', (BUILDER / 'BuilderApp.swift').read_text()))   # the game languages
        used |= {'Game', 'Update', 'DLC', 'Package'}   # GamePackage.Kind, through L(p.kind.rawValue)
        self.assertEqual(sorted(used - known), [], 'texts with no translation in Strings.swift')
        self.assertEqual(sorted(known - used), [], 'translations no code uses')

    def test_the_window_has_no_text_outside_L(self):   # a literal here would stay in English in every language
        source = (BUILDER / 'BuilderApp.swift').read_text()
        pattern = r'\b(Text|Button|Label|Toggle|Picker|Section|LabeledContent|DisclosureGroup|TextField|Link)\("|\.(help|accessibilityLabel|messageText|informativeText|message)\s*(\(|=\s*)"|addButton\(withTitle: "'
        self.assertEqual(re.findall(pattern, source), [])

    def test_events_are_the_scripts(self):   # the event names the app reads are the ones docs/frontends.md promises
        doc = (REPO / 'docs/frontends.md').read_text()
        core = (BUILDER / 'BuildCore.swift').read_text()
        for ev in ('stage', 'step', 'progress', 'stage_end', 'shaders_stale', 'say', 'game'):
            self.assertIn(f'| `{ev}` |', doc)
            self.assertIn(f'case "{ev}":', core)

    def test_arguments_exist_in_the_script(self):
        script = (REPO / 'scripts/build_ipa_from_nsp.py').read_text()
        core = (BUILDER / 'BuildCore.swift').read_text()
        flags = set(re.findall(r'"(--[a-z-]+)"', core))
        self.assertGreater(len(flags), 10)
        for flag in flags:
            base = flag.replace('--no-', '--')
            self.assertTrue(f"'{flag}'" in script or f"'{base}'" in script, flag)


if __name__ == '__main__':
    unittest.main()
