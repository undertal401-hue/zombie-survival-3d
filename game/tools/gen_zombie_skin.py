#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generador del skin de zombi de rango bajo (ADR-005).

Produce el pack que consume el runtime:

    assets/enemies/zombie/<anim>/<anim>_NN.png   frames sueltos (64x64)
    assets/enemies/zombie/<anim>_strip.png        strip horizontal uniforme

CONTRATO (ficha del pack de arte del autor):
  - Celda de 64x64 px, PPU 64, pivot centro (0.5, 0.5).
  - Animaciones y numero de frames:
        idle 2, walk 5, walk_alt 3, attack 6,
        attack_alt 2, rise 5, death 6, special 4
  - Strips horizontales listos para AnimationPlayer: celda N en x = N*64.

Los pixeles salen del generador canonico del repo (ADR-001): misma paleta de
16 colores, mismo humanoid, misma semilla. Cada frame se renderiza a 32x32
(px logico) y se escala x2 a la celda de 64x64, de modo que el PPU del pack
(64) es exactamente el doble del PPU nativo del proyecto (32) y en pantalla
sale nitido a escala 0.5.

ANCLAJE: se calcula el bbox opaco de la UNION de todos los frames del pack
(todas las animaciones), se centra esa caja en la celda 64x64 y se aplica la
MISMA traslacion a todos los frames. Nunca se reencuadra un frame contra su
propio bbox. Asi el personaje no patina entre frames ni entre animaciones, y
el origen del nodo (centro de la celda) es el pivot declarado.

Uso:
    python3 tools/gen_zombie_skin.py           # genera el pack
    python3 tools/gen_zombie_skin.py --check   # verifica (gate de CI)
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gen_art import Canvas, draw_humanoid, RGBA, ZOMBIE_TRIPLES  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(
    os.path.join(HERE, "..", "assets", "enemies", "zombie"))

# ---------------------------------------------------------------------------
# Contrato del skin
# ---------------------------------------------------------------------------

CELL = 64          # celda del pack (px) -> PPU 64
LOGICAL = 32       # px logicos (retícula nativa del proyecto)
SCALE = CELL // LOGICAL
CRAWL_STAGE_H = LOGICAL + 1  # staging extra para que el bob +1 no recorte pies
CRAWL_BOB = (0, -1, 0, 1, 0)
CRAWL_CROP_BOTTOM = 3         # patas traseras: arrastre mas bajo que `walk`

# Tabla del skin: nombre del pack -> (accion canonica, secuencia de poses,
# fps, bucle). Las poses son indices de la animacion canonica de 4 frames
# (`draw_humanoid`), encadenados para dar el numero de frames del pack.
SKIN_ANIMS = {
    # 2 frames: respiracion sutil.
    "idle": ("idle", (0, 1), 4.0, True),
    # 5 frames: ciclo de caminata (izq, paso, der, paso, paso).
    "walk": ("walk", (0, 1, 2, 3, 1), 8.0, True),
    # 3 frames: zancada rapida (usada como `run`).
    "walk_alt": ("run", (0, 1, 2), 12.0, True),
    # 6 frames: carga, media, golpe, golpe, media, vuelta.
    "attack": ("attack", (0, 1, 2, 2, 1, 0), 12.0, False),
    # 2 frames: golpe alterno rapido (usada como `hit`).
    "attack_alt": ("hit", (2, 3), 10.0, False),
    # 5 frames: arrastre continuo en el suelo (runtime: `crawl`).
    # La pose canonica es fija; el subtlety la aporta el bob CRAWL_BOB.
    # El bucle es TRUE: `crawl` se reproduce en bucle mientras al zombi le
    # fallan las piernas, asi que el clip debe ciclar (igual que en
    # ZombieVisual.SKIN_ANIMATIONS).
    "rise": ("crawl", (0, 0, 0, 0, 0), 8.0, True),
    # 6 frames: de pie, tropiezo, cae, en el suelo.
    "death": ("death", (0, 0, 1, 2, 3, 3), 7.0, False),
    # 4 frames: sacudida de impacto (usada como `hurt`).
    "special": ("hurt", (0, 1, 2, 3), 10.0, False),
}

# Mapa pack -> nombres canonicos que usa el runtime (ZombieVisual).
CANONICAL_MAP = {
    "idle": "idle",
    "walk": "walk",
    "walk_alt": "run",
    "attack": "attack",
    "attack_alt": "hit",
    "rise": "crawl",
    "death": "death",
    "special": "hurt",
}

# Par de color del zombi: mismo triple que `zombie_walker.png`.
TRIPLE = ZOMBIE_TRIPLES["walker"]


# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------

def render_logical(action: str, pose: int, frame_index: int, count: int):
    """Renderiza un frame logico -> (w, h, RGBA bytes).

    El arrastre usa la pose canonica `crawl`, fija y baja. Para evitar que el
    bob hacia abajo recorte la ultima fila logica, el clip se renderiza en un
    staging de 33 px de alto; el recorte final a 64x64 ocurre tras calcular el
    ancla global de todo el pack.
    """
    c = Canvas()
    if action == "crawl":
        draw_humanoid(c, 0, "crawl", TRIPLE, TRIPLE,
                      survivor=False, kind="walker")
        bob = CRAWL_BOB[frame_index % len(CRAWL_BOB)]
        src = c.data
        out = [0] * (LOGICAL * CRAWL_STAGE_H)
        for y in range(LOGICAL):
            for x in range(LOGICAL):
                value = src[y * LOGICAL + x]
                ny = y + bob
                if (value and 0 <= ny < CRAWL_STAGE_H and
                        ny < LOGICAL - CRAWL_CROP_BOTTOM):
                    out[ny * LOGICAL + x] = value
        rgba = bytearray(LOGICAL * CRAWL_STAGE_H * 4)
        for i, value in enumerate(out):
            rgba[i * 4:i * 4 + 4] = bytes(RGBA[value])
        return LOGICAL, CRAWL_STAGE_H, bytes(rgba)

    draw_humanoid(c, pose % 4, action, TRIPLE, TRIPLE,
                  survivor=False, kind="walker")

    # El humanoide caido del generador canonico queda 1 px logico a la derecha
    # en las poses finales de `death`. Se corrige ANTES del anclaje global para
    # que el bbox de cada frame quede centrado en su celda sin alterar el
    # movimiento vertical de la animacion.
    if action == "death":
        bbox = bbox_of(LOGICAL, LOGICAL, c.pixels())
        if bbox is not None:
            shift = (LOGICAL - (bbox[0] + bbox[2])) // 2
            if shift:
                src = c.data
                out = [0] * (LOGICAL * LOGICAL)
                for y in range(LOGICAL):
                    for x in range(LOGICAL):
                        value = src[y * LOGICAL + x]
                        if value and 0 <= x + shift < LOGICAL:
                            out[y * LOGICAL + x + shift] = value
                c.data = out
    return LOGICAL, LOGICAL, c.pixels()


def upscale(w: int, h: int, rgba: bytes, factor: int = SCALE):
    """Escala xN con vecino mas proximo (px logico -> px de la celda)."""
    out = bytearray(w * factor * h * factor * 4)
    ow = w * factor
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            r, g, b, a = rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]
            if a == 0:
                continue
            for dy in range(factor):
                row = (y * factor + dy) * ow
                for dx in range(factor):
                    j = (row + x * factor + dx) * 4
                    out[j] = r
                    out[j + 1] = g
                    out[j + 2] = b
                    out[j + 3] = a
    return ow, h * factor, bytes(out)


def bbox_of(w: int, h: int, rgba: bytes):
    """bbox opaco (l, t, r, b) o None."""
    l, t, r, b = w, h, 0, 0
    found = False
    for y in range(h):
        row = y * w * 4
        for x in range(w):
            if rgba[row + x * 4 + 3] == 0:
                continue
            found = True
            if x < l:
                l = x
            if x + 1 > r:
                r = x + 1
            if y < t:
                t = y
            if y + 1 > b:
                b = y + 1
    return (l, t, r, b) if found else None


