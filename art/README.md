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

`source/xc_jumps.py` builds the cross country fences in `placeables/xcJumps/`: the log piles (two
barks with moss, lichen and normal maps, log ends and flags, all painted by the script; bowed, lumpy
logs with knots, branch stubs and leaning sawn ends; inline geometry, one invisible static collision
prism with Riding Hall 2k26's jump collision filter), the cross country flags (`courseFlags`, a newFence: a white and a red flag post, a thin pole with
a pennant wrapped round it, and gold height bars for 0.6, 0.9 and 1.2 m that `EqXcFlags` shows only
in construction mode) and the drop walls (painted planks and peeled posts, a
half-round log on the lip, triangle side walls, a plank deck on top; collision on the face, deck and sides). The shop images are small software renders of the meshes; PNG copies
go to `art/previews/` (not in the mod). Change the script and run it again rather than editing those files.

`source/bleachers.py` builds the bleachers in `placeables/bleachers/` (3 rows x 6 m, 5 x 10 m and
8 x 16 m): a stepped steel frame with aluminium benches and a back rail, and a row of sponsor
boards in front. Each board's face is its own shape (`eqSponsor_<n>`) with its own material, so
`EqSponsors` can put one of the game's brand logos on it at run time; the texture it starts with is
our own board. Change the script and run it again rather than editing those files.

The art scripts write DDS files with `source/eqdds.py`: shop images as BC7, 3D textures as DXT1
with mipmaps, as GIANTS' TestRunner wants. It needs `pip install etcpak`. The scripts write inline
i3d geometry, so after running one, open its .i3d files in GIANTS Editor and Save (with Preferences >
Save "force external binary files" on) to get the
binary `.i3d.shapes` files.
