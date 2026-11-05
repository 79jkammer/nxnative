"""Diesel programs in zlib streams of a stream bundle. Synthetic bytes only."""
import contextlib
import io
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'dm/tools/fuzz'))
import fuzz_shader_split as fz
ss = fz.ss


def stage(pair, ctl_len=0x848):
    """(control, code) of a stage: the control section sized to its own length, naming its code's length"""
    control, code = pair
    c = bytearray(control.ljust(ctl_len, b'\0'))[:ctl_len]
    struct.pack_into('<I', c, 0x20, ctl_len); struct.pack_into('<I', c, 0x704, len(code))
    return bytes(c), code


def program(stages=(fz.VS, fz.PS), lie=0):
    """Records, then the control sections, then the code areas; lie: added to the first record's code length"""
    parts = [stage(s) for s in stages]
    at = 0x40 + 0x20 * len(parts)
    records, ctls, codes = b'', b'', b''
    ko = at + sum(len(c) for c, _ in parts)
    for i, (c, k) in enumerate(parts):
        records += struct.pack('<2Q2I', at + len(ctls), ko + len(codes), len(k) + (lie if not i else 0), len(c)) + bytes(8)
        ctls += c; codes += k
    return bytes(0x40) + records + ctls + codes


def bundle(*streams):
    """Each stream with the bundle's trailer, among stored bytes"""
    return b'RIFF' + bytes(61) + b''.join(zlib.compress(s) + struct.pack('<I', len(s)) + b'\xaa' * 13 for s in streams)


class Diesel(unittest.TestCase):
    def scan(self, data, name='stream_default_0.bundle', db=True):
        with tempfile.TemporaryDirectory() as t, contextlib.redirect_stdout(io.StringIO()) as log:
            path = Path(t) / name; path.write_bytes(data)
            if db: (Path(t) / 'bundle_db.blb').write_bytes(b'\0')
            result = ss.scan_file((str(path), 'assets/' + name))
        return result, log.getvalue()

    def test_streams_are_found_among_stored_bytes(self):
        plain = [b'first' * 99, b'second' * 99]
        self.assertEqual([d for _, d in ss.diesel_streams(bundle(*plain))], plain)

    def test_a_cut_stream_ends_the_walk_quietly(self):
        whole = zlib.compress(b'whole' * 99)
        self.assertEqual([d for _, d in ss.diesel_streams(whole + zlib.compress(b'cut' * 999)[:-8])], [b'whole' * 99])

    def test_a_program_gives_its_stages_and_their_pair(self):
        (_, found, pairs, _), log = self.scan(bundle(b'other' * 99, b'pad' + program()))
        self.assertEqual(log, ''); self.assertEqual(sorted(v[1] for v in found.values()), ['ps', 'vs'])
        vs, ps = (ss.skey(*stage(s)) for s in (fz.VS, fz.PS))
        self.assertEqual(set(found), {vs, ps}); self.assertEqual(pairs, {(vs, ps)})

    def test_a_section_with_no_good_record_is_named(self):
        (_, found, _, _), log = self.scan(bundle(program(lie=0x100)))
        self.assertEqual(sorted(v[1] for v in found.values()), ['ps']); self.assertIn('[RED]', log); self.assertIn('1 control section', log)

    def test_only_a_stream_bundle_beside_its_database_is_walked(self):
        data = bundle(program())
        for name, db in (('stream_default_h.bundle', True), ('0055338f6552879f_h.bundle', True), ('stream_default_0.bundle', False)):
            with self.subTest(name=name, db=db):
                self.assertEqual(self.scan(data, name, db)[0][1], {})


if __name__ == '__main__': unittest.main()
