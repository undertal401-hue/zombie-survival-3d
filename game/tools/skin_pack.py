#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Auditoria y normalizacion de packs de sprites de actor (skins).

Tool de la "piel" de zombis de rango bajo (ADR-005). El pack canonico vive
en `assets/enemies/zombie/`:

    assets/enemies/zombie/<anim>/<anim>_NN.png   frames sueltos (fuente)
    assets/enemies/zombie/<anim>_strip.png        strip horizontal uniforme

El strip es lo que consume el runtime (Sprite2D + region_rect +
AnimationPlayer): celdas de `CELL x CELL` px, celda N en `x = N*CELL`.
Un strip con celdas de ANCHO VARIABLE no es rebanable y rompe la
animacion, asi que la normalizacion es obligatoria, no opcional.

Subcomandos:
    audit <dir>                         Diagnostica un pack externo.
    import <dir> --out <destino>       Normaliza un pack externo.
    build                               Regenera los strips del proyecto.
    check                               Verifica el pack del proyecto (CI).

Regla de anclaje del proyecto: el bbox opaco de la UNION de todos los frames
se centra en la celda 64x64 y se aplica la MISMA traslacion a todos los frames.
Nunca se reencuadra un frame usando el bbox de su propio frame; asi el
personaje no patina entre frames ni entre animaciones.

