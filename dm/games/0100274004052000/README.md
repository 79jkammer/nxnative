# PAYDAY 2 (`0100274004052000`)

1.1.0, SDK 3.5.1, on NVN (1,534 shaders). Modules `main`, `subsdk0` (NintendoSDK_movie) and `sdk`. Overkill's Diesel engine, Wwise.

On the Mac (2026-11-05): a scripted run on an M1 through the title, the menus and into the first heist (Bain: The Basics), with its intro movies, HUD, weapons and 3D level, at the game's own 30 fps (p50 33.4 ms, p95 34.7 ms) and no shader missing. Then a person built it with Slotless from a local checkout and reported that it works; how far they played was not recorded.

## What it needs

| Setting | Where | Why |
|---|---|---|
| 25.3 GB block with a 20 GB alias region: `mem_reserve 0x650000000`, `mem_alias 0x500000000`, `mem_stack 0x10000000`, `app_pool 0xCD500000` | [`game.tsv`](game.tsv) | [Memory](#memory) |
| `sys_resource 0x1000000` | `game.tsv` | the NPDM declares 16 MB of system resource |

## Files

- RomFS: 2,800 files, 9.76 GB. `assets/` holds eight `stream_*.bundle` files (9.40 GB, up to 2 GB each), 2,609 small `*_h.bundle` headers, `bundle_db.blb` and `stream_*.bfs`; `movies/` holds MP4s.
- Shaders are only in `stream_default_0.bundle` and `stream_default_1.bundle` ([reference](../../../docs/reference/shaders.md#diesel-programs-in-stream-bundles)). 4,034 control sections are 1,534 distinct shaders, 767 vertex and 767 pixel, one pair per program.

## Memory

- A request returning to `main+0x4c7ae8` takes 16 GB through `nn::os::AllocateAddressRegion` at alias +1.66 GB in `nninitStartup`; 1.9 GB of it was mapped in the first 15 s. With the 4.38 GB alias region the survey guessed, the host crashes before `nnMain` (exit 139). Measured with `DM_ALIAS_SIZE=0x1000000000` and `DM_REGIONS`. The Mac build's region check now gets the same value by itself ([reference](../../../docs/reference/memory.md#a-games-own-address-region-past-the-alias-region-of-a-mac-build)).

## Driving it on the Mac

`DM_KEYS=30:L+R~1,36:L+R~1,42:L+R~2,50:L+R~2,58:A~1,64:A~1,70:A~1,82:X~0.5,90:X~0.5,100:A~0.5,180:A~0.5,190:X~0.5,200:LUp~6` goes from a fresh start through the title, the menus and into the first heist, then walks forward. The title takes L+R, and a press before it appears (25 s) does nothing.

## Found on this game

- [Diesel programs in stream bundles](../../../docs/reference/shaders.md#diesel-programs-in-stream-bundles): resolved.
- [A game's own address region past the alias region of a Mac build](../../../docs/reference/memory.md#a-games-own-address-region-past-the-alias-region-of-a-mac-build): resolved on the Mac, open on the iPhone.

## Open

- **iPhone:** not built or tested. The 20 GB alias region is over iOS's limit; a smaller one works only if the game's allocator places nothing by fixed offsets, which is not known.
- **Other builds:** only 1.1.0 was seen. The profile came from the one dump.
- **Later play:** the rest of the first heist and other heists, a written save (no save file had been committed when the run stopped), real audio (the runs were silent) and online are not tested.
- `main` imports `glslcCompile` weakly and no module defines it; nothing in these runs called for it.
