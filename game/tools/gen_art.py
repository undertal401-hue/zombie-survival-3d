#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Deterministic, dependency-free pixel-art generator for ADR-001.

Writes palette-locked RGBA8 PNGs using ONLY the Python standard library
(zlib + struct). No Pillow, no ImageMagick. Fixed seed -> byte-identical
output on every run.

Usage:
    python3 tools/gen_art.py            # (re)generate all sprite sheets
    python3 tools/gen_art.py --check    # verify outputs only; writes nothing
"""

from __future__ import annotations

import os
import random
import struct
import sys
import zlib

# ---------------------------------------------------------------------------
# Palette (index 0 is transparent; 1..16 are the only legal opaque colors).
# ---------------------------------------------------------------------------

PALETTE = [
    (1, "OUTLINE",      "#0b0d0b"),
    (2, "SHADOW_GREEN", "#1a2117"),
    (3, "OLIVE_DARK",   "#33421f"),
    (4, "OLIVE_MID",    "#566e32"),
    (5, "OLIVE_LIGHT",  "#7f9a45"),
    (6, "OLIVE_HI",     "#a9bf5e"),
    (7, "LEATHER_DARK", "#33261a"),
    (8, "LEATHER_MID",  "#5c4330"),
    (9, "SKIN_MID",     "#8b6b45"),
    (10, "AMBER",       "#d2a867"),
    (11, "BONE",        "#efe4bd"),
    (12, "BLOOD_DARK",  "#6e1712"),
    (13, "BLOOD",       "#b52b20"),
    (14, "BLOOD_BRIGHT","#e8563c"),
    (15, "STEEL_DARK",  "#55626d"),
    (16, "STEEL_LIGHT", "#9aabb6"),
]

IDX = {name: i for i, name, _ in PALETTE}
RGBA = [(0, 0, 0, 0)]
for _i, _name, _hex in PALETTE:
    RGBA.append((int(_hex[1:3], 16), int(_hex[3:5], 16),
                 int(_hex[5:7], 16), 255))
LEGAL_RGB = {rgba[:3] for rgba in RGBA[1:]}

FRAME = 32
COLS = 8
SEED = 1337
rng = random.Random(SEED)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "assets", "art", "sprites"))

PLAYER_ANIMS = [
    "idle", "walk", "run",
    "attack_melee", "attack_pistol", "attack_shotgun", "attack_rifle",
    "reload_pistol", "reload_shotgun", "reload_rifle",
    "hurt", "death",
]
ZOMBIE_ANIMS = [
    "idle", "walk", "run", "attack", "hit", "hurt", "death", "crawl",
]


# ---------------------------------------------------------------------------
# PNG writer / reader (stdlib only).
# ---------------------------------------------------------------------------

def _chunk(tag: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + tag + data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def write_png(path: str, width: int, height: int, pixels: bytearray) -> None:
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type: None
        raw.extend(pixels[y * stride:(y + 1) * stride])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    blob = (b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", ihdr) +
            _chunk(b"IDAT", zlib.compress(bytes(raw), 9)) +
            _chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(blob)


def read_png(path: str):
    """Return (width, height, pixels) or raise ValueError on invalid PNG."""
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("bad PNG signature")
    pos = 8
    width = height = 0
    idat = bytearray()
    seen_end = False
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        crc = struct.unpack(">I", data[pos + 8 + length:pos + 12 + length])[0]
        if (zlib.crc32(tag + body) & 0xFFFFFFFF) != crc:
            raise ValueError("bad CRC in %r" % tag)
        if tag == b"IHDR":
            width, height, depth, ctype, comp, filt, inter = struct.unpack(
                ">IIBBBBB", body)
            if (depth, ctype, comp, filt, inter) != (8, 6, 0, 0, 0):
                raise ValueError("unexpected IHDR format")
        elif tag == b"IDAT":
            idat.extend(body)
        elif tag == b"IEND":
            seen_end = True
            break
        pos += 12 + length
    if not seen_end or width == 0 or height == 0:
        raise ValueError("incomplete PNG")
    raw = zlib.decompress(bytes(idat))
    stride = width * 4
    if len(raw) != height * (stride + 1):
        raise ValueError("bad raw size")
    pixels = bytearray(width * height * 4)
    for y in range(height):
        row_start = y * (stride + 1)
        if raw[row_start] != 0:
            raise ValueError("unsupported scanline filter")
        pixels[y * stride:(y + 1) * stride] = \
            raw[row_start + 1:row_start + 1 + stride]
    return width, height, pixels


# ---------------------------------------------------------------------------
# Palette-locked canvas and shape primitives.
# ---------------------------------------------------------------------------

class Canvas:
    __slots__ = ("data",)

    def __init__(self, w: int = FRAME, h: int = FRAME):
        self.data = [0] * (w * h)

    def set(self, x: int, y: int, idx: int) -> None:
        if 0 <= x < FRAME and 0 <= y < FRAME:
            self.data[y * FRAME + x] = idx

    def get(self, x: int, y: int) -> int:
        if 0 <= x < FRAME and 0 <= y < FRAME:
            return self.data[y * FRAME + x]
        return 0

    def rect(self, x0, y0, x1, y1, name) -> None:
        i = IDX[name]
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.set(x, y, i)

    def line(self, x0, y0, x1, y1, name) -> None:
        i = IDX[name]
        dx = abs(x1 - x0)
        dy = -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.set(x0, y0, i)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def pixels(self) -> bytearray:
        out = bytearray(FRAME * FRAME * 4)
        for i, idx in enumerate(self.data):
            out[i * 4:i * 4 + 4] = bytes(RGBA[idx])
        return out


def disc_mask(cx, cy, r):
    return {(x, y)
            for y in range(cy - r, cy + r + 1)
            for x in range(cx - r, cx + r + 1)
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r}


def ellipse_mask(cx, cy, rx, ry):
    return {(x, y)
            for y in range(cy - ry, cy + ry + 1)
            for x in range(cx - rx, cx + rx + 1)
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0}


def rect_mask(x0, y0, x1, y1):
    return {(x, y) for y in range(y0, y1) for x in range(x0, x1)}


def blit(c: Canvas, mask, triple, outline=True, dx=0, dy=0, inset_light=1):
    """Draw a shaded shape: 1px outline + top-left light / bottom-right shadow."""
    shifted = {(x + dx, y + dy) for (x, y) in mask}
    if outline:
        ring = set()
        for (x, y) in shifted:
            for ox in (-1, 0, 1):
                for oy in (-1, 0, 1):
                    if ox == 0 and oy == 0:
                        continue
                    nb = (x + ox, y + oy)
                    if nb not in shifted:
                        ring.add(nb)
        oi = IDX["OUTLINE"]
        for (x, y) in ring:
            c.set(x, y, oi)
    shadow, mid, light = (IDX[n] for n in triple)
    for (x, y) in shifted:
        tl = ((x - inset_light, y) not in shifted or
              (x, y - inset_light) not in shifted)
        br = ((x + 1, y) not in shifted or (x, y + 1) not in shifted)
        if tl:
            c.set(x, y, light)
        elif br:
            c.set(x, y, shadow)
        else:
            c.set(x, y, mid)


def stamp(c: Canvas, mask, name, dx=0, dy=0) -> None:
    i = IDX[name]
    for (x, y) in mask:
        c.set(x + dx, y + dy, i)


# ---------------------------------------------------------------------------
# Character triples (shadow / mid / light) — all from the canonical palette.
# ---------------------------------------------------------------------------

SKIN = ("LEATHER_MID", "SKIN_MID", "AMBER")
CLOTH = ("OLIVE_DARK", "OLIVE_MID", "OLIVE_LIGHT")
PACK = ("LEATHER_DARK", "LEATHER_MID", "SKIN_MID")
STEEL = ("STEEL_DARK", "STEEL_DARK", "STEEL_LIGHT")
BLOODY = ("BLOOD_DARK", "BLOOD", "BLOOD_BRIGHT")

ZOMBIE_TRIPLES = {
    "walker":   ("OLIVE_DARK", "OLIVE_MID", "OLIVE_LIGHT"),
    "runner":   ("BLOOD_DARK", "LEATHER_MID", "BLOOD_BRIGHT"),
    "tank":     ("SHADOW_GREEN", "STEEL_DARK", "STEEL_LIGHT"),
    "spitter":  ("OLIVE_DARK", "OLIVE_LIGHT", "OLIVE_HI"),
    "screamer": ("BLOOD_DARK", "BLOOD", "BLOOD_BRIGHT"),
}


def draw_humanoid(c: Canvas, frame: int, action: str, flesh, cloth,
                  survivor=False, kind="walker"):
    """Top-down 32x32 actor. Frame index selects a subtle pose variation."""
    bob = 0
    swing = 0
    fwd = 0
    recoil = 0
    dying = False
    crawling = False
    if action == "idle":
        bob = [0, -1, 0, 0][frame]
    elif action == "walk":
        swing = [-2, 0, 2, 0][frame]
        bob = [0, -1, 0, -1][frame]
    elif action == "run":
        swing = [-3, 0, 3, 0][frame]
        bob = [-1, -2, -1, -2][frame]
    elif action == "attack":
        fwd = [0, -2, -4, -2][frame]
        bob = [0, 0, -1, 0][frame]
    elif action in ("hit", "hurt"):
        recoil = [1, 2, 2, 1][frame]
        bob = recoil
    elif action == "death":
        dying = True
        bob = [0, 1, 2, 3][frame]
    elif action == "crawl":
        crawling = True
        bob = 3

    # Feet / legs (behind torso).
    if not dying:
        blit(c, rect_mask(11, 24 + bob, 15, 28 + bob + (swing // 2)),
             PACK, outline=True)
        blit(c, rect_mask(17, 24 + bob, 21, 28 + bob - (swing // 2)),
             PACK, outline=True)

    if dying and frame >= 2:
        # Collapsed: wide, low silhouette + blood pool.
        pool = ellipse_mask(16, 27, 11, 3)
        stamp(c, pool, "BLOOD_DARK")
        stamp(c, ellipse_mask(16, 26, 7, 2), "BLOOD")
        blit(c, ellipse_mask(15 + frame, 25, 9, 4), flesh, outline=True)
        blit(c, disc_mask(7 + frame * 2, 24, 3), flesh, outline=True)
        for (x, y) in [(9, 27), (12, 29), (21, 28), (25, 26)]:
            c.set(x, y, IDX["BLOOD_BRIGHT"])
        return

    # Backpack behind the torso (survivors carry gear).
    if survivor:
        blit(c, ellipse_mask(16, 21 + bob, 6, 5), PACK, outline=True)

    # Torso — oval with directional shading.
    torso_cy = 18 + bob + (2 if crawling else 0)
    blit(c, ellipse_mask(16, torso_cy, 7, 8 if not crawling else 6), cloth,
         outline=True)

    # Tattered clothing / blood stains for the undead.
    if not survivor:
        for (x, y) in [(12, 19 + bob), (20, 21 + bob), (16, 23 + bob)]:
            c.set(x, y, IDX["BLOOD_DARK"])
        if kind in ("runner", "screamer", "spitter"):
            for (x, y) in [(13, 17 + bob), (19, 19 + bob), (15, 22 + bob)]:
                c.set(x, y, IDX["BLOOD_BRIGHT"])

    # Head — round, with hair/helmet arc on top.
    head_cy = 10 + bob + (3 if crawling else 0)
    head_r = 4 if not dying else 3
    blit(c, disc_mask(16, head_cy, head_r), flesh, outline=True)
    # Hair / cap rim (top-left), keeps a 32px-readable silhouette.
    hair = disc_mask(16, head_cy - 1, head_r)
    stamp(c, {(x, y) for (x, y) in hair if y <= head_cy - 2},
          "LEATHER_DARK" if survivor else "SHADOW_GREEN")
    if survivor:
        c.set(15, head_cy - 3, IDX["STEEL_LIGHT"])
    # Eyes: glowing for the undead.
    if not survivor:
        c.set(14, head_cy + 1, IDX["BLOOD_BRIGHT"])
        c.set(18, head_cy + 1, IDX["BLOOD_BRIGHT"])
    else:
        c.set(14, head_cy + 1, IDX["OUTLINE"])
        c.set(18, head_cy + 1, IDX["OUTLINE"])

    # Arms / shoulders — extend sideways, swing per frame.
    arm_y = 16 + bob + fwd + (2 if crawling else 0)
    left = rect_mask(4, arm_y + swing, 12, arm_y + 4 + swing)
    right = rect_mask(20, arm_y - swing, 28, arm_y + 4 - swing)
    if dying:
        left = rect_mask(5, 18 + bob, 13, 22 + bob)
        right = rect_mask(19, 18 + bob, 27, 22 + bob)
    blit(c, left, flesh, outline=True)
    blit(c, right, flesh, outline=True)
    # Hands (skin highlight).
    stamp(c, rect_mask(4, arm_y + swing, 6, arm_y + 3 + swing),
          "SKIN_MID" if survivor else "BONE")
    stamp(c, rect_mask(26, arm_y - swing, 28, arm_y + 3 - swing),
          "SKIN_MID" if survivor else "BONE")

    # Survivor details: amber scarf, sidearm, straps.
    if survivor:
        c.rect(13, 14 + bob, 19, 15 + bob, "AMBER")
        c.set(16, 15 + bob, IDX["BLOOD_DARK"])
        blit(c, rect_mask(24, arm_y - swing - 7 + fwd,
                          27, arm_y - swing + 1 + fwd), STEEL, outline=True)
        c.set(25, arm_y - swing - 5 + fwd, IDX["BONE"])  # muzzle glint
        # Backpack straps.
        c.set(13, 18 + bob, IDX["LEATHER_DARK"])
        c.set(19, 18 + bob, IDX["LEATHER_DARK"])
    else:
        # Undead details: one arm reaching forward, bite marks, spit/scream.
        if action in ("attack", "crawl"):
            blit(c, rect_mask(14, 5 + bob, 18, 11 + bob), flesh, outline=True)
            stamp(c, rect_mask(15, 4 + bob, 17, 6 + bob), "BLOOD")
        if kind == "spitter":
            stamp(c, disc_mask(16, 6 + bob, 2), "OLIVE_HI")
            c.set(16, 3 + bob, IDX["OLIVE_HI"])
        if kind == "screamer":
            c.line(16, 6 + bob, 12, 2 + bob, "BLOOD_BRIGHT")
            c.line(16, 6 + bob, 20, 2 + bob, "BLOOD_BRIGHT")
            c.line(16, 6 + bob, 16, 1 + bob, "BLOOD_BRIGHT")
        if kind == "tank":
            # Armoured plates on the shoulders.
            c.rect(6, arm_y - 1 + swing, 11, arm_y + 2 + swing, "STEEL_LIGHT")
            c.rect(21, arm_y - 1 - swing, 26, arm_y + 2 - swing, "STEEL_LIGHT")

    # Hit feedback: red speckles, deterministic positions.
    if action in ("hit", "hurt"):
        for (x, y) in [(10, 12 + bob), (22, 14 + bob), (17, 8 + bob)]:
            c.set(x, y, IDX["BLOOD_BRIGHT"])
        for (x, y) in [(7, 18 + bob), (25, 20 + bob)]:
            c.set(x, y, IDX["BLOOD"])


# ---------------------------------------------------------------------------
# Effects and tile sheets.
# ---------------------------------------------------------------------------

def draw_effect(c: Canvas, frame: int) -> None:
    kind = frame % 8
    if kind == 0:  # blood splatter
        stamp(c, disc_mask(16, 16, 6), "BLOOD_DARK")
        stamp(c, disc_mask(14, 14, 3), "BLOOD")
        for (x, y) in [(6, 10), (24, 9), (9, 25), (23, 24), (4, 18), (27, 17)]:
            stamp(c, disc_mask(x, y, 1), "BLOOD_BRIGHT")
    elif kind == 1:  # muzzle flash
        c.line(16, 4, 16, 28, "BLOOD_BRIGHT")
        c.line(4, 16, 28, 16, "BLOOD_BRIGHT")
        c.line(8, 8, 24, 24, "AMBER")
        c.line(8, 24, 24, 8, "AMBER")
        stamp(c, disc_mask(16, 16, 4), "BONE")
    elif kind == 2:  # bullet impact sparks
        stamp(c, disc_mask(16, 16, 3), "BONE")
        for (x, y) in [(16, 5), (16, 27), (5, 16), (27, 16),
                       (9, 9), (23, 23), (23, 9), (9, 23)]:
            c.set(x, y, IDX["AMBER"])
    elif kind == 3:  # dust puff
        for (x, y, r) in [(12, 18, 4), (19, 17, 5), (16, 22, 3)]:
            stamp(c, disc_mask(x, y, r), "STEEL_DARK")
            stamp(c, disc_mask(x - 1, y - 1, r - 2), "STEEL_LIGHT")
    elif kind == 4:  # blood drip
        c.rect(15, 6, 18, 16, "BLOOD_DARK")
        c.rect(16, 8, 17, 15, "BLOOD")
        stamp(c, ellipse_mask(16, 24, 4, 5), "BLOOD")
        c.set(15, 27, IDX["BLOOD_BRIGHT"])
    elif kind == 5:  # small explosion
        stamp(c, disc_mask(16, 16, 9), "BLOOD_DARK")
        stamp(c, disc_mask(16, 16, 6), "BLOOD")
        stamp(c, disc_mask(16, 16, 3), "BLOOD_BRIGHT")
        stamp(c, disc_mask(16, 16, 1), "BONE")
    elif kind == 6:  # acid spit
        stamp(c, disc_mask(16, 16, 5), "OLIVE_HI")
        for (x, y) in [(16, 6), (10, 20), (22, 20), (7, 12), (25, 12)]:
            stamp(c, disc_mask(x, y, 1), "OLIVE_LIGHT")
    else:  # scream wave
        for r in (4, 8, 12):
            ring = {(x, y) for (x, y) in disc_mask(16, 16, r)
                    if r - 1 <= ((x - 16) ** 2 + (y - 16) ** 2) ** 0.5 <= r}
            stamp(c, ring, "BLOOD_BRIGHT" if r == 4 else "BLOOD")
        stamp(c, disc_mask(16, 16, 2), "BONE")


def draw_tile(c: Canvas, frame: int) -> None:
    kind = frame % 8
    if kind == 0:  # grass floor
        c.rect(0, 0, 32, 32, "OLIVE_DARK")
        c.rect(2, 2, 30, 30, "OLIVE_MID")
        for (x, y) in [(5, 6), (12, 9), (21, 5), (26, 13), (8, 20),
                       (17, 24), (25, 27), (4, 28)]:
            c.set(x, y, IDX["OLIVE_LIGHT"])
            c.set(x + 1, y, IDX["OLIVE_HI"])
    elif kind == 1:  # concrete floor
        c.rect(0, 0, 32, 32, "STEEL_DARK")
        c.rect(2, 2, 30, 30, "OLIVE_DARK")
        c.line(2, 16, 30, 16, "STEEL_DARK")
        c.line(16, 2, 16, 30, "STEEL_DARK")
        for (x, y) in [(6, 7), (24, 22), (10, 26)]:
            c.set(x, y, IDX["STEEL_LIGHT"])
    elif kind == 2:  # wall block
        c.rect(0, 0, 32, 32, "OUTLINE")
        c.rect(1, 1, 31, 31, "STEEL_DARK")
        c.rect(3, 3, 29, 29, "STEEL_LIGHT")
        for y in range(6, 29, 8):
            c.line(3, y, 29, y, "STEEL_DARK")
        c.line(16, 3, 16, 29, "STEEL_DARK")
    elif kind == 3:  # dirt with pebbles
        c.rect(0, 0, 32, 32, "LEATHER_DARK")
        c.rect(2, 2, 30, 30, "LEATHER_MID")
        for (x, y) in [(7, 9), (15, 6), (24, 11), (10, 21), (20, 25), (27, 19)]:
            c.set(x, y, IDX["SKIN_MID"])
            c.set(x + 1, y, IDX["AMBER"])
    elif kind == 4:  # blood-stained floor
        c.rect(0, 0, 32, 32, "STEEL_DARK")
        c.rect(2, 2, 30, 30, "OLIVE_DARK")
        stamp(c, ellipse_mask(16, 16, 9, 7), "BLOOD_DARK")
        stamp(c, ellipse_mask(14, 14, 5, 4), "BLOOD")
        c.set(19, 18, IDX["BLOOD_BRIGHT"])
        c.set(8, 22, IDX["BLOOD"])
    elif kind == 5:  # wooden plank
        c.rect(0, 0, 32, 32, "LEATHER_DARK")
        for x in range(2, 30, 6):
            c.rect(x, 2, x + 5, 30, "LEATHER_MID")
            c.line(x + 5, 2, x + 5, 30, "LEATHER_DARK")
            c.set(x + 2, 6, IDX["SKIN_MID"])
            c.set(x + 3, 20, IDX["SKIN_MID"])
    elif kind == 6:  # rubble
        c.rect(0, 0, 32, 32, "SHADOW_GREEN")
        blit(c, rect_mask(4, 8, 14, 20), ("STEEL_DARK", "STEEL_DARK", "STEEL_LIGHT"))
        blit(c, rect_mask(18, 14, 28, 26), ("OLIVE_DARK", "OLIVE_MID", "OLIVE_LIGHT"))
        blit(c, rect_mask(13, 4, 20, 12), ("LEATHER_DARK", "LEATHER_MID", "SKIN_MID"))
    else:  # gravel path
        c.rect(0, 0, 32, 32, "OLIVE_DARK")
        for (x, y) in [(4, 5), (11, 8), (19, 4), (26, 9), (7, 15),
                       (15, 17), (24, 19), (5, 25), (13, 27), (22, 26)]:
            c.set(x, y, IDX["STEEL_DARK"])
            c.set(x + 1, y, IDX["STEEL_LIGHT"])


# ---------------------------------------------------------------------------
# Sheet assembly.
# ---------------------------------------------------------------------------

def assemble(frames):
    rows = (len(frames) + COLS - 1) // COLS
    w, h = COLS * FRAME, rows * FRAME
    sheet = bytearray(w * h * 4)
    for i, frame in enumerate(frames):
        col, row = i % COLS, i // COLS
        fp = frame.pixels()
        for y in range(FRAME):
            dest = ((row * FRAME + y) * w + col * FRAME) * 4
            sheet[dest:dest + FRAME * 4] = fp[y * FRAME * 4:(y + 1) * FRAME * 4]
    return w, h, sheet


def make_actor_sheet(anims, draw_fn):
    frames = []
    for anim in anims:
        for f in range(4):
            c = Canvas()
            draw_fn(c, f, anim)
            frames.append(c)
    return assemble(frames)


def build_all():
    outputs = {}

    outputs["player_sheet.png"] = make_actor_sheet(
        PLAYER_ANIMS,
        lambda c, f, a: draw_humanoid(c, f, a, SKIN, CLOTH, survivor=True),
    )

    def zombie_draw(kind):
        return lambda c, f, a: draw_humanoid(
            c, f, a, ZOMBIE_TRIPLES[kind], ZOMBIE_TRIPLES[kind],
            survivor=False, kind=kind)

    for kind in ("walker", "runner", "tank", "spitter", "screamer"):
        outputs["zombie_%s.png" % kind] = make_actor_sheet(
            ZOMBIE_ANIMS, zombie_draw(kind))

    effect_frames = []
    for f in range(8):
        c = Canvas()
        draw_effect(c, f)
        effect_frames.append(c)
    outputs["effects.png"] = assemble(effect_frames)

    tile_frames = []
    for f in range(8):
        c = Canvas()
        draw_tile(c, f)
        tile_frames.append(c)
    outputs["tiles.png"] = assemble(tile_frames)

    return outputs


# ---------------------------------------------------------------------------
# CLI.
# ---------------------------------------------------------------------------

def do_check() -> int:
    expected = [name for name in (
        "player_sheet.png",
        "zombie_walker.png", "zombie_runner.png", "zombie_tank.png",
        "zombie_spitter.png", "zombie_screamer.png",
        "effects.png", "tiles.png",
    )]
    ok = True
    for name in expected:
        path = os.path.join(OUT_DIR, name)
        if not os.path.isfile(path):
            print("MISSING %s" % name)
            ok = False
            continue
        try:
            w, h, px = read_png(path)
        except Exception as exc:  # noqa: BLE001
            print("INVALID %s: %s" % (name, exc))
            ok = False
            continue
        problems = []
        if w % FRAME or h % FRAME or w == 0 or h == 0:
            problems.append("dimensions %dx%d not multiple of %d" % (w, h, FRAME))
        for i in range(0, len(px), 4):
            r, g, b, a = px[i], px[i + 1], px[i + 2], px[i + 3]
            if a == 0:
                continue
            if a != 255 or (r, g, b) not in LEGAL_RGB:
                problems.append("out-of-palette pixel at %d: %s"
                                % (i // 4, (r, g, b, a)))
                break
        if problems:
            print("INVALID %s: %s" % (name, "; ".join(problems)))
            ok = False
        else:
            print("OK      %s (%dx%d)" % (name, w, h))
    if ok:
        print("CHECK OK: %d sheets, palette-locked" % len(expected))
        return 0
    print("CHECK FAILED")
    return 1


def do_generate() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    outputs = build_all()
    for name in sorted(outputs):
        w, h, px = outputs[name]
        path = os.path.join(OUT_DIR, name)
        write_png(path, w, h, px)
        print("WROTE   %s (%dx%d, %d bytes)" % (name, w, h, os.path.getsize(path)))
    return 0


def main() -> int:
    if "--check" in sys.argv[1:]:
        return do_check()
    return do_generate()


if __name__ == "__main__":
    sys.exit(main())