Solo stdlib (zlib + struct), igual que `tools/gen_art.py`.
"""

from __future__ import annotations

import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gen_art import PALETTE, write_png  # noqa: E402


# ---------------------------------------------------------------------------
# Lector PNG (stdlib) con TODOS los filtros de scanline.
# ---------------------------------------------------------------------------
# `gen_art.read_png` solo acepta filtro 0 porque sus propias hojas se
# escriben asi. Los packs externos vienen de otras herramientas y usan
# filtros Sub/Up/Average/Paeth: sin esto, la auditoria se caeria al leerlos.

def _unfilter(raw: bytes, width: int, height: int, bpp: int) -> bytearray:
    stride = width * bpp
    out = bytearray(height * stride)
    pos = 0
    prev = bytearray(stride)
    for y in range(height):
        ft = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ft == 0:
            pass
        elif ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        else:
            raise ValueError("filtro PNG desconocido: %d" % ft)
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return out


def read_png(path: str):
    """Return (width, height, pixels RGBA) or raise ValueError."""
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("bad PNG signature")
    pos = 8
    width = height = 0
    depth = ctype = 0
    idat = bytearray()
    palette = b""
    trns = b""
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
            if depth != 8 or inter != 0:
                raise ValueError("unsupported PNG (depth=%d interlace=%d)"
                                 % (depth, inter))
        elif tag == b"PLTE":
            palette = body
        elif tag == b"tRNS":
            trns = body
        elif tag == b"IDAT":
            idat.extend(body)
        elif tag == b"IEND":
            seen_end = True
            break
        pos += 12 + length
    if not seen_end or width == 0 or height == 0:
        raise ValueError("incomplete PNG")
    raw = zlib.decompress(bytes(idat))
    if ctype == 6:
        bpp = 4
    elif ctype == 2:
        bpp = 3
    elif ctype == 0:
        bpp = 1
    elif ctype == 4:
        bpp = 2
    elif ctype == 3:
        bpp = 1
    else:
        raise ValueError("unsupported color type %d" % ctype)
    data_px = _unfilter(raw, width, height, bpp)
    pixels = bytearray(width * height * 4)
    n = width * height
    for i in range(n):
        if ctype == 6:
            r, g, b, a = data_px[i * 4:i * 4 + 4]
        elif ctype == 2:
            r, g, b = data_px[i * 3:i * 3 + 3]
            a = 255
        elif ctype == 0:
            r = g = b = data_px[i]
            a = 255
        elif ctype == 4:
            r = g = b = data_px[i * 2]
            a = data_px[i * 2 + 1]
        else:  # palette
            idx = data_px[i]
            if idx * 3 + 2 >= len(palette):
                raise ValueError("indice de paleta fuera de rango")
            r, g, b = palette[idx * 3:idx * 3 + 3]
            a = trns[idx] if idx < len(trns) else 255
        pixels[i * 4:i * 4 + 4] = bytes((r, g, b, a))
    return width, height, bytes(pixels)


# ---------------------------------------------------------------------------
# PNG canonico determinista (mismo formato que `gen_art.write_png`).
# ---------------------------------------------------------------------------

def _chunk(tag: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + tag + data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def png_bytes(width: int, height: int, pixels: bytes) -> bytes:
    """Codifica RGBA8 PNG en memoria, sin escribir ningun fichero."""
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filtro None
        raw.extend(pixels[y * stride:(y + 1) * stride])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", ihdr) +
            _chunk(b"IDAT", zlib.compress(bytes(raw), 9)) +
            _chunk(b"IEND", b""))


# ---------------------------------------------------------------------------
# Contrato del pack
# ---------------------------------------------------------------------------

CELL = 64          # celda canonica del skin (px)
PPU = 64            # PPU exacto del skin
PPU_MIN = 64       # PPU minimo declarado por la ficha del pack
PPU_MAX = 66

# Animaciones y numero de frames (ficha del pack entregado por el autor).
ANIM_FRAMES = {
    "idle": 2,
    "walk": 5,
    "walk_alt": 3,
    "attack": 6,
    "attack_alt": 2,
    "rise": 5,
    "death": 6,
    "special": 4,
}

# Anclaje: la union global de todos los frames se centra en la celda. Todos
# los frames reciben la misma traslacion global.
ANCHOR = "global-union-center"

CANONICAL_COLORS = []
for _index, _name, _hex in PALETTE:
    CANONICAL_COLORS.append((int(_hex[1:3], 16), int(_hex[3:5], 16),
                             int(_hex[5:7], 16)))
LEGAL_CANONICAL = set(CANONICAL_COLORS)

HERE = os.path.dirname(os.path.abspath(__file__))
SKIN_DIR = os.path.normpath(
    os.path.join(HERE, "..", "assets", "enemies", "zombie"))


# ---------------------------------------------------------------------------
# Utilidades de imagen y layout
# ---------------------------------------------------------------------------

def frame_files(anim_dir: str, prefix: str | None = None):
    """Frames de una animacion, ordenados por indice."""
    if not os.path.isdir(anim_dir):
        return []
    names = []
    for name in os.listdir(anim_dir):
        if not name.endswith(".png"):
            continue
        stem = name[:-4]
        if "_" not in stem:
            continue
        if prefix is not None and not stem.startswith(prefix + "_"):
            continue
        suffix = stem.rsplit("_", 1)[1]
        if suffix.isdigit():
            names.append((int(suffix), name))
    names.sort()
    return [os.path.join(anim_dir, name) for _, name in names]


def png_paths(root: str):
    """Rutas relativas de todos los PNG bajo root."""
    found = []
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            if name.endswith(".png"):
                rel = os.path.relpath(os.path.join(dirpath, name), root)
                found.append(rel.replace(os.sep, "/"))
    return sorted(found)


def pixel_stats(width: int, height: int, pixels: bytes):
    """(opacos, bbox_opaco, colores_distintos) de un frame RGBA."""
    bbox = None
    colors = set()
    opaque = 0
    for y in range(height):
        row = y * width * 4
        for x in range(width):
            i = row + x * 4
            r, g, b, a = pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]
            if a == 0:
                continue
            opaque += 1
            colors.add((r, g, b))
            if bbox is None:
                bbox = [x, y, x + 1, y + 1]
            else:
                if x < bbox[0]:
                    bbox[0] = x
                if y < bbox[1]:
                    bbox[1] = y
                if x + 1 > bbox[2]:
                    bbox[2] = x + 1
                if y + 1 > bbox[3]:
                    bbox[3] = y + 1
    return opaque, bbox, colors


def is_flat_card(pixels: bytes, width: int, height: int, colors) -> bool:
    """True si el frame es una 'tarjeta' de color, no una silueta.

    Se detectan dos patrones del pack proxy del autor: menos de cuatro colores
    y/o una superficie casi totalmente opaca que llena su bbox rectangular.
    """
    if len(colors) < 4:
        return True
    opaque, bbox, _colors = pixel_stats(width, height, pixels)
    if not opaque or bbox is None:
        return False
    bbox_area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
    if bbox_area <= 0:
        return False
    coverage = opaque / float(width * height)
    fill = opaque / float(bbox_area)
    return coverage >= 0.70 and fill >= 0.70


def union_bbox(images):
    """Bbox opaco de la union de una lista de (w, h, RGBA)."""
    union = None
    for width, height, pixels in images:
        _opaque, bbox, _colors = pixel_stats(width, height, pixels)
        if bbox is None:
            continue
        if union is None:
            union = list(bbox)
        else:
            union[0] = min(union[0], bbox[0])
            union[1] = min(union[1], bbox[1])
            union[2] = max(union[2], bbox[2])
            union[3] = max(union[3], bbox[3])
    return tuple(union) if union is not None else None


def shift_image(image, dx: int, dy: int, cell: int = CELL):
    """Mueve una imagen a una celda cell x cell, recortando lo que sobre."""
    width, height, pixels = image
    out = bytearray(cell * cell * 4)
    for sy in range(height):
        dy2 = sy + dy
        if not (0 <= dy2 < cell):
            continue
        src_row = sy * width * 4
        dst_row = dy2 * cell * 4
        for sx in range(width):
            dx2 = sx + dx
            if not (0 <= dx2 < cell):
                continue
            src = src_row + sx * 4
            alpha = pixels[src + 3]
            if alpha == 0:
                continue
            dst = dst_row + dx2 * 4
            out[dst:dst + 4] = pixels[src:src + 4]
    return cell, cell, bytes(out)


def center_source_canvases(images, cell: int = CELL):
    """Empotra cada canvas fuente en una celda, centrado por su canvas.

    Este paso solo da coordenadas comparables a frames que llegan recortados.
    El ancla definitivo se calcula despues sobre la union opaca GLOBAL.
    """
    centered = []
    for width, height, pixels in images:
        centered.append(shift_image(
            (width, height, pixels),
            (cell - width) // 2,
            (cell - height) // 2,
            cell,
        ))
    return centered


def anchor_images(images, cell: int = CELL):
    """Centra la union opaca global y aplica una traslacion comun.

    Devuelve (frames_alineados, (dx, dy)). La operacion es idempotente: si la
    union ya esta centrada, la traslacion es (0, 0) y los pixeles no cambian.
    """
    union = union_bbox(images)
    if union is None:
        raise ValueError("no hay frames opacos para calcular el ancla")
    left, top, right, bottom = union
    width = right - left
    height = bottom - top
    if width <= cell:
        dx = (cell - width) // 2 - left
    else:
        crop_left = left + (width - cell) // 2
        dx = -crop_left
    if height <= cell:
        dy = (cell - height) // 2 - top
    else:
        crop_top = top + (height - cell) // 2
        dy = -crop_top
    aligned = [shift_image(image, dx, dy, cell) for image in images]
    return aligned, (dx, dy)


def strip_bytes(frames, cell: int = CELL) -> bytes:
    """Concatena frames ya ALUCIADOS en celdas en un strip horizontal."""
    width = cell * len(frames)
    out = bytearray(width * cell * 4)
    for idx, frame in enumerate(frames):
        frame_width, frame_height, pixels = frame
        if (frame_width, frame_height) != (cell, cell):
            raise ValueError("frame fuera de celda: %dx%d" %
                             (frame_width, frame_height))
        for row in range(cell):
            src = row * cell * 4
            dst = (row * width + idx * cell) * 4
            out[dst:dst + cell * 4] = pixels[src:src + cell * 4]
    return bytes(out)


def strip_from_frames(paths, cell: int = CELL) -> bytes:
    """Normaliza frames con el ancla global y los concatena en un strip."""
    images = [read_png(path) for path in paths]
    prepared = center_source_canvases(images, cell)
    aligned, _translation = anchor_images(prepared, cell)
    return strip_bytes(aligned, cell)


def fill_empty_frames(frames_by_anim):
    """Rellena frames vacios con el frame no vacio mas cercano de su anim.

    En caso de empate se elige el indice anterior. Devuelve el numero de
    frames rellenados; muta las listas de entrada.
    """
    filled = 0
    for anim in sorted(frames_by_anim):
        images = frames_by_anim[anim]
        non_empty = []
        for idx, image in enumerate(images):
            _opaque, bbox, _colors = pixel_stats(*image)
            if bbox is not None:
                non_empty.append(idx)
        if not non_empty:
            raise ValueError("la animacion %s no tiene frames no vacios" % anim)
        for idx, image in enumerate(images):
            _opaque, bbox, _colors = pixel_stats(*image)
            if bbox is not None:
                continue
            nearest = min(non_empty, key=lambda other: (abs(other - idx), other))
            images[idx] = images[nearest]
            filled += 1
    return filled


def quantize_to_canonical(image):
    """Mapea un frame externo a la paleta canonica de 16 colores.

    El alpha se vuelve binario (0/255) y cada color opaco se asigna al color
    canonico mas cercano. La conversion es determinista y no crea colores nuevos.
    """
    width, height, pixels = image
    out = bytearray(width * height * 4)
    for i in range(width * height):
        src = i * 4
        alpha = pixels[src + 3]
        if alpha < 128:
            out[src:src + 4] = b"\x00\x00\x00\x00"
            continue
        rgb = (pixels[src], pixels[src + 1], pixels[src + 2])
        if rgb in LEGAL_CANONICAL:
            nearest = rgb
        else:
            nearest = min(
                CANONICAL_COLORS,
                key=lambda color: (
                    (color[0] - rgb[0]) ** 2 +
                    (color[1] - rgb[1]) ** 2 +
                    (color[2] - rgb[2]) ** 2,
                    CANONICAL_COLORS.index(color),
                ),
            )
        out[src:src + 4] = bytes((nearest[0], nearest[1], nearest[2], 255))
    return width, height, bytes(out)


def load_expected_frames(pack_dir: str):
    """Carga el layout esperado; devuelve (frames_por_anim, errores)."""
    frames_by_anim = {}
    errors = []
    for anim in sorted(ANIM_FRAMES):
        count = ANIM_FRAMES[anim]
        anim_dir = os.path.join(pack_dir, anim)
        images = []
        for idx in range(1, count + 1):
            name = "%s_%02d.png" % (anim, idx)
            path = os.path.join(anim_dir, name)
            if not os.path.exists(path):
                errors.append("falta %s/%s" % (anim, name))
                continue
            try:
                images.append(read_png(path))
            except (OSError, ValueError) as exc:
                errors.append("%s/%s: PNG invalido (%s)" % (anim, name, exc))
        frames_by_anim[anim] = images
        found = frame_files(anim_dir, prefix=anim)
        if len(found) != count:
            errors.append("%s: %d frames (ficha: %d)" %
                          (anim, len(found), count))
    return frames_by_anim, errors


# ---------------------------------------------------------------------------
# Auditoria
# ---------------------------------------------------------------------------

def audit(pack_dir: str) -> int:
    if not os.path.isdir(pack_dir):
        print("ERROR: no existe el directorio %s" % pack_dir)
        return 2
    print("AUDITORIA DEL PACK: %s" % os.path.abspath(pack_dir))
    print("=" * 72)
    issues = []
    total_frames = 0
    empty_frames = []
    flat_cards = []
    variable_anims = []
    outside_colors = set()

    anim_dirs = sorted(
        d for d in os.listdir(pack_dir)
        if os.path.isdir(os.path.join(pack_dir, d)))
    for anim in anim_dirs:
        anim_dir = os.path.join(pack_dir, anim)
        files = frame_files(anim_dir)
        expected = ANIM_FRAMES.get(anim)
        sizes = []
        for path in files:
            try:
                w, h, px = read_png(path)
            except (OSError, ValueError) as exc:
                issues.append("%s: PNG invalido (%s)" % (path, exc))
                continue
            total_frames += 1
            opaque, bbox, colors = pixel_stats(w, h, px)
            sizes.append((os.path.basename(path), w, h))
            outside_colors.update(c for c in colors if c not in LEGAL_CANONICAL)
            if opaque == 0:
                empty_frames.append(os.path.basename(path))
            elif is_flat_card(px, w, h, colors):
                flat_cards.append((os.path.basename(path), len(colors)))
        widths = sorted({w for _, w, _ in sizes})
        heights = sorted({h for _, _, h in sizes})
        uniform = len(widths) == 1 and len(heights) == 1
        if not uniform:
            variable_anims.append(anim)
        flag = "" if uniform else "  <-- TAMANOS VARIABLES"
        count_note = ""
        if expected is not None and len(files) != expected:
            count_note = "  <-- %d frames (ficha: %d)" % (len(files), expected)
        print("\n  %-12s frames=%-3d tamanos=%s%s%s" % (
            anim, len(files),
            ("%dx%d" % (widths[0], heights[0])) if uniform
            else ("ancho=%s alto=%s" % (widths, heights)),
            flag, count_note))
        for name, w, h in sizes:
            print("      %-22s %dx%d" % (name, w, h))

    # Strips
    print("\n  STrips horizontales")
    for name in sorted(os.listdir(pack_dir)):
        if not name.endswith("_strip.png"):
            continue
        path = os.path.join(pack_dir, name)
        try:
            w, h, _px = read_png(path)
        except (OSError, ValueError) as exc:
            issues.append("%s: PNG invalido (%s)" % (path, exc))
            continue
        anim = name[:-len("_strip.png")]
        expected_frames = ANIM_FRAMES.get(anim)
        uniform = w % CELL == 0 and h == CELL
        cells = w // CELL if uniform else 0
        note = ""
        if not uniform:
            note = "  <-- NO rebanable en celdas de %d" % CELL
        elif expected_frames is not None and cells != expected_frames:
            note = "  <-- %d celdas (ficha: %d frames)" % (cells, expected_frames)
        print("      %-24s %dx%d%s" % (name, w, h, note))

    # Resumen
    print("\n" + "=" * 72)
    print("RESUMEN")
    print("  frames totales            : %d" % total_frames)
    print("  frames VACIOS (alpha=0)   : %d %s" % (
        len(empty_frames), empty_frames or ""))
    print("  frames 'tarjeta de color' : %d %s" % (
        len(flat_cards),
        ["%s(%d colores)" % (n, c) for n, c in flat_cards[:6]]))
    print("  animaciones con tamano variable: %s" %
          (variable_anims or "ninguna"))
    print("  colores fuera de paleta canonica: %d" % len(outside_colors))

    if empty_frames:
        issues.append("%d frames completamente vacios (alpha=0): %s" % (
            len(empty_frames), ", ".join(empty_frames)))
    if flat_cards:
        issues.append("%d frames son tarjetas de color plano, no siluetas" %
                      len(flat_cards))
    if variable_anims:
        issues.append("tamanos de frame variables en: %s (el strip no es rebanable)" %
                      ", ".join(variable_anims))
    if outside_colors:
        issues.append("%d colores opacos fuera de la paleta canonica de 16" %
                      len(outside_colors))

    if issues:
        print("\n  INCIDENCIAS (%d):" % len(issues))
        for issue in issues:
            print("    - %s" % issue)
        return 1
    print("\n  Sin incidencias mecanicas.")
    return 0


# ---------------------------------------------------------------------------
# Build / check del pack del proyecto
# ---------------------------------------------------------------------------

def _flatten_frames(frames_by_anim):
    flat = []
    for anim in sorted(ANIM_FRAMES):
        flat.extend(frames_by_anim.get(anim, []))
    return flat


def _split_anchored(frames_by_anim, anchored):
    result = {}
    pos = 0
    for anim in sorted(ANIM_FRAMES):
        count = len(frames_by_anim.get(anim, []))
        result[anim] = anchored[pos:pos + count]
        pos += count
    return result


def build(verbose: bool = True) -> int:
    """Regenera los strips del proyecto a partir de sus frames."""
    if not os.path.isdir(SKIN_DIR):
        print("ERROR: no existe %s" % SKIN_DIR)
        return 2
    frames_by_anim, errors = load_expected_frames(SKIN_DIR)
    if errors:
        for error in errors:
            print("ERROR %s" % error)
        return 2
    for anim in sorted(ANIM_FRAMES):
        for idx, (width, height, _pixels) in enumerate(frames_by_anim[anim], 1):
            if (width, height) != (CELL, CELL):
                print("ERROR %s frame %d fuera de celda: %dx%d" %
                      (anim, idx, width, height))
                return 2

    flat = _flatten_frames(frames_by_anim)
    anchored, translation = anchor_images(flat, CELL)
    anchored_by_anim = _split_anchored(frames_by_anim, anchored)
    if verbose and translation != (0, 0):
        print("  ancla global: traslacion %s" % (translation,))

    written = 0
    for anim in sorted(ANIM_FRAMES):
        frames = anchored_by_anim[anim]
        if not frames:
            print("  AVISO: sin frames para %s" % anim)
            continue
        strip = strip_bytes(frames, CELL)
        path = os.path.join(SKIN_DIR, "%s_strip.png" % anim)
        write_png(path, CELL * len(frames), CELL, bytearray(strip))
        written += 1
        if verbose:
            print("  %-12s %d frames -> %s (%dx%d)" % (
                anim, len(frames), os.path.basename(path),
                CELL * len(frames), CELL))
    print("  strips escritos: %d" % written)
    return 0


def check() -> int:
    """Puerta de CI: strips, layout, anclaje y contrato del pack."""
    if not os.path.isdir(SKIN_DIR):
        print("ERROR: no existe %s" % SKIN_DIR)
        return 2

    bad = 0
    expected_frames = set()
    for anim, count in ANIM_FRAMES.items():
        for idx in range(1, count + 1):
            expected_frames.add("%s/%s_%02d.png" % (anim, anim, idx))
    expected_strips = {"%s_strip.png" % anim for anim in ANIM_FRAMES}
    expected_pngs = expected_frames | expected_strips
    actual_pngs = set(png_paths(SKIN_DIR))

    for rel in sorted(actual_pngs - expected_pngs):
        print("FAIL PNG sobrante: %s" % rel)
        bad += 1
    for rel in sorted(expected_pngs - actual_pngs):
        print("FAIL falta PNG: %s" % rel)
        bad += 1

    frames_by_anim = {}
    for anim in sorted(ANIM_FRAMES):
        images = []
        for idx in range(1, ANIM_FRAMES[anim] + 1):
            name = "%s_%02d.png" % (anim, idx)
            path = os.path.join(SKIN_DIR, anim, name)
            if not os.path.exists(path):
                continue
            try:
                width, height, pixels = read_png(path)
            except (OSError, ValueError) as exc:
                print("FAIL PNG invalido: %s/%s (%s)" % (anim, name, exc))
                bad += 1
                continue
            if (width, height) != (CELL, CELL):
                print("FAIL frame fuera de celda: %s/%s (%dx%d)" %
                      (anim, name, width, height))
                bad += 1
                continue
            opaque, bbox, colors = pixel_stats(width, height, pixels)
            if bbox is None:
                print("FAIL frame vacio: %s/%s" % (anim, name))
                bad += 1
                continue
            center_x = (bbox[0] + bbox[2]) / 2.0
            if abs(center_x - CELL / 2.0) > 1.0:
                print("FAIL frame descentrado: %s/%s centro_x=%.1f" %
                      (anim, name, center_x))
                bad += 1
            if CELL - bbox[3] < 2:
                print("FAIL frame sin margen inferior: %s/%s" % (anim, name))
                bad += 1
            if len(colors) < 4:
                print("FAIL frame con menos de 4 colores: %s/%s" %
                      (anim, name))
                bad += 1
            illegal = sorted(c for c in colors if c not in LEGAL_CANONICAL)
            if illegal:
                print("FAIL paleta no canonica: %s/%s (%d colores)" %
                      (anim, name, len(illegal)))
                bad += 1
            images.append((width, height, pixels))
        frames_by_anim[anim] = images
        if len(images) != ANIM_FRAMES[anim]:
            print("FAIL numero de frames: %s tiene %d (esperado %d)" %
                  (anim, len(images), ANIM_FRAMES[anim]))
            bad += 1

    flat = _flatten_frames(frames_by_anim)
    if flat:
        union = union_bbox(flat)
        center_x = (union[0] + union[2]) / 2.0
        center_y = (union[1] + union[3]) / 2.0
        if abs(center_x - CELL / 2.0) > 1.0 or \
                abs(center_y - CELL / 2.0) > 1.0:
            print("FAIL union global descentrada: centro=(%.1f, %.1f)" %
                  (center_x, center_y))
            bad += 1
        anchored, _translation = anchor_images(flat, CELL)
        anchored_by_anim = _split_anchored(frames_by_anim, anchored)
        for anim in sorted(ANIM_FRAMES):
            frames = anchored_by_anim[anim]
            if len(frames) != ANIM_FRAMES[anim]:
                continue
            path = os.path.join(SKIN_DIR, "%s_strip.png" % anim)
            if not os.path.exists(path):
                continue
            expected_width = CELL * len(frames)
            expected_strip = strip_bytes(frames, CELL)
            expected_blob = png_bytes(expected_width, CELL, expected_strip)
            try:
                with open(path, "rb") as f:
                    actual_blob = f.read()
                width, height, pixels = read_png(path)
            except (OSError, ValueError) as exc:
                print("FAIL strip invalido: %s_strip.png (%s)" % (anim, exc))
                bad += 1
                continue
            if (width, height) != (expected_width, CELL):
                print("FAIL dimensiones de strip: %s_strip.png (%dx%d)" %
                      (anim, width, height))
                bad += 1
            if bytes(pixels) != expected_strip:
                print("FAIL strip desincronizado: %s_strip.png" % anim)
                bad += 1
            elif actual_blob != expected_blob:
                print("FAIL bytes PNG no canonicos: %s_strip.png" % anim)
                bad += 1
            else:
                print("OK   %s_strip.png (%d frames, %dx%d)" %
                      (anim, len(frames), width, height))

    print("SKIN_PACK_CHECK failures=%d" % bad)
    return 1 if bad else 0


# ---------------------------------------------------------------------------
# Importacion de packs externos
# ---------------------------------------------------------------------------

def _is_within(path: str, root: str) -> bool:
    try:
        return os.path.commonpath([os.path.realpath(path),
                                   os.path.realpath(root)]) == \
            os.path.realpath(root)
    except ValueError:
        return False


def import_pack(pack_dir: str, out_dir: str | None, force: bool = False) -> int:
    """Normaliza un pack externo al layout del proyecto."""
    if not out_dir:
        print("ERROR: `import` exige --out <destino> explicito")
        return 2
    if not os.path.isdir(pack_dir):
        print("ERROR: no existe el directorio %s" % pack_dir)
        return 2

    out_dir = os.path.abspath(os.path.expanduser(out_dir))
    if _is_within(out_dir, SKIN_DIR) and not force:
        print("ERROR: no se puede escribir en el pack canonico %s sin --force" %
              SKIN_DIR)
        return 2
    if os.path.exists(out_dir) and not os.path.isdir(out_dir):
        print("ERROR: el destino no es un directorio: %s" % out_dir)
        return 2

    frames_by_anim, errors = load_expected_frames(pack_dir)
    if errors:
        for error in errors:
            print("ERROR %s" % error)
        return 2

    # Un frame "tarjeta de color" NO tiene silueta. Ninguna normalizacion
    # puede inventarla: rellenar frames vacios, recentrar lienzos o cuantizar
    # la paleta no convierte un rectangulo en un personaje. Importarlo
    # dejaria rectangulos de color en pantalla, asi que el importador
    # RECHAZA el pack y no escribe nada, salvo que se fuerce de forma
    # explicita.
    flat_frames = []
    for anim in sorted(frames_by_anim):
        for idx, (width, height, pixels) in enumerate(frames_by_anim[anim], 1):
            _opaque, bbox, colors = pixel_stats(width, height, pixels)
            if bbox is None:
                continue  # frame vacio: se rellena con el vecino mas cercano
            if is_flat_card(pixels, width, height, colors):
                flat_frames.append("%s/%s_%02d.png" % (anim, anim, idx))
    if flat_frames and not force:
        print("ERROR: el pack tiene %d frames 'tarjeta de color' sin silueta:"
              % len(flat_frames))
        for name in flat_frames[:12]:
            print("  - %s" % name)
        if len(flat_frames) > 12:
            print("  ... y %d mas" % (len(flat_frames) - 12))
        print("ERROR: ninguna normalizacion puede inventar una silueta; no se "
              "importa nada. Usa --force solo si es intencional.")
        return 2
    if flat_frames:
        print("AVISO: importacion forzada con %d frames 'tarjeta de color'"
              % len(flat_frames))

    try:
        filled = fill_empty_frames(frames_by_anim)
    except ValueError as exc:
        print("ERROR %s" % exc)
        return 2

    # Cuantizacion a la paleta canonica: el pack importado no introduce
    # colores nuevos al proyecto.
    for anim in frames_by_anim:
        frames_by_anim[anim] = [quantize_to_canonical(image)
                                 for image in frames_by_anim[anim]]

    flat = _flatten_frames(frames_by_anim)
    prepared = center_source_canvases(flat, CELL)
    anchored, translation = anchor_images(prepared, CELL)
    anchored_by_anim = _split_anchored(frames_by_anim, anchored)

    os.makedirs(out_dir, exist_ok=True)
    frame_count = 0
    for anim in sorted(ANIM_FRAMES):
        anim_dir = os.path.join(out_dir, anim)
        os.makedirs(anim_dir, exist_ok=True)
        for idx, (width, height, pixels) in enumerate(anchored_by_anim[anim], 1):
            path = os.path.join(anim_dir, "%s_%02d.png" % (anim, idx))
            write_png(path, width, height, bytearray(pixels))
            frame_count += 1

    strip_count = 0
    for anim in sorted(ANIM_FRAMES):
        frames = anchored_by_anim[anim]
        strip = strip_bytes(frames, CELL)
        path = os.path.join(out_dir, "%s_strip.png" % anim)
        write_png(path, CELL * len(frames), CELL, bytearray(strip))
        strip_count += 1

    print("SKIN_IMPORT frames=%d strips=%d filled=%d anchor=%s -> %s" % (
        frame_count, strip_count, filled, translation, out_dir))
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "audit":
        return audit(argv[2] if len(argv) > 2 else "~/zombie_sprites")
    if cmd == "import":
        if len(argv) < 3 or argv[2].startswith("-"):
            print("ERROR: `import` exige <dir> y --out <destino> explicito")
            return 2
        pack_dir = argv[2]
        out_dir = None
        force = False
        index = 3
        while index < len(argv):
            arg = argv[index]
            if arg == "--out":
                index += 1
                if index >= len(argv):
                    print("ERROR: --out necesita un valor")
                    return 2
                out_dir = argv[index]
            elif arg.startswith("--out="):
                out_dir = arg.split("=", 1)[1]
            elif arg == "--force":
                force = True
            else:
                print("ERROR: argumento desconocido para import: %s" % arg)
                return 2
            index += 1
        return import_pack(pack_dir, out_dir, force)
    if cmd == "build":
        return build()
    if cmd == "check":
        return check()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
