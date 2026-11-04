# Teenage Mutant Ninja Turtles: Shredder's Revenge (`0100FE701475A000`)

1.0.9, SDK 13.3.2, on NVN (88 shaders, MonoGame effects). Modules `main`, `subsdk0` (NintendoSDK_movie), `subsdk1` (NintendoSDK_NVN) and `sdk`; `subsdk2` (GLSLC) is not loaded. MonoGame for the Switch, its C# compiled to C++ by BRUTE. Two DLC packs.

On the Mac (2026-11-04): a scripted run through the logos, the intro movie, the main menu, the tutorial, character select, the opening cutscene and the start of the first stage at 60 fps, with a save written; then a person played it and reported that it works. Not checked: the whole game, and the iPhone.

The profile comes from one dump, a 1.0.9 with a Russian translation and voice mod: its `build` row and shader tables are that dump's. Whether an unmodified 1.0.9 has the same module build IDs is not known.

## What it needs

| Setting | Where | Why |
|---|---|---|
| 3.25 GB layout: `mem_reserve 0x100000000`, `mem_alias 0x10000000`, `mem_stack 0x10000000`, `app_pool 0xCD500000` | [`game.tsv`](game.tsv) | the provisional layout, which holds |
| `sys_resource 0x0` | `game.tsv` | the NPDM declares 0 MB of system resource |
| `mem_used 0xabd4000` | `game.tsv` | the rewritten modules are over the default 64 MB; written by the NSP script after the rewrite |
| `eos_offline on` | `game.tsv` | the game does not expect Epic Online Services to fail ([reference](../../../docs/reference/services.md#online-sdks-in-nros-are-never-loaded)) |
| `start_behind on` | `game.tsv` | a workaround for the game's own race at each loading screen ([reference](../../../docs/reference/threads.md#a-started-thread-queues-behind-its-pinned-starter)) |

## Files

- RomFS: 3,499 files, 1.05 GB. `Content/` holds raw deflate files: `.zxnb` (XNB, 13 effects in `Content/Shaders`) and `.zpbn`; `Content/Audio` (0.56 GB, Opus), `Content/Videos` (0.30 GB, one MP4, one Ogg).
- `nro/EOSSDK-Switch-Shipping.nro`, with three older copies: Epic Online Services, refused by the host.

## Driving it on the Mac

`DM_KEYS=32:A*8/2,50:Plus~3,58:A*40/3` goes from the title through the menus, skips the tutorial (Plus is held) and starts the first stage, at about 180 s.

## Found on this game

- [MGFX version 10 effects in raw deflate `.zxnb` files](../../../docs/reference/shaders.md#mgfx-version-10-effects-in-raw-deflate-zxnb-files): resolved.
- [Online SDKs in NROs are never loaded](../../../docs/reference/services.md#online-sdks-in-nros-are-never-loaded): `eos_offline`, current. Online play does not work.
- [A started thread queues behind its pinned starter](../../../docs/reference/threads.md#a-started-thread-queues-behind-its-pinned-starter): a workaround, current. Why the race does not crash a Switch is open.

## Open

- `[RED] DrawTexture with blending on (targets 0x1): drawn without it`, once per run during the intro movie; nothing visible was traced to it.
- The `start_behind` bound of 20 ms: later loading screens were seen to work, but it does not remove the race.
