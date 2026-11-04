"""MonoGame effects of MGFX version 10 and their raw deflate .zxnb files. Synthetic bytes only."""
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

READER = b'\x01\x78' + b'Microsoft.Xna.Framework.Content.EffectReader, MonoGame.Framework, Version=2.22.5.0, Culture=neutral, PublicKeyToken=null'.ljust(0x78, b' ') + bytes(5)


def name(text): return bytes([len(text)]) + text


def shader(vertex, stage):
    control, code = stage
    bytecode = struct.pack('<I', len(control)) + control + struct.pack('<I', len(code)) + code
    sampler = bytes(3) + b'\0' + name(b'Texture') + b'\0'
    return bytes([vertex]) + struct.pack('<I', len(bytecode)) + bytecode + b'\x01' + sampler + b'\x01\0' + b'\x01' + name(b'POSITION') + bytes(4)


def effect(version):
    """One constant buffer with one parameter, a pixel and a vertex shader, one parameter, one technique with a pass; only the count widths differ"""
    if version == 10: count = lambda n: struct.pack('<i', n); index = count; none = -1
    else: count = lambda n: bytes([n]); index = count; none = 255
    buffer = count(1) + name(b'global') + struct.pack('<h', 16) + count(1) + index(0) + struct.pack('<H', 0)
    shaders = count(2) + shader(0, fz.PS) + shader(1, fz.VS)
    parameters = count(1) + b'\x01\x03' + name(b'DiffuseColor') + b'\0' + count(0) + b'\x01\x04' + count(0) + count(0) + bytes(16)
    passes = count(1) + b'\0' + count(0) + index(1) + index(0) + bytes(3)
    techniques = count(1) + name(b'Effect') + count(0) + passes
    body = b'MGFX' + bytes([version, 40]) + bytes(4) + buffer + shaders + parameters + techniques
    return body + (b'MGFX' if version == 10 else b''), none


def xnb(version):
    body = effect(version)[0]
    return b'XNBS\x05\x01' + struct.pack('<I', 14 + len(READER) + 4 + len(body)) + READER + struct.pack('<I', len(body)) + body


def deflate(data):
    z = zlib.compressobj(wbits=-15)
    return z.compress(data) + z.flush()


class Version10(unittest.TestCase):
    def scan(self, data, rel):
        with tempfile.TemporaryDirectory() as t, contextlib.redirect_stdout(io.StringIO()) as log:
            path = Path(t) / Path(rel).name; path.write_bytes(data)
            result = ss.scan_file((str(path), rel))
        return result, log.getvalue()

    def test_effect_versions_give_the_same_shaders(self):
        keys = {}
        for version in (8, 10):
            with self.subTest(version=version):
                (_, found, _, _), log = self.scan(xnb(version), 'Content/Effects/a.xnb')
                self.assertEqual(log, ''); self.assertEqual(sorted(v[1] for v in found.values()), ['ps', 'vs'])
                keys[version] = set(found)
        self.assertEqual(keys[8], keys[10])

    def test_zxnb_is_a_deflated_xnb(self):
        plain = self.scan(xnb(10), 'Content/Shaders/a.xnb')[0][1]
        (_, found, _, _), log = self.scan(deflate(xnb(10)), 'Content/Shaders/a.zxnb')
        self.assertEqual(log, ''); self.assertEqual(set(found), set(plain))

    def test_other_zxnb_content_holds_no_shaders(self):
        (_, found, _, extra), log = self.scan(deflate(b'XNBw\x05\x01' + bytes(64)), 'Content/2d/a.zxnb')
        self.assertEqual(log, ''); self.assertEqual(found, {}); self.assertNotIsInstance(extra, tuple)

    def test_damaged_zxnb_is_named(self):
        for label, data in [('cut', deflate(xnb(10))[:-8]), ('not deflate', b'\xff' * 64), ('not an XNB', deflate(bytes(64)))]:
            with self.subTest(damage=label):
                (_, found, _, extra), log = self.scan(data, 'Content/Shaders/a.zxnb')
                self.assertEqual(found, {}); self.assertEqual(extra[0], 'unreadable'); self.assertIn('[RED]', log)

    def test_a_stray_marker_in_main_is_left_alone(self):
        for tail in (b'MGFX', b'MGFX' + bytes(64), b'MGFX\x0a\x28' + bytes(4) + struct.pack('<i', 1)):
            with self.subTest(tail=tail[:6]):
                self.assertEqual(ss.mgfx_shaders(bytes(16) + tail, 'main'), [])


if __name__ == '__main__': unittest.main()