def build_frames():
    """Renderiza todos los frames del pack -> {ruta_rel: (w, h, rgba)}."""
    rendered = []
    for anim in sorted(SKIN_ANIMS):
        action, poses, _fps, _loop = SKIN_ANIMS[anim]
        for idx, pose in enumerate(poses):
            w, h, rgba = render_logical(action, pose, idx, len(poses))
            rendered.append((anim, idx, upscale(w, h, rgba)))
    # Caja UNICA de todo el personaje: ancla comun de todos los frames.
    union = None
    for _anim, _idx, (w, h, rgba) in rendered:
        bb = bbox_of(w, h, rgba)
        if bb is None:
            continue
        if union is None:
            union = list(bb)
        else:
            union[0] = min(union[0], bb[0])
            union[1] = min(union[1], bb[1])
            union[2] = max(union[2], bb[2])
            union[3] = max(union[3], bb[3])
    if union is None:
        raise RuntimeError("el skin renderizado esta completamente vacio")
    uw = union[2] - union[0]
    uh = union[3] - union[1]
    if uw > CELL or uh > CELL:
        raise RuntimeError(
            "la caja del personaje (%dx%d) no cabe en la celda de %d" %
            (uw, uh, CELL))

    # Ancla CENTRO de la caja comun. La misma traslacion se aplica a todos los
    # frames: nunca se reencuadra un frame contra su propio bbox, por lo que el
    # personaje no patina entre frames ni entre animaciones.
    ox = (CELL - uw) // 2 - union[0]
    oy = (CELL - uh) // 2 - union[1]
    out = {}
    for anim, idx, (w, h, rgba) in rendered:
        cell = bytearray(CELL * CELL * 4)
        for y in range(h):
            for x in range(w):
                i = (y * w + x) * 4
                if rgba[i + 3] == 0:
                    continue
                dx, dy = x + ox, y + oy
                if not (0 <= dx < CELL and 0 <= dy < CELL):
                    continue
                j = (dy * CELL + dx) * 4
                cell[j] = rgba[i]
                cell[j + 1] = rgba[i + 1]
                cell[j + 2] = rgba[i + 2]
                cell[j + 3] = rgba[i + 3]
        out["%s/%s_%02d.png" % (anim, anim, idx + 1)] = (CELL, CELL, bytes(cell))
    return out


def build_strips(frames):
    """Strip horizontal por animacion: celda N en x = N*64."""
    strips = {}
    for anim in sorted(SKIN_ANIMS):
        names = sorted(k for k in frames if k.startswith(anim + "/"))
        if not names:
            continue
        width = CELL * len(names)
        strip = bytearray(width * CELL * 4)
        for idx, name in enumerate(names):
            _w, _h, rgba = frames[name]
            for row in range(CELL):
                src = row * CELL * 4
                dst = (row * width + idx * CELL) * 4
                strip[dst:dst + CELL * 4] = rgba[src:src + CELL * 4]
        strips["%s_strip.png" % anim] = (width, CELL, bytes(strip))
    return strips


def outputs():
    frames = build_frames()
    strips = build_strips(frames)
    return frames, strips


