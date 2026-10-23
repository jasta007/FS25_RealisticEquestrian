# Art

- `icon_512.png`: the mod icon (exported to `icon_RealisticEquestrian.dds`, DXT1, 512x512).
- `logotype_green.png` and `logotype_cream.png`: the logotype on a transparent background, for light
  and dark backgrounds.

The painting is generated, not traced from any artwork: `source/under.py` lays out the scene in flat
shapes, `source/paint.py` repaints it as layered oil-sketch brush strokes, and `source/compose.py`
adds the lettering. The lettering uses Cormorant Garamond Italic and Cormorant SC (SIL Open Font
License); the fonts are not included, only the rendered images.
