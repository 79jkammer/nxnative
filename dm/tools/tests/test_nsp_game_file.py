"""NSP script: --game-file names the game by one of its files, in a folder that holds others (Downloads), even when only the package itself can say which game it is."""
import importlib.util
import shutil
import struct
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('build_ipa_from_nsp', REPO / 'scripts/build_ipa_from_nsp.py')
nsp = importlib.util.module_from_spec(spec)
sys.modules['build_ipa_from_nsp'] = nsp
spec.loader.exec_module(nsp)

FIRST, SECOND, NEW = 0x0100AAAA00000000, 0x0100BBBB00000000, 0x0100CCCC00000000


class GameFile(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='nsp_game_file_'))
        self.addCleanup(shutil.rmtree, self.tmp)
        for name in (f'First [{FIRST:016X}][v0].nsp', f'Second [{SECOND:016X}][v0].nsp', 'New game.nsp'):
            (self.tmp / name).write_bytes(b'PFS0' + struct.pack('<III', 0, 0, 0))
        self.read = lambda p: NEW if p.name == 'New game.nsp' else None

    def test_a_file_without_a_tag_is_read_from_the_package(self):
        self.assertEqual(nsp.game_of_file(self.tmp / 'New game.nsp', self.read), NEW)

    def test_a_tagged_file_needs_no_reading(self):
        self.assertEqual(nsp.game_of_file(self.tmp / f'First [{FIRST:016X}][v0].nsp'), FIRST)

    def test_an_update_or_dlc_names_its_game(self):
        for tid in (FIRST + 0x800, FIRST + 0x1001):
            p = self.tmp / f'Extra [{tid:016X}][v1].nsp'
            p.write_bytes(b'PFS0' + struct.pack('<III', 0, 0, 0))
            self.assertEqual(nsp.game_of_file(p), FIRST)

    def test_the_chosen_game_is_packed_from_a_folder_of_others(self):
        app, fam = nsp.scan_nsps(self.tmp, self.read, want=nsp.game_of_file(self.tmp / 'New game.nsp', self.read))
        self.assertEqual((app, fam['base'].name), (NEW, 'New game.nsp'))

    def test_a_file_that_cannot_be_read_says_so(self):
        with self.assertRaisesRegex(nsp.BuildError, 'could not be read'):
            nsp.game_of_file(self.tmp / 'New game.nsp', lambda p: None)

    def test_a_missing_file_says_so(self):
        with self.assertRaisesRegex(nsp.BuildError, 'no such game file'):
            nsp.game_of_file(self.tmp / 'Gone.nsp', self.read)


if __name__ == '__main__':
    unittest.main()