def do_build() -> int:
    from gen_art import write_png
    frames, strips = outputs()
    for rel, (w, h, rgba) in sorted(frames.items()):
        path = os.path.join(OUT_DIR, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        write_png(path, w, h, bytearray(rgba))
    for name, (w, h, rgba) in sorted(strips.items()):
        path = os.path.join(OUT_DIR, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        write_png(path, w, h, bytearray(rgba))
    print("SKIN_GENERATED frames=%d strips=%d -> %s" % (
        len(frames), len(strips), OUT_DIR))
    return 0


def do_check() -> int:
    """Puerta de CI: compara con disco y valida el contrato completo."""
    from skin_pack import LEGAL_CANONICAL, pixel_stats, png_bytes, read_png

    frames, strips = outputs()
    bad = 0
    expected_frames = set(frames)
    expected_strips = set(strips)
    expected_pngs = expected_frames | expected_strips

    actual_pngs = set()
    for dirpath, _dirs, files in os.walk(OUT_DIR):
        for name in files:
            if name.endswith(".png"):
                rel = os.path.relpath(os.path.join(dirpath, name), OUT_DIR)
                actual_pngs.add(rel.replace(os.sep, "/"))

    for rel in sorted(actual_pngs - expected_pngs):
        print("FAIL PNG sobrante: %s" % rel)
        bad += 1
    for rel in sorted(expected_pngs - actual_pngs):
        print("FAIL falta PNG: %s" % rel)
        bad += 1

    disk_frames = {}
    for rel, (w, h, rgba) in sorted(frames.items()):
        path = os.path.join(OUT_DIR, rel)
        if not os.path.exists(path):
            continue
        try:
            with open(path, "rb") as f:
                actual_blob = f.read()
        except OSError as exc:
            print("FAIL no se puede leer %s (%s)" % (rel, exc))
            bad += 1
            continue
        expected_blob = png_bytes(w, h, rgba)
        if actual_blob != expected_blob:
            try:
                fw, fh, fp = read_png(path)
            except (OSError, ValueError) as exc:
                print("FAIL PNG invalido %s (%s)" % (rel, exc))
                bad += 1
                continue
            if (fw, fh) != (w, h):
                print("FAIL tamano %s: %dx%d (esperado %dx%d)" %
                      (rel, fw, fh, w, h))
                bad += 1
            elif bytes(fp) != rgba:
                print("FAIL pixeles %s" % rel)
                bad += 1
            else:
                print("FAIL bytes PNG no canonicos %s" % rel)
                bad += 1

        try:
            fw, fh, fp = read_png(path)
        except (OSError, ValueError) as exc:
            print("FAIL PNG invalido %s (%s)" % (rel, exc))
            bad += 1
            continue
        if (fw, fh) != (CELL, CELL):
            print("FAIL frame fuera de celda %s: %dx%d" % (rel, fw, fh))
            bad += 1
            continue
        opaque, bbox, colors = pixel_stats(fw, fh, fp)
        if bbox is None:
            print("FAIL frame vacio %s" % rel)
            bad += 1
            continue
        center_x = (bbox[0] + bbox[2]) / 2.0
        if abs(center_x - CELL / 2.0) > 1.0:
            print("FAIL frame descentrado %s: centro_x=%.1f" %
                  (rel, center_x))
            bad += 1
        if CELL - bbox[3] < 2:
            print("FAIL frame sin margen inferior %s" % rel)
            bad += 1
        if len(colors) < 4:
            print("FAIL frame con menos de 4 colores %s" % rel)
            bad += 1
        illegal = sorted(color for color in colors
                         if color not in LEGAL_CANONICAL)
        if illegal:
            print("FAIL paleta no canonica %s (%d colores)" %
                  (rel, len(illegal)))
            bad += 1
        disk_frames[rel] = bbox

    for anim, count in sorted(
            (anim, len(poses)) for anim, (_a, poses, _f, _l)
            in SKIN_ANIMS.items()):
        found = sum(1 for rel in disk_frames if rel.startswith(anim + "/"))
        if found != count:
            print("FAIL numero de frames %s: %d (esperado %d)" %
                  (anim, found, count))
            bad += 1

    # Semantica del arrastre: todos los frames de `rise` son mas bajos que
    # todos los frames de `walk` y se mantienen en la mitad baja del pack.
    walk_heights = [
        bbox[3] - bbox[1] for rel, bbox in disk_frames.items()
        if rel.startswith("walk/")
    ]
    rise_boxes = [
        bbox for rel, bbox in disk_frames.items() if rel.startswith("rise/")
    ]
    if walk_heights and rise_boxes:
        min_walk_height = min(walk_heights)
        for rel, bbox in sorted(disk_frames.items()):
            if not rel.startswith("rise/"):
                continue
            if bbox[3] - bbox[1] >= min_walk_height:
                print("FAIL rise no mas bajo que walk %s" % rel)
                bad += 1
            if (bbox[1] + bbox[3]) / 2.0 < CELL / 2.0:
                print("FAIL rise fuera de la parte inferior %s" % rel)
                bad += 1

    if disk_frames:
        boxes = list(disk_frames.values())
        union = (
            min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes),
        )
        center_x = (union[0] + union[2]) / 2.0
        center_y = (union[1] + union[3]) / 2.0
        if abs(center_x - CELL / 2.0) > 1.0 or \
                abs(center_y - CELL / 2.0) > 1.0:
            print("FAIL union global descentrada: centro=(%.1f, %.1f)" %
                  (center_x, center_y))
            bad += 1

    for name, (w, h, rgba) in sorted(strips.items()):
        path = os.path.join(OUT_DIR, name)
        if not os.path.exists(path):
            continue
        try:
            with open(path, "rb") as f:
                actual_blob = f.read()
        except OSError as exc:
            print("FAIL no se puede leer %s (%s)" % (name, exc))
            bad += 1
            continue
        expected_blob = png_bytes(w, h, rgba)
        if actual_blob != expected_blob:
            try:
                sw, sh, sp = read_png(path)
            except (OSError, ValueError) as exc:
                print("FAIL PNG invalido %s (%s)" % (name, exc))
                bad += 1
                continue
            if (sw, sh) != (w, h):
                print("FAIL tamano %s: %dx%d (esperado %dx%d)" %
                      (name, sw, sh, w, h))
                bad += 1
            elif bytes(sp) != rgba:
                print("FAIL pixeles %s" % name)
                bad += 1
            else:
                print("FAIL bytes PNG no canonicos %s" % name)
                bad += 1
        try:
            sw, sh, _sp = read_png(path)
        except (OSError, ValueError) as exc:
            print("FAIL PNG invalido %s (%s)" % (name, exc))
            bad += 1
            continue
        if sh != CELL or sw % CELL != 0:
            print("FAIL strip no rebanable %s: %dx%d" % (name, sw, sh))
            bad += 1

    print("ZOMBIE_SKIN_CHECK failures=%d frames=%d strips=%d" % (
        bad, len(frames), len(strips)))
    return 1 if bad else 0


def main(argv) -> int:
    if len(argv) > 1 and argv[1] == "--check":
        return do_check()
    return do_build()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
