# Art

- `icon_512.png`: the mod icon (exported to `icon_RealisticEquestrian.dds`, DXT1, 512x512).
- `logotype_green.png` and `logotype_cream.png`: the logotype on a transparent background, for light
  and dark backgrounds.

The painting is John Frederick Herring Senior, *The Interior of a Stable with a Dapple Grey Horse in
Harness, with Ducks, Goats, and a Cockerel by a Manger* (1843). Herring died in 1856, so the work is
in the public domain. `source/herring_stable_1843.png` is the square crop used, lightly retouched to
remove one duck. `source/compose_icon.py` darkens the top and sets the logotype above the horse's
head. The lettering uses Playfair Display SC (SIL Open Font License); the
fonts are not included, only the rendered images.

The icon carries the author's signature, "Jasta007", painted into the straw at the bottom left
(`sign()` in `compose_icon.py`, Liberation Serif Italic), and both DDS files name the author in
their header's reserved bytes (`mark_dds()`). The PNGs carry an Author text chunk.

`source/dressage_arenas.py` builds the dressage arenas in `placeables/dressageArena/` (the .i3d with
inline geometry, the placeable .xml, the letter texture and the shop images). Change the script and
run it again rather than editing those files. Letters use DejaVu Sans Bold (rendered only).

`source/xc_jumps.py` builds the cross country fences in `placeables/xcJumps/`: the log piles (bark,
log end and flag textures painted by the script, inline geometry, one invisible static collision
prism with Riding Hall 2k26's jump collision filter) and the fence markers (gold rails, hidden
in game by `EqXcMarkers`). The shop images are small software renders of the meshes; PNG copies
go to `art/previews/` (not in the mod). Change the script and run it again rather than editing those files.
