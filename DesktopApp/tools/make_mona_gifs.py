#!/usr/bin/env python3
"""Build Mona's expression GIFs from mona-loading-default.gif.

The hop is a 24×24 grid of 16×16 pixels. The white face keeps the same
shape in every frame; only its origin moves. Eyes and mouth are repainted
relative to that origin. Outline pixels are never touched.

    python3 DesktopApp/tools/make_mona_gifs.py

The Pillow wheel on this machine is x86_64, so:

    arch -x86_64 python3 DesktopApp/tools/make_mona_gifs.py
"""

import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "DesktopApp/ChaosTamagotchi/mona-loading-default.gif"
OUT_APP = ROOT / "DesktopApp/ChaosTamagotchi"
OUT_DOCS = ROOT / "docs/assets"

SCALE = 16
# Palette index 0 is GIF transparency.
PALETTE = [
    (0, 0, 0, 0),            # .
    (68, 77, 86, 255),       # # body
    (250, 251, 252, 255),    # O face
    (176, 214, 232, 255),    # S sweat / tear
    (204, 68, 76, 255),      # R anger / heart
    (240, 168, 176, 255),    # B blush
]
CHAR = {".": 0, "#": 1, "O": 2, "S": 3, "R": 4, "B": 5}
BODY, FACE = "#", "O"

# Interior features, relative to the white face's top-left.
# Eyes are a vertical pair. The mouth is a 3-wide bar; squash frames add a second row.
EYES = [(2, 2), (2, 3), (8, 2), (8, 3)]
MOUTH = [(4, 4), (5, 4), (6, 4), (5, 5), (6, 5)]


