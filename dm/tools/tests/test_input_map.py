"""The player's controller and keyboard maps (dm/host/input_map.h), compiled and run on their own."""
from pathlib import Path
import subprocess
import tempfile
import unittest

HEADER = Path(__file__).resolve().parents[2] / 'host'
SOURCE = r'''
#include <assert.h>
#include <stdio.h>
#include "input_map.h"
int main(void) {
    uint8_t m[IM_BUTTONS], k[IM_KEYS];
    pad_map_parse(NULL, 0, m);
    for (int i = 0; i < IM_BUTTONS; i++) assert(m[i] == i);
    assert(pad_map_apply(0x3, m) == 0x3);
    pad_map_parse(NULL, 1, m);
    assert(pad_map_apply(1u << 0, m) == 1u << 1 && pad_map_apply(1u << 3, m) == 1u << 2);
    pad_map_parse("A=ZR,LEFT=DOWN", 0, m);
    assert(pad_map_apply(1u << 0, m) == 1u << 9 && pad_map_apply(1u << 12, m) == 1u << 15 && pad_map_apply(1u << 1, m) == 1u << 1);
    assert(pad_map_apply(1u << 0 | 1ull << 63, m) == (1u << 9 | 1ull << 63));   // DM_BTN_SHAKE passes
    pad_map_parse("BAD=A,A=NOPE,,=,B", 0, m);   // nothing here is a mapping
    for (int i = 0; i < IM_BUTTONS; i++) assert(m[i] == i);
    pad_map_parse("A=B,X", 0, m); assert(m[0] == 1);   // a cut list keeps what came before
    key_map_parse(NULL, k);
    assert(k[38] == 1 && k[40] == 2 && k[49] == IM_SHAKE + 1 && k[13] == IM_LSU + 1 && k[123] == 13 && k[50] == 0);
    key_map_parse("A=50", k);   // moved: the old key does nothing now
    assert(k[50] == 1 && k[38] == 0 && k[40] == 2);
    key_map_parse("A=40", k);   // onto B's key: B goes without one
    assert(k[40] == 1);
    for (int i = 0; i < IM_KEYS; i++) assert(k[i] != 2);
    key_map_parse("RSU=13", k);
    assert(k[13] == IM_RSU + 1);
    key_map_parse("A=999,A=-1,NOPE=3,B=", k);
    assert(k[38] == 1 && k[40] == 2);
    puts("ok");
    return 0;
}
'''


class InputMapTests(unittest.TestCase):
    def test_maps(self):
        with tempfile.TemporaryDirectory() as tmp:
            c, exe = Path(tmp) / 't.c', Path(tmp) / 't'
            c.write_text(SOURCE)
            subprocess.run(['cc', '-Wall', '-Werror', '-I', str(HEADER), str(c), '-o', str(exe)], check=True)
            self.assertEqual(subprocess.run([str(exe)], capture_output=True, text=True, check=True).stdout.strip(), 'ok')


if __name__ == '__main__':
    unittest.main()
