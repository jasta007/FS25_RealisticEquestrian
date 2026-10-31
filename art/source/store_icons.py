"""Remake only the shop images (store_*.dds) of the jumps and bleachers.

The generators also write each placeable's .i3d, .xml and textures, and the committed .i3d files
have since been re-saved in GIANTS Editor (binary .i3d.shapes), so running a generator again would
undo that. This runs each one into a scratch folder and copies back only the shop images.
The dressage arenas keep their top-down plans (dressage_arenas.py).

    python3 art/source/store_icons.py
"""
import glob
import os
import random
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bleachers  # noqa: E402
import show_jumps  # noqa: E402
import xc_import  # noqa: E402
import xc_jumps  # noqa: E402


def remake(module, out, run):
    tmp = tempfile.mkdtemp()
    # the generators read some textures from the real folder, so start from a copy of it
    shutil.copytree(out, tmp, dirs_exist_ok=True)
    module.OUT = tmp
    run()
    for path in sorted(glob.glob(os.path.join(tmp, "store_*.dds"))):
        shutil.copy(path, os.path.join(out, os.path.basename(path)))
        print("  ", os.path.join(out, os.path.basename(path)))
    module.OUT = out
    shutil.rmtree(tmp)


def main():
    remake(xc_jumps, "placeables/xcJumps", xc_jumps.main)
    remake(xc_jumps, "placeables/xcJumps", xc_import.main)
    remake(show_jumps, "placeables/showJumps", show_jumps.main)

    def bleacher_run():
        random.seed(1)
        bleachers.main()
    remake(bleachers, "placeables/bleachers", bleacher_run)


if __name__ == "__main__":
    main()
