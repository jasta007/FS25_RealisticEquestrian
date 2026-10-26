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
