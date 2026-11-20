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
    selftest                            Autopruebas del importador (CI).

Regla de anclaje del proyecto: el bbox opaco de la UNION de todos los frames
se centra en la celda 64x64 y se aplica la MISMA traslacion a todos los frames.
Nunca se reencuadra un frame usando el bbox de su propio frame; asi el
personaje no patina entre frames ni entre animaciones.

Solo stdlib (zlib + struct), igual que `tools/gen_art.py`.
"""

from __future__ import annotations

import hashlib
import os
import struct
import sys
import tempfile
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


## Tope de dimensiones: un PNG que declara un lienzo enorme no se descomprime
## (evita que un fichero corrupto agote la memoria del proceso).
MAX_DIMENSION = 4096


def read_png(path: str):
    """Return (width, height, pixels RGBA) or raise ValueError.

    Toda corrupcion del fichero se traduce a `ValueError`: el llamante
    muestra un diagnostico ("PNG invalido (...)") en vez de un traceback
    de `struct.error` o `zlib.error`.
    """
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
        # El chunk completo (longitud + tag + cuerpo + CRC) tiene que caber
        # en el fichero. Sin esta comprobacion, un PNG truncado provoca que
        # `struct.unpack` lance `struct.error` en vez de un diagnostico.
        if pos + 12 + length > len(data):
            raise ValueError("chunk %r truncado (%d bytes declarados)"
                             % (tag, length))
        body = data[pos + 8:pos + 8 + length]
        crc = struct.unpack(">I", data[pos + 8 + length:pos + 12 + length])[0]
        if (zlib.crc32(tag + body) & 0xFFFFFFFF) != crc:
            raise ValueError("bad CRC in %r" % tag)
        if tag == b"IHDR":
            if length != 13:
                raise ValueError("IHDR invalido (%d bytes, se esperan 13)"
                                 % length)
            try:
                width, height, depth, ctype, comp, filt, inter = struct.unpack(
                    ">IIBBBBB", body)
            except struct.error as exc:
                raise ValueError("IHDR invalido: %s" % exc)
            if depth != 8 or inter != 0:
                raise ValueError("unsupported PNG (depth=%d interlace=%d)"
                                 % (depth, inter))
            if width == 0 or height == 0:
                raise ValueError("IHDR con dimensiones cero")
            if width > MAX_DIMENSION or height > MAX_DIMENSION:
                raise ValueError("dimensiones excesivas (%dx%d, maximo %d)"
                                 % (width, height, MAX_DIMENSION))
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
    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error as exc:
        raise ValueError("stream IDAT corrupto: %s" % exc)
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
    try:
        data_px = _unfilter(raw, width, height, bpp)
    except (IndexError, ValueError, struct.error) as exc:
        raise ValueError("pixeles PNG invalidos: %s" % exc)
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
    # Estructural: las ocho animaciones de la ficha tienen que estar. Un
    # directorio vacio o incompleto es una INCIDENCIA (rc=1), no un pack
    # "sin incidencias mecanicas". Antes estas notas solo se imprimian y
    # el auditor daba verde sobre packs estructuralmente invalidos.
    expected_anims = set(ANIM_FRAMES.keys())
    present_anims = set(anim_dirs)
    for anim in sorted(expected_anims - present_anims):
        issues.append("falta la animacion '%s'" % anim)
    for anim in sorted(present_anims - expected_anims):
        issues.append("animacion inesperada: '%s'" % anim)
    for anim in anim_dirs:
        anim_dir = os.path.join(pack_dir, anim)
        files = frame_files(anim_dir)
        expected = ANIM_FRAMES.get(anim)
        if expected is None:
            issues.append("animacion inesperada: '%s'" % anim)
        elif len(files) != expected:
            issues.append("%s: %d frames (ficha: %d)"
                          % (anim, len(files), expected))
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
    found_strips = set()
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
        found_strips.add(anim)
        expected_frames = ANIM_FRAMES.get(anim)
        if expected_frames is None:
            issues.append("strip inesperado: %s" % name)
        uniform = w % CELL == 0 and h == CELL
        cells = w // CELL if uniform else 0
        note = ""
        if not uniform:
            note = "  <-- NO rebanable en celdas de %d" % CELL
            issues.append("%s: NO rebanable en celdas de %d (%dx%d)"
                          % (name, CELL, w, h))
        elif expected_frames is not None and cells != expected_frames:
            note = "  <-- %d celdas (ficha: %d frames)" % (cells, expected_frames)
            issues.append("%s: %d celdas (ficha: %d frames)"
                          % (name, cells, expected_frames))
        print("      %-24s %dx%d%s" % (name, w, h, note))
    for anim in sorted(expected_anims - found_strips):
        issues.append("falta el strip %s_strip.png" % anim)

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
# Autopruebas del importador y del auditor (puerta de CI)
# ---------------------------------------------------------------------------

def _synthetic_frame(width: int = CELL, height: int = CELL) -> bytes:
    """Frame sintetico CON silueta (no es una tarjeta de color)."""
    pixels = bytearray(width * height * 4)
    body = [(60, 90, 110, 255), (120, 80, 60, 255),
            (40, 60, 80, 255), (200, 180, 140, 255)]
    for y in range(height // 2, height // 2 + 20):
        for x in range(width // 2 - 6, width // 2 + 6):
            if not (0 <= x < width and 0 <= y < height):
                continue
            index = (y * width + x) * 4
            pixels[index:index + 4] = bytes(body[(x + y) % len(body)])
    return bytes(pixels)


def _write_synthetic_pack(pack_dir: str, flat_card: bool = False) -> None:
    """Escribe un pack sintetico con la ficha de frames del proyecto."""
    for anim, count in ANIM_FRAMES.items():
        anim_dir = os.path.join(pack_dir, anim)
        os.makedirs(anim_dir, exist_ok=True)
        for index in range(1, count + 1):
            if flat_card and anim == "idle" and index == 1:
                pixels = bytearray(CELL * CELL * 4)
                for i in range(CELL * CELL):
                    pixels[i * 4:i * 4 + 4] = bytes((156, 192, 194, 255))
            else:
                pixels = bytearray(_synthetic_frame())
            path = os.path.join(anim_dir, "%s_%02d.png" % (anim, index))
            with open(path, "wb") as handle:
                handle.write(png_bytes(CELL, CELL, bytes(pixels)))


def _tree_files(root: str) -> list:
    found = []
    for base, _dirs, names in os.walk(root):
        for name in names:
            found.append(os.path.join(base, name))
    return found


def _tree_digest(root: str) -> dict:
    """Huella del contenido de un arbol (ruta relativa -> SHA-256)."""
    digest = {}
    for path in sorted(_tree_files(root)):
        with open(path, "rb") as handle:
            digest[os.path.relpath(path, root)] = hashlib.sha256(
                handle.read()).hexdigest()
    return digest


def selftest() -> int:
    """Autopruebas del importador y del auditor (puerta de CI).

    Cubre los cierres de R2 que no tenian regresion automatizada:

      1. un pack con un frame 'tarjeta de color' se RECHAZA (rc=2) y no
         escribe nada;
      2. un destino con symlinks NO permite escribir fuera del destino;
      3. un PNG corrupto produce un diagnostico (`ValueError`), no un
         traceback de `struct.error`;
      4. `audit` de un pack estructuralmente invalido devuelve rc=1;
      5. un pack valido se importa con rc=0 (si no, los rechazos de 1 y 2
         serian verdes triviales);
      6. el destino NO puede ser el propio pack de origen: con `--out` igual
         a la entrada, el importador normalizaba los frames EN EL SITIO
         (rellenaba los vacios, cuantizaba la paleta y perdia los anchos
         originales) de forma irreversible.
    """
    failures = []
    with tempfile.TemporaryDirectory(prefix="skinpack_selftest_") as temporary:
        root = os.path.join(temporary, "work")
        os.makedirs(root, exist_ok=True)

        valid_pack = os.path.join(root, "pack_ok")
        _write_synthetic_pack(valid_pack)

        card_pack = os.path.join(root, "pack_card")
        _write_synthetic_pack(card_pack, flat_card=True)

        # 5. Un pack valido se importa (si no, los rechazos de abajo son
        #    verdes triviales porque el importador esta roto).
        out_ok = os.path.join(root, "out_ok")
        code = import_pack(valid_pack, out_ok)
        if code != 0:
            failures.append("un pack valido debe importarse (rc=0, hubo %d)" % code)

        # 1. El pack con una tarjeta de color se rechaza sin escribir nada.
        out_card = os.path.join(root, "out_card")
        code = import_pack(card_pack, out_card)
        if code != 2:
            failures.append("un pack con tarjeta de color debe rechazarse "
                            "(rc=2, hubo %d)" % code)
        if os.path.exists(out_card) and _tree_files(out_card):
            failures.append("un pack con tarjeta de color no debe escribir nada")

        # 2. Un subdirectorio que es symlink no puede sacar escrituras fuera.
        out_link = os.path.join(root, "out_link")
        escaped = os.path.join(root, "escaped")
        os.makedirs(out_link, exist_ok=True)
        os.makedirs(escaped, exist_ok=True)
        os.symlink(escaped, os.path.join(out_link, "idle"))
        code = import_pack(valid_pack, out_link)
        if code != 2:
            failures.append("un destino con symlink debe rechazarse "
                            "(rc=2, hubo %d)" % code)
        if _tree_files(escaped):
            failures.append("el destino con symlink escribio fuera: %s"
                            % sorted(_tree_files(escaped)))

        # 2b. Un strip que es symlink a un fichero externo no lo sobrescribe.
        out_link_file = os.path.join(root, "out_link_file")
        os.makedirs(out_link_file, exist_ok=True)
        victim = os.path.join(root, "victim.txt")
        with open(victim, "w", encoding="utf-8") as handle:
            handle.write("ORIGINAL")
        os.symlink(victim, os.path.join(out_link_file, "idle_strip.png"))
        code = import_pack(valid_pack, out_link_file)
        if code != 2:
            failures.append("un destino con strip symlink debe rechazarse "
                            "(rc=2, hubo %d)" % code)
        with open(victim, encoding="utf-8") as handle:
            content = handle.read()
        if content != "ORIGINAL":
            failures.append("el importador sobrescribio un fichero externo")

        # 3. Un PNG corrupto da diagnostico, no traceback.
        broken = os.path.join(root, "broken.png")
        with open(broken, "wb") as handle:
            handle.write(b"\x89PNG\r\n\x1a\n" +
                         struct.pack(">I", 4) + b"IHDR" + b"\x00\x00")
        try:
            read_png(broken)
            failures.append("un PNG truncado debe lanzar ValueError")
        except ValueError:
            pass
        except Exception as exc:  # pragma: no cover - solo si el parser cambia
            failures.append("un PNG truncado debe lanzar ValueError, no %s"
                            % type(exc).__name__)

        # 4. `audit` de un pack estructuralmente invalido devuelve rc=1.
        empty = os.path.join(root, "empty")
        os.makedirs(empty, exist_ok=True)
        code = audit(empty)
        if code != 1:
            failures.append("audit de un pack vacio debe devolver rc=1 "
                            "(devolvio %d)" % code)

        # 6. El destino no puede ser el propio pack de origen: importando
        #    sobre el, el importador reescribia la entrada (rellenaba los
        #    frames vacios y cuantizaba la paleta) y el resultado era
        #    IRREVERSIBLE.
        source_pack = os.path.join(root, "pack_source")
        _write_synthetic_pack(source_pack)
        before = _tree_digest(source_pack)
        if any(len(digest) != 64 for digest in before.values()):
            failures.append("la huella del arbol debe usar SHA-256 (64 hex)")
        code = import_pack(source_pack, source_pack)
        if code != 2:
            failures.append("importar sobre el propio pack de origen debe "
                            "rechazarse (rc=2, hubo %d)" % code)
        after = _tree_digest(source_pack)
        if before != after:
            changed = sorted(set(before) ^ set(after)) or \
                sorted(k for k in before if before[k] != after.get(k))
            failures.append("importar sobre el propio pack de origen lo "
                            "modifico: %s" % changed[:8])

    print("SKIN_PACK_SELFTEST failures=%d" % len(failures))
    for failure in failures:
        print("  - %s" % failure)
    return 1 if failures else 0


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


def _write_png_atomic(path: str, width: int, height: int, pixels: bytearray) -> None:
    """Escribe un PNG sin seguir enlaces simbolicos.

    Se escribe primero en un temporal del MISMO directorio y se renombra con
    `os.replace` (que opera sobre la ruta, no sobre el destino del enlace):
    si `path` fuera un symlink a un fichero de fuera, ese fichero no se
    toca; lo que se sustituye es el propio enlace.
    """
    data = png_bytes(width, height, bytes(pixels))
    directory = os.path.dirname(os.path.abspath(path))
    handle, temporary = tempfile.mkstemp(prefix=".skinpack_", dir=directory)
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(data)
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.unlink(temporary)
        raise


def _plan_output_paths(out_dir: str, counts: dict) -> tuple:
    """Rutas de salida que el importador va a escribir.

    Se calcula ANTES de escribir nada para poder validar el destino entero
    (symlinks incluidos) en una sola pasada.
    """
    directories = []
    files = []
    for anim in sorted(ANIM_FRAMES):
        anim_dir = os.path.join(out_dir, anim)
        directories.append(anim_dir)
        for index in range(1, int(counts.get(anim, 0)) + 1):
            files.append(os.path.join(anim_dir, "%s_%02d.png" % (anim, index)))
        files.append(os.path.join(out_dir, "%s_strip.png" % anim))
    return directories, files


def import_pack(pack_dir: str, out_dir: str | None, force: bool = False) -> int:
    """Normaliza un pack externo al layout del proyecto."""
    if not out_dir:
        print("ERROR: `import` exige --out <destino> explicito")
        return 2
    if not os.path.isdir(pack_dir):
        print("ERROR: no existe el directorio %s" % pack_dir)
        return 2

    out_dir = os.path.abspath(os.path.expanduser(out_dir))
    pack_dir = os.path.abspath(os.path.expanduser(pack_dir))
    # El destino NO puede ser el propio pack de origen: con `--out` igual a
    # la entrada, el importador normalizaba los frames EN EL SITIO (rellenaba
    # los vacios, cuantizaba la paleta y perdia los anchos originales) de
    # forma IRREVERSIBLE. Se rechaza siempre, con o sin `--force`.
    if os.path.realpath(out_dir) == os.path.realpath(pack_dir):
        print("ERROR: el destino es el propio pack de origen (%s); la "
              "importacion destruiria la entrada. Usa otro --out." % pack_dir)
        return 2
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

    # --- Pre-flight del destino -----------------------------------------
    # Un destino con symlinks permitiria escribir FUERA del directorio
    # pedido: `out/idle` como enlace a otro directorio, o
    # `out/idle_strip.png` como enlace a un fichero que se sobrescribiria.
    # Se valida TODO el plan de escritura antes del primer byte.
    if os.path.islink(out_dir):
        print("ERROR: el destino es un enlace simbolico: %s" % out_dir)
        return 2
    planned_dirs, planned_files = _plan_output_paths(
        out_dir, {anim: len(images) for anim, images in anchored_by_anim.items()})
    for path in planned_dirs:
        if os.path.islink(path):
            print("ERROR: '%s' es un enlace simbolico; no se escribe nada" % path)
            return 2
    for path in planned_files:
        if os.path.islink(path):
            print("ERROR: '%s' es un enlace simbolico; no se escribe nada" % path)
            return 2

    os.makedirs(out_dir, exist_ok=True)
    root = os.path.realpath(out_dir)
    frame_count = 0
    for anim in sorted(ANIM_FRAMES):
        anim_dir = os.path.join(out_dir, anim)
        os.makedirs(anim_dir, exist_ok=True)
        # Segunda linea de defensa: aunque el pre-flight ya lo rechazo, un
        # `anim_dir` que resuelva fuera del destino se para aqui.
        if not _is_within(anim_dir, root):
            print("ERROR: '%s' resuelve fuera del destino (%s); no se escribe nada"
                  % (anim_dir, os.path.realpath(anim_dir)))
            return 2
        for idx, (width, height, pixels) in enumerate(anchored_by_anim[anim], 1):
            path = os.path.join(anim_dir, "%s_%02d.png" % (anim, idx))
            _write_png_atomic(path, width, height, bytearray(pixels))
            frame_count += 1

    strip_count = 0
    for anim in sorted(ANIM_FRAMES):
        frames = anchored_by_anim[anim]
        strip = strip_bytes(frames, CELL)
        path = os.path.join(out_dir, "%s_strip.png" % anim)
        _write_png_atomic(path, CELL * len(frames), CELL, bytearray(strip))
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
    if cmd == "selftest":
        return selftest()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