def load_base():
    im = Image.open(SOURCE)
    frames = []
    for i in range(im.n_frames):
        im.seek(i)
        rgba = im.convert("RGBA")
        px = rgba.load()
        grid = []
        for gy in range(24):
            row = []
            for gx in range(24):
                c = px[gx * SCALE + SCALE // 2, gy * SCALE + SCALE // 2]
                if c[3] < 10:
                    row.append(".")
                elif c[:3] == (68, 77, 86):
                    row.append("#")
                elif c[:3] == (250, 251, 252):
                    row.append("O")
                else:
                    raise SystemExit(f"unexpected color {c} at {gx},{gy} frame {i}")
            grid.append(row)
        frames.append(grid)
    return frames


def clone(grid):
    return [row[:] for row in grid]


def origin(grid):
    cells = [(x, y) for y in range(24) for x in range(24) if grid[y][x] == FACE]
    return min(x for x, _ in cells), min(y for _, y in cells)


def clear(grid, ox, oy, rels):
    for dx, dy in rels:
        x, y = ox + dx, oy + dy
        if grid[y][x] == BODY:
            grid[y][x] = FACE


def paint(grid, ox, oy, rels, ch):
    """Paint only white face cells so the dark outline stays intact."""
    for dx, dy in rels:
        x, y = ox + dx, oy + dy
        if 0 <= x < 24 and 0 <= y < 24 and grid[y][x] == FACE:
            grid[y][x] = ch


def paint_empty(grid, points, ch):
    for x, y in points:
        if 0 <= x < 24 and 0 <= y < 24 and grid[y][x] == ".":
            grid[y][x] = ch


def outline_sig(grid, ox, oy):
    features = {(ox + dx, oy + dy) for dx, dy in EYES + MOUTH}
    return [(x, y) for y in range(24) for x in range(24)
            if grid[y][x] == BODY and (x, y) not in features]


def face(grid, eyes, mouth, extra=(), extra_ch="#"):
    """Return a copy with eyes and mouth replaced. `eyes`/`mouth` are relative."""
    out = clone(grid)
    ox, oy = origin(out)
    sig = outline_sig(out, ox, oy)
    clear(out, ox, oy, EYES + MOUTH)
    paint(out, ox, oy, eyes, "#")
    paint(out, ox, oy, mouth, "#")
    paint(out, ox, oy, extra, extra_ch)
    for x, y in sig:
        if out[y][x] != BODY:
            raise SystemExit(f"outline broken at {x},{y}")
    return out


def normal_eyes():
    return list(EYES)


def closed_eyes():
    # Three-pixel lid across each eye.
    return [(1, 3), (2, 3), (3, 3), (7, 3), (8, 3), (9, 3)]


def half_eyes():
    return [(2, 3), (8, 3)]


def neutral_mouth():
    return [(4, 4), (5, 4), (6, 4)]


def open_mouth():
    return [(4, 4), (5, 4), (6, 4), (4, 5), (6, 5), (4, 6), (5, 6), (6, 6)]


def smile():
    # Corners sit above the center (∪).
    return [(3, 4), (7, 4), (4, 5), (5, 5), (6, 5)]


def frown():
    # Center sits above the corners (∩).
    return [(4, 4), (5, 4), (6, 4), (3, 5), (7, 5)]


def glare():
    return closed_eyes()


def angry_brows():
    return [(2, 1), (3, 1), (7, 1), (8, 1)]


def worried_brows():
    return [(1, 1), (2, 1), (8, 1), (9, 1)]


def wide_eyes():
    return [(2, 2), (3, 2), (2, 3), (3, 3), (8, 2), (9, 2), (8, 3), (9, 3)]


def happy_eyes():
    # ^ ^  — point on the upper row, feet on the lower row.
    return [(2, 2), (1, 3), (3, 3), (8, 2), (7, 3), (9, 3)]


def sad_eyes():
    return [(2, 3), (3, 3), (7, 3), (8, 3)]


def cross_eyes():
    # X X across the brow row, the eye row, and the lid row.
    return [(1, 1), (3, 1), (2, 2), (1, 3), (3, 3),
            (7, 1), (9, 1), (8, 2), (7, 3), (9, 3)]


def star_eyes():
    # Plus-shaped pupils.
    return [(2, 2), (1, 3), (2, 3), (3, 3), (8, 2), (7, 3), (8, 3), (9, 3)]


def fang():
    # Open mouth. (5, 5) stays white, so one tooth shows.
    return [(4, 4), (5, 4), (6, 4), (4, 5), (6, 5), (4, 6), (5, 6), (6, 6)]


def grin():
    return [(3, 4), (7, 4), (4, 5), (6, 5), (4, 6), (5, 6), (6, 6)]


def little_o():
    return [(5, 4), (4, 5), (6, 5), (5, 6)]


def glance(side):
    if side < 0:
        return [(1, 2), (1, 3), (7, 2), (7, 3)]
    if side > 0:
        return [(3, 2), (3, 3), (9, 2), (9, 3)]
    return normal_eyes()


def smirk():
    return [(5, 4), (6, 4), (7, 4), (7, 5)]


def drop(grid, step, ch):
    xs = [x for y in range(24) for x in range(24) if grid[y][x] != "."]
    ys = [y for y in range(24) for x in range(24) if grid[y][x] != "."]
    if not xs:
        return
    minx, maxx, miny = min(xs), max(xs), min(ys)
    y = miny + 2 + (step % 4)
    for x in (maxx + 1, minx - 1):
        if 0 <= x < 24 and 0 <= y < 24 and grid[y][x] == ".":
            grid[y][x] = ch
            if y + 1 < 24 and grid[y + 1][x] == ".":
                grid[y + 1][x] = ch
            return


def tear(grid, ox, oy, step):
    # Falls down the right cheek. Those cells stay white across the hop.
    y = oy + 3 + (step % 4)
    x = ox + 11
    if 0 <= x < 24 and 0 <= y < 24 and grid[y][x] == FACE:
        grid[y][x] = "S"


def sparks(grid):
    slots = []
    for y in range(1, 10):
        for x in range(24):
            if grid[y][x] != ".":
                continue
            neighbors = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx == dy == 0:
                        continue
                    yy, xx = y + dy, x + dx
                    if 0 <= xx < 24 and 0 <= yy < 24 and grid[yy][xx] == BODY:
                        neighbors += 1
            if neighbors == 1:
                slots.append((x, y))
    if not slots:
        return
    slots.sort()
    paint_empty(grid, [slots[0], slots[-1]], "R")


def heart(grid, bob):
    filled = [(x, y) for y in range(24) for x in range(24) if grid[y][x] != "."]
    if not filled:
        return
    cx = (min(x for x, _ in filled) + max(x for x, _ in filled)) // 2
    top = min(y for _, y in filled)
    y = max(0, top - 2 - (bob % 2))
    pixels = [(cx - 1, y), (cx + 1, y)]
    stem = (cx, y + 1)
    if y + 1 < top and 0 <= stem[0] < 24:
        pixels.append(stem)
    if all(0 <= px < 24 and 0 <= py < 24 and grid[py][px] == "." for px, py in pixels):
        paint_empty(grid, pixels, "R")


def blush(grid, ox, oy):
    paint(grid, ox, oy, [(3, 6), (7, 6)], "B")


def to_image(grid):
    small = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    px = small.load()
    for y in range(24):
        for x in range(24):
            px[x, y] = PALETTE[CHAR[grid[y][x]]]
    big = small.resize((384, 384), Image.Resampling.NEAREST)
    pal = []
    for r, g, b, _a in PALETTE:
        pal.extend((r, g, b))
    pal.extend([0] * (768 - len(pal)))
    out = Image.new("P", big.size)
    out.putpalette(pal)
    src = big.load()
    lut = {PALETTE[i][:3]: i for i in range(1, len(PALETTE))}
    data = []
    for y in range(big.size[1]):
        for x in range(big.size[0]):
            r, g, b, a = src[x, y]
            data.append(0 if a < 128 else lut[(r, g, b)])
    out.putdata(data)
    return out


def save_gif(name, frames, delays):
    images = [to_image(g) for g in frames]
    payload = dict(
        save_all=True,
        append_images=images[1:],
        duration=delays,
        loop=0,
        disposal=2,
        transparency=0,
        optimize=False,
    )
    images[0].save(OUT_APP / name, **payload)
    shutil.copy(OUT_APP / name, OUT_DOCS / name)


def build():
    base = load_base()
    for i in (0, 1, 2, 6):
        redrawn = face(base[i], normal_eyes(), neutral_mouth())
        if redrawn != base[i]:
            raise SystemExit(f"neutral redraw drifted on frame {i}")

    # Content: the original hop, then a blink held on the standing pose.
    content = [clone(g) for g in base]
    stand = base[0]
    content.append(face(stand, half_eyes(), neutral_mouth()))
    content.append(face(stand, closed_eyes(), neutral_mouth()))
    content.append(face(stand, half_eyes(), neutral_mouth()))
    save_gif("mona-content.gif", content, [150] * 7 + [70, 110, 70])

    # Restless: eyes dart, mouth pulls to one side.
    restless = []
    look = [-1, -1, 0, 1, 1, 0, -1]
    for g, side in zip(base, look):
        restless.append(face(g, glance(side), smirk()))
    save_gif("mona-restless.gif", restless, [130] * 7)

    # Anxious: raised brows, round eyes, little "o", dripping sweat.
    anxious = []
    for i, g in enumerate(base):
        f = face(g, wide_eyes(), little_o(), worried_brows())
        drop(f, i, "S")
        anxious.append(f)
    save_gif("mona-anxious.gif", anxious, [110] * 7)

    # Feral: glare, brows, one fang, anger sparks on alternate frames.
    feral = []
    for i, g in enumerate(base):
        f = face(g, glare(), fang(), angry_brows())
        if i % 2 == 0:
            sparks(f)
        feral.append(f)
    save_gif("mona-feral.gif", feral, [100] * 7)

    # Crimes: X eyes and star eyes trade off over a grin. Eyes are red.
    crimes = []
    for i, g in enumerate(base):
        eyes = cross_eyes() if i % 2 == 0 else star_eyes()
        f = face(g, [], grin())
        ox, oy = origin(f)
        # face() already cleared eyes; paint them red.
        paint(f, ox, oy, eyes, "R")
        crimes.append(f)
    save_gif("mona-crimes.gif", crimes, [90] * 7)

    # Happy (fed): ^_^ , blush, a bobbing heart, nom on odd frames.
    happy = []
    for i, g in enumerate(base):
        mouth = open_mouth() if i % 2 else smile()
        f = face(g, happy_eyes(), mouth)
        ox, oy = origin(f)
        blush(f, ox, oy)
        heart(f, i)
        happy.append(f)
    save_gif("mona-happy.gif", happy, [140] * 7)

    # Talk: two hops, mouth flaps, one blink on the second pass.
    talk = []
    delays = []
    for pass_i in range(2):
        for i, g in enumerate(base):
            eyes = closed_eyes() if pass_i == 1 and i in (0, 1) else normal_eyes()
            mouth = open_mouth() if (pass_i * 7 + i) % 2 else neutral_mouth()
            talk.append(face(g, eyes, mouth))
            delays.append(120)
    save_gif("mona-talk.gif", talk, delays)

    # Sad: low eyes, frown, a tear down the cheek. Wallpaper uses frame 0.
    sad = []
    for i, g in enumerate(base):
        f = face(g, sad_eyes(), frown())
        ox, oy = origin(f)
        tear(f, ox, oy, i)
        sad.append(f)
    save_gif("mona-sad.gif", sad, [160] * 7)

    shutil.copy(OUT_APP / "mona-content.gif", OUT_DOCS / "pet.gif")


if __name__ == "__main__":
    build()
    print("wrote expression gifs")
