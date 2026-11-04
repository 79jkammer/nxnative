#!/bin/bash
# Copy a game's files to its iPhone app's Documents/romfs.img; resources.env also replaces Documents/aoc with the build's DLC set (see docs/development.md, Quick reinstalls).
# The files go as one RomFS image (dm/tools/romfs_image.py), packed next to the RomFS folder on first use: one file copies at full speed, where a folder of a few hundred
# thousand files ran the phone's file service out of open files (Tears of the Kingdom: 304,000). main.m only takes a complete image, so a copy cut off halfway is never used.
# Usage: push_romfs.sh <device UDID> <bundle ID> <game>_build/xcode/Gen/resources.env [--repack]
#    or: push_romfs.sh <device UDID> <bundle ID> <RomFS.img>   (the image build_ipa_from_nsp.py --romfs separate prints: <game>_build/extract/<version>/RomFS.img)
# A build made with DM_COPY_ROMFS=NO carries the identity of its image (romfs.id); the app uses only a Documents/romfs.img with that identity, so push again whenever the game or its version changed.
# Run it while the app (any build with that bundle ID) is installed. Rerun after a failure, before launching the game. A direct image push leaves DLC unchanged.
set -eu
[ "$#" = 3 ] || { [ "$#" = 4 ] && [ "$4" = --repack ]; } || { echo "usage: $0 <device UDID> <bundle ID> <resources.env> [--repack]" >&2; exit 1; }
dev=$1 id=$2 sync_aoc=0
case "$3" in
    *.env) sync_aoc=1; DM_RESOURCE_AOC=; source "$3";;
    *) DM_RESOURCE_ROMFS=$3; DM_RESOURCE_MARKER=;;
esac
if [ "$sync_aoc" = 1 ] && [ -n "$DM_RESOURCE_AOC" ] && [ ! -d "$DM_RESOURCE_AOC" ]; then
    echo "[RED] Add-on content unavailable: $DM_RESOURCE_AOC" >&2; exit 1
fi
if [ -f "$DM_RESOURCE_ROMFS" ]; then img=$DM_RESOURCE_ROMFS
else
    img=${DM_RESOURCE_ROMFS%/}.img
    repack=${4:-}; set -- "$DM_RESOURCE_ROMFS" "$img"
    [ "$repack" = --repack ] || set -- --reuse "$@"
    python3 -I "$(dirname "$0")/../dm/tools/romfs_image.py" "$@"
fi
python3 -I "$(dirname "$0")/../dm/tools/romfs.py" "$img" "${DM_RESOURCE_MARKER:-}"
echo "identity: $(python3 -I "$(dirname "$0")/../dm/tools/romfs_image.py" --identity "$img")"
xcrun devicectl device copy to --device "$dev" --domain-type appDataContainer --domain-identifier "$id" --source "$img" --destination Documents/romfs.img -q
# Add-on content (DLC): <index>.img files or legacy <index>/ trees, merged into Documents/aoc. Never with --remove-existing-content true: devicectl 651 (Xcode 27.2) then empties the app's Documents
# and tmp, saves and the image just copied included, whatever the destination is (docs/reference/packing.md). It also cannot send an empty folder, so a build with no DLC sends none.
# devicectl has no delete, so DLC this build no longer has stays on the phone, and the host would still report it as owned: say so.
if [ "$sync_aoc" = 1 ]; then
    aoc=$DM_RESOURCE_AOC
    if [ -n "$aoc" ] && [ -n "$(ls -A "$aoc")" ]; then
        xcrun devicectl device copy to --device "$dev" --domain-type appDataContainer --domain-identifier "$id" --source "$aoc" --destination Documents/aoc -q
        echo "DLC on the phone: $id"
    fi
    stale=
    for entry in $(xcrun devicectl device info files --device "$dev" --domain-type appDataContainer --domain-identifier "$id" --subdirectory Documents 2> /dev/null | awk '{print $1}' | sed -n 's#^aoc/\([1-9][0-9]*\(\.img\)\{0,1\}\)$#\1#p'); do
        [ -n "$aoc" ] && [ -e "$aoc/$entry" ] || stale="$stale $entry"
    done
    [ -z "$stale" ] || echo "[RED] Documents/aoc on the phone also holds DLC this build does not have:$stale. The game still sees it; only deleting the app removes it, which deletes its saves too."
fi
echo "game files on the phone: $id"
