#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Auditoria y normalizacion de packs de sprites de actor (skins).

Tool de las skins de los actores WALKER/BOSS definidos por ADR-006; el pack
no es exclusivo de los zombis de rango bajo. El pack canonico vive en
`assets/enemies/zombie/`:

    assets/enemies/zombie/<anim>/<anim>_NN.png   frames sueltos (fuente)
    assets/enemies/zombie/<anim>_strip.png        strip horizontal uniforme

El runtime materializa el strip como `AtlasTexture` y lo consume mediante
`SpriteFrames`: celdas de `CELL x CELL` px, celda N en `x = N*CELL`. Un strip
con celdas de ANCHO VARIABLE no es rebanable y rompe la animacion, asi que la
normalizacion es obligatoria, no opcional.

Subcomandos:
    audit <dir>                         Diagnostica un pack externo.
    import <dir> --out <destino>       Normaliza un pack externo.
                                       [--force] reemplaza; [--dry-run] no escribe.
    build                               Regenera los strips del proyecto.
    check                               Verifica el pack del proyecto (CI).
    selftest                            Autopruebas del importador (CI).

Regla de anclaje del proyecto: el bbox opaco de la UNION de todos los frames
se centra en la celda 64x64 y se aplica la MISMA traslacion a todos los frames.
Nunca se reencuadra un frame usando el bbox de su propio frame; asi el
personaje no patina entre frames ni entre animaciones.

Solo stdlib, igual que `tools/gen_art.py`.
"""

from __future__ import annotations

import contextlib
import errno
import hashlib
import io
import json
import os
import stat
import struct
import sys
import tempfile
import zlib

try:
    import fcntl
except ImportError:  # pragma: no cover - plataforma sin POSIX flock
    fcntl = None

try:
    import msvcrt
except ImportError:  # pragma: no cover - plataforma sin Windows locking
    msvcrt = None

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
    # El stream IDAT es independiente del IHDR: sin tope, un PNG de unas
    # decenas de bytes podria expandirse a cientos de MB antes de validar.
    expected_raw = height * (1 + width * bpp)
    decompressor = zlib.decompressobj()
    try:
        raw = decompressor.decompress(bytes(idat), expected_raw + 1)
    except zlib.error as exc:
        raise ValueError("stream IDAT corrupto: %s" % exc)
    if len(raw) != expected_raw:
        raise ValueError("stream IDAT excede el tamaño declarado por IHDR")
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


def _tree_fingerprint(root: str) -> dict:
    """Snapshot completo de rutas, tipos y contenido de un arbol.

    Incluye ficheros, directorios vacios y enlaces simbolicos. Asi una
    comparacion before/after detecta tanto contenido ausente como residuos
    de staging, backups o directorios que quedaron vacios.
    """
    if not os.path.lexists(root):
        return {}
    if os.path.islink(root):
        return {".": "symlink:%s" % os.readlink(root)}
    if not os.path.isdir(root):
        with open(root, "rb") as handle:
            return {".": "file:%s" % hashlib.sha256(handle.read()).hexdigest()}

    snapshot = {".": "dir"}
    for base, dirs, names in os.walk(root, topdown=True, followlinks=False):
        dirs.sort()
        names.sort()
        for name in list(dirs):
            path = os.path.join(base, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            if os.path.islink(path):
                snapshot[rel] = "symlink:%s" % os.readlink(path)
                dirs.remove(name)
            else:
                snapshot[rel] = "dir"
        for name in names:
            path = os.path.join(base, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            if os.path.islink(path):
                snapshot[rel] = "symlink:%s" % os.readlink(path)
            elif os.path.isdir(path):
                snapshot[rel] = "dir"
            else:
                with open(path, "rb") as handle:
                    snapshot[rel] = "file:%s" % hashlib.sha256(
                        handle.read()).hexdigest()
    return snapshot


# Linux expone los bind mounts en mountinfo incluso cuando comparten st_dev.
# La ruta se puede sustituir en pruebas para no depender de privilegios root.
_MOUNTINFO_PATH = "/proc/self/mountinfo"


def _transaction_checkpoint() -> None:
    """Seam de crash; entre operaciones debe quedar durable el estado."""
    return None


def _decode_mountinfo_path(value: str) -> str:
    """Decodifica los escapes octales de un campo de mountinfo."""
    return (value.replace("\\040", " ")
                 .replace("\\011", "\t")
                 .replace("\\012", "\n")
                 .replace("\\134", "\\"))


def _read_mount_points() -> set:
    """Devuelve los mountpoints visibles para este proceso."""
    points = set()
    try:
        with open(_MOUNTINFO_PATH, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                fields = line.split()
                if len(fields) < 5:
                    continue
                mount_point = os.path.realpath(_decode_mountinfo_path(fields[4]))
                points.add(mount_point)
    except (OSError, UnicodeError):
        pass
    return points


def _mount_point_below(path: str, mount_points: set) -> str | None:
    """Primer mountpoint igual a ``path`` o contenido dentro de el."""
    real_path = os.path.realpath(path)
    prefix = real_path.rstrip(os.sep) + os.sep
    for mount_point in sorted(mount_points):
        if mount_point == real_path or mount_point.startswith(prefix):
            return mount_point
    return None


def _find_mount_boundary(root: str) -> str | None:
    """Detecta una frontera de montaje dentro de ``root``.

    mountinfo cubre bind mounts del mismo ``st_dev``; ``st_dev`` e
    ``ismount`` cubren las demas fronteras y funcionan tambien si no se puede
    leer mountinfo.
    """
    if not os.path.lexists(root) or os.path.islink(root):
        return None
    try:
        root_stat = os.stat(root, follow_symlinks=False)
    except OSError:
        return None
    if not stat.S_ISDIR(root_stat.st_mode):
        return None

    mount_points = _read_mount_points()
    boundary = _mount_point_below(root, mount_points)
    if boundary is not None:
        return boundary

    for base, dirs, names in os.walk(root, topdown=True, followlinks=False):
        for name in list(dirs):
            path = os.path.join(base, name)
            try:
                child_stat = os.stat(path, follow_symlinks=False)
            except OSError:
                continue
            if stat.S_ISDIR(child_stat.st_mode):
                if child_stat.st_dev != root_stat.st_dev:
                    return path
                if os.path.ismount(path):
                    return path
                boundary = _mount_point_below(path, mount_points)
                if boundary is not None:
                    return boundary
            else:
                # Un symlink a un directorio no se sigue ni se cruza.
                dirs.remove(name)
        for name in names:
            path = os.path.join(base, name)
            try:
                child_stat = os.stat(path, follow_symlinks=False)
            except OSError:
                continue
            if stat.S_ISDIR(child_stat.st_mode):
                if child_stat.st_dev != root_stat.st_dev:
                    return path
                if os.path.ismount(path):
                    return path
                boundary = _mount_point_below(path, mount_points)
                if boundary is not None:
                    return boundary
    return None


def _safe_remove_dir_fd(dir_fd: int, path: str, root_dev: int) -> None:
    """Borra las entradas de un directorio abierto sin seguir symlinks."""
    for name in os.listdir(dir_fd):
        child_path = os.path.join(path, name)
        try:
            child_stat = os.stat(name, dir_fd=dir_fd, follow_symlinks=False)
        except FileNotFoundError:
            continue
        if not stat.S_ISDIR(child_stat.st_mode):
            os.unlink(name, dir_fd=dir_fd)
            continue

        boundary = _find_mount_boundary(child_path)
        if boundary is not None:
            raise OSError(errno.EXDEV,
                          "no se cruza la frontera de montaje '%s'" % boundary,
                          child_path)
        if child_stat.st_dev != root_dev:
            raise OSError(errno.EXDEV,
                          "el hijo pertenece a otro filesystem", child_path)

        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
        flags |= getattr(os, "O_NOFOLLOW", 0)
        child_fd = os.open(name, flags, dir_fd=dir_fd)
        try:
            opened_stat = os.fstat(child_fd)
            if opened_stat.st_dev != root_dev:
                raise OSError(errno.EXDEV,
                              "el directorio abierto pertenece a otro filesystem",
                              child_path)
            _safe_remove_dir_fd(child_fd, child_path, root_dev)
        finally:
            os.close(child_fd)
        os.rmdir(name, dir_fd=dir_fd)


def _safe_remove_tree(path: str) -> None:
    """Borra un arbol sin seguir symlinks ni cruzar mountpoints.

    Primero inspecciona el arbol completo. Si encuentra una frontera, falla
    sin borrar nada. Durante el borrado abre cada directorio con
    ``O_NOFOLLOW`` y comprueba ``st_dev`` antes de recursar.
    """
    boundary = _find_mount_boundary(path)
    if boundary is not None:
        raise OSError(errno.EXDEV,
                      "no se borra un arbol con frontera de montaje '%s'"
                      % boundary, path)

    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    root_fd = os.open(path, flags)
    try:
        root_stat = os.fstat(root_fd)
        _safe_remove_dir_fd(root_fd, path, root_stat.st_dev)
    finally:
        os.close(root_fd)
    os.rmdir(path)


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
         originales) de forma irreversible;
      7. se rechazan destinos descendientes y ancestros del origen incluso
         con `--force` (cada puerta se prueba de forma independiente);
      8. un alias del mismo directorio se rechaza cuando symlinks estan
         disponibles en la plataforma;
      9. un directorio planificado que ya es un fichero se rechaza en el
         pre-flight;
     10. un fallo de escritura intermedio devuelve rc=2 sin salida parcial;
     11. un destino no vacio con un frame obsoleto se rechaza por defecto;
     12. un fallo al publicar restaura el destino anterior de forma integra y
         no deja staging ni temporales;
     13. `--force` publica exactamente 33 frames y 8 strips, sin conservar
         frames obsoletos ni contenido ajeno;
     14. un fallo de limpieza posterior a publicar se distingue de un fallo
         anterior: la salida completa queda visible y no se hace rollback;
     15. se preservan el modo del destino, la creacion tardia del padre y la
         ausencia de escrituras del dry-run;
     16. se detectan fronteras de montaje y no se cruza al limpiar;
     17. un crash entre los dos renombres deja un journal durable y recovery
         restaura el destino anterior;
     18. el lock por destino y su fallback O_EXCL rechazan importadores
         concurrentes;
     19. recovery ocurre antes de validar el origen nuevo y restaura el
         backup aunque la siguiente entrada no exista;
     20. el journal v2 conserva `had_destination` y el manifest SHA-256
         exacto del staging ya escrito;
     21. un crash building/prepared sin destino previo se descarta de forma
         segura y permite una importacion limpia;
     22. JSON roto, Unicode invalido, version o tipos invalidos devuelven
         rc=2 sin traceback y conservan los artefactos;
     23. un destino presente que no coincide con el manifest falla cerrado y
         conserva tanto el destino como el backup;
     24. el dry-run no crea locks y rechaza una transaccion pendiente sin
         tocarla.
    """
    global _write_png_atomic
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
        before = _tree_fingerprint(source_pack)
        code = import_pack(source_pack, source_pack, force=True)
        if code != 2:
            failures.append("importar sobre el propio pack de origen debe "
                            "rechazarse (rc=2, hubo %d)" % code)
        after = _tree_fingerprint(source_pack)
        if before != after:
            changed = sorted(set(before) ^ set(after)) or \
                sorted(k for k in before if before[k] != after.get(k))
            failures.append("importar sobre el propio pack de origen lo "
                            "modifico: %s" % changed[:8])

        # 7. Un destino descendiente del origen se rechaza. Publicar dentro
        #    del pack de entrada lo modifica y deja una salida anidada.
        descendant_source = os.path.join(root, "pack_descendant")
        _write_synthetic_pack(descendant_source)
        descendant_out = os.path.join(descendant_source, "nested_out")
        descendant_before = _tree_fingerprint(descendant_source)
        code = import_pack(descendant_source, descendant_out, force=True)
        if code != 2:
            failures.append("un destino descendiente del origen debe rechazarse "
                            "(rc=2, hubo %d)" % code)
        if _tree_fingerprint(descendant_source) != descendant_before:
            failures.append("un destino descendiente modifico el pack de origen")
        if os.path.lexists(descendant_out):
            failures.append("un destino descendiente dejo salida parcial")

        # 8. Un destino ancestro del origen se rechaza. El caso inverso evita
        #    que la importacion se publique dentro del arbol que la contiene.
        ancestor_root = os.path.join(root, "ancestor_case")
        ancestor_source = os.path.join(ancestor_root, "pack")
        os.makedirs(ancestor_root, exist_ok=True)
        _write_synthetic_pack(ancestor_source)
        ancestor_before = _tree_fingerprint(ancestor_root)
        # `force=True` es esencial: sin el, el rechazo podria deberse solo
        # al destino no vacio y la puerta ancestra quedaria sin cobertura.
        code = import_pack(ancestor_source, ancestor_root, force=True)
        if code != 2:
            failures.append("un destino ancestro del origen debe rechazarse "
                            "(rc=2, hubo %d)" % code)
        if _tree_fingerprint(ancestor_root) != ancestor_before:
            failures.append("un destino ancestro fue modificado por la importacion")

        # 9. Un alias del mismo directorio tambien es el propio origen. En
        #    Linux el alias por symlink es viable y debe compararse por
        #    identidad real, no solo por cadena.
        alias_case = os.path.join(root, "alias_case")
        alias_source = os.path.join(alias_case, "pack")
        _write_synthetic_pack(alias_source)
        alias_out = os.path.join(alias_case, "alias_to_source")
        try:
            os.symlink(alias_source, alias_out, target_is_directory=True)
        except (OSError, NotImplementedError):
            pass  # symlinks no viables en esta plataforma
        else:
            alias_before = _tree_fingerprint(alias_source)
            alias_target_before = os.readlink(alias_out)
            code = import_pack(alias_source, alias_out, force=True)
            if code != 2:
                failures.append("un alias del origen debe rechazarse "
                                "(rc=2, hubo %d)" % code)
            if _tree_fingerprint(alias_source) != alias_before:
                failures.append("importar sobre un alias modifico el pack de origen")
            if os.readlink(alias_out) != alias_target_before:
                failures.append("importar sobre un alias modifico el enlace")

        # 10. El pre-flight de directorios planificados detecta que una
        #     animacion destino ya es un fichero, sin escribir nada.
        planned_case = os.path.join(root, "planned_file_case")
        planned_source = os.path.join(planned_case, "pack")
        planned_file_out = os.path.join(planned_case, "out")
        _write_synthetic_pack(planned_source)
        os.makedirs(planned_file_out, exist_ok=True)
        with open(os.path.join(planned_file_out, "idle"), "wb") as handle:
            handle.write(b"not a directory")
        planned_before = _tree_fingerprint(planned_case)
        try:
            code = import_pack(planned_source, planned_file_out, force=True)
        except OSError as exc:
            failures.append("un directorio planificado que es fichero no debe "
                            "propagar OSError (%s)" % exc)
            code = 2
        if code != 2:
            failures.append("un directorio planificado que es fichero debe "
                            "rechazarse (rc=2, hubo %d)" % code)
        if _tree_fingerprint(planned_case) != planned_before:
            failures.append("el rechazo por pre-flight modifico el arbol")

        # 11. Un fallo de escritura intermedio no deja salida parcial ni
        #     staging huerfano, y se convierte en un diagnostico rc=2.
        failed_write_case = os.path.join(root, "write_failure_case")
        failed_source = os.path.join(failed_write_case, "pack")
        failed_write_out = os.path.join(failed_write_case, "out")
        _write_synthetic_pack(failed_source)
        failed_before = _tree_fingerprint(failed_write_case)
        original_write = _write_png_atomic
        write_calls = {"count": 0}

        def failing_write(path, width, height, pixels):
            write_calls["count"] += 1
            if write_calls["count"] == 2:
                raise OSError(28, "fallo sintetico de escritura intermedia")
            return original_write(path, width, height, pixels)

        _write_png_atomic = failing_write
        try:
            code = import_pack(failed_source, failed_write_out)
        except OSError as exc:
            failures.append("un fallo de escritura no debe propagar OSError (%s)"
                            % exc)
            code = 2
        finally:
            _write_png_atomic = original_write
        if code != 2:
            failures.append("un fallo de escritura debe devolver rc=2 "
                            "(hubo %d)" % code)
        if _tree_fingerprint(failed_write_case) != failed_before:
            failures.append("un fallo de escritura modifico el origen o dejo "
                            "salida, staging o temporales")

        # 12. Un destino no vacio se rechaza por defecto. En particular no se
        #     conservan frames obsoletos extra ni se borran ficheros ajenos.
        stale_case = os.path.join(root, "stale_case")
        stale_source = os.path.join(stale_case, "pack")
        stale_out = os.path.join(stale_case, "out")
        _write_synthetic_pack(stale_source)
        os.makedirs(os.path.join(stale_out, "idle"), exist_ok=True)
        with open(os.path.join(stale_out, "idle", "idle_99.png"), "wb") as handle:
            handle.write(b"stale frame")
        stale_before = _tree_fingerprint(stale_case)
        code = import_pack(stale_source, stale_out)
        if code != 2:
            failures.append("un destino no vacio debe rechazarse por defecto "
                            "(rc=2, hubo %d)" % code)
        if _tree_fingerprint(stale_case) != stale_before:
            failures.append("el rechazo de destino no vacio modifico o borro "
                            "contenido ajeno")

        # 13. Publicacion transaccional: si falla el rename del staging
        #     despues de apartar el destino anterior, este se restaura
        #     integro y no quedan artefactos transitorios.
        rollback_root = os.path.join(root, "rollback_case")
        rollback_source = os.path.join(rollback_root, "pack")
        rollback_out = os.path.join(rollback_root, "destination")
        _write_synthetic_pack(rollback_source)
        os.makedirs(os.path.join(rollback_out, "idle"), exist_ok=True)
        with open(os.path.join(rollback_out, "old.txt"), "wb") as handle:
            handle.write(b"previous destination")
        rollback_before = _tree_fingerprint(rollback_root)
        rollback_out_before = _tree_fingerprint(rollback_out)
        original_replace = os.replace

        def fail_publish(src, dst):
            if (os.path.basename(src) in ("staging",) or
                    os.path.basename(src).startswith(".skinpack_stage_")) and \
                    os.path.abspath(dst) == os.path.abspath(rollback_out):
                raise OSError(errno.EXDEV, "fallo sintetico de publicacion")
            return original_replace(src, dst)

        os.replace = fail_publish
        try:
            code = import_pack(rollback_source, rollback_out, force=True)
        except OSError as exc:
            failures.append("el fallo de publicacion no debe propagar OSError (%s)"
                            % exc)
            code = 2
        finally:
            os.replace = original_replace
        if code != 2:
            failures.append("un fallo de publicacion debe devolver rc=2 "
                            "(hubo %d)" % code)
        if _tree_fingerprint(rollback_out) != rollback_out_before:
            failures.append("el rollback no restauro el destino anterior integro")
        if _tree_fingerprint(rollback_root) != rollback_before:
            failures.append("el rollback dejo staging, backup o temporales")

        # 14. --force publica exactamente 33 frames y 8 strips. Un destino
        #     previo con frames obsoletos y contenido ajeno se reemplaza por
        #     el mismo arbol limpio que produce una importacion normal.
        exact_root = os.path.join(root, "exact_force_case")
        exact_source = os.path.join(exact_root, "pack")
        clean_out = os.path.join(exact_root, "clean")
        forced_out = os.path.join(exact_root, "forced")
        _write_synthetic_pack(exact_source)
        code = import_pack(exact_source, clean_out)
        if code != 0:
            failures.append("no se pudo crear la referencia limpia (rc=%d)" % code)
        clean_fingerprint = _tree_fingerprint(clean_out)
        os.makedirs(os.path.join(forced_out, "idle"), exist_ok=True)
        os.makedirs(os.path.join(forced_out, "extra_dir"), exist_ok=True)
        with open(os.path.join(forced_out, "idle", "idle_99.png"), "wb") as handle:
            handle.write(b"stale frame")
        with open(os.path.join(forced_out, "foreign.bin"), "wb") as handle:
            handle.write(b"foreign")
        with open(os.path.join(forced_out, "extra_dir", "keep.txt"), "wb") as handle:
            handle.write(b"extra")
        code = import_pack(exact_source, forced_out, force=True)
        if code != 0:
            failures.append("--force debe publicar el pack exacto (rc=%d)" % code)
        expected_frames = {
            "%s/%s_%02d.png" % (anim, anim, index)
            for anim, count in ANIM_FRAMES.items()
            for index in range(1, count + 1)
        }
        expected_strips = {"%s_strip.png" % anim for anim in ANIM_FRAMES}
        actual_pngs = set(png_paths(forced_out))
        actual_frames = {path for path in actual_pngs if "/" in path}
        actual_strips = {path for path in actual_pngs if "/" not in path}
        if actual_pngs != expected_frames | expected_strips:
            failures.append("--force no publico el conjunto exacto de PNG")
        if len(actual_frames) != 33 or len(actual_strips) != 8:
            failures.append("--force debe publicar 33 frames y 8 strips exactos")
        if _tree_fingerprint(forced_out) != clean_fingerprint:
            failures.append("--force conservo frames obsoletos o contenido ajeno")
        transient = [name for name in os.listdir(exact_root)
                     if name.startswith(".skinpack_")]
        if transient:
            failures.append("--force dejo staging, backup o temporales: %s" % transient)

        # 15. Un fallo de limpieza POSTERIOR a la publicacion no se presenta
        #     como una importacion sin salida. El pack nuevo ya esta visible y
        #     no se deshace mediante rollback.
        cleanup_root = os.path.join(root, "post_publish_cleanup_case")
        cleanup_source = os.path.join(cleanup_root, "pack")
        cleanup_clean = os.path.join(cleanup_root, "clean")
        cleanup_out = os.path.join(cleanup_root, "destination")
        _write_synthetic_pack(cleanup_source)
        code = import_pack(cleanup_source, cleanup_clean)
        if code != 0:
            failures.append("no se pudo crear la referencia de cleanup (rc=%d)" % code)
        clean_fingerprint = _tree_fingerprint(cleanup_clean)
        os.makedirs(cleanup_out, exist_ok=True)
        with open(os.path.join(cleanup_out, "old.txt"), "wb") as handle:
            handle.write(b"previous destination")
        original_safe_remove = globals()["_safe_remove_tree"]

        def fail_backup_cleanup(path, *args, **kwargs):
            if os.path.basename(path) == "previous":
                raise OSError(errno.EACCES, "fallo sintetico al eliminar backup")
            return original_safe_remove(path, *args, **kwargs)

        globals()["_safe_remove_tree"] = fail_backup_cleanup
        diagnostics = io.StringIO()
        try:
            with contextlib.redirect_stdout(diagnostics):
                code = import_pack(cleanup_source, cleanup_out, force=True)
        except OSError as exc:
            failures.append("el fallo post-publicacion no debe propagar OSError (%s)"
                            % exc)
            code = 2
        finally:
            globals()["_safe_remove_tree"] = original_safe_remove
        diagnostic = diagnostics.getvalue()
        if code != 1:
            failures.append("un fallo de cleanup post-publicacion debe devolver "
                            "rc=1 (hubo %d)" % code)
        if "no se publico una salida parcial" in diagnostic:
            failures.append("el fallo post-publicacion afirmo que no hubo salida")
        if "public" not in diagnostic.lower() or "rollback" not in diagnostic.lower():
            failures.append("el fallo post-publicacion no explico la fase ni "
                            "la ausencia de rollback")
        if _tree_fingerprint(cleanup_out) != clean_fingerprint:
            failures.append("el fallo post-publicacion no dejo el pack completo visible")
        staging_left = [name for name in os.listdir(cleanup_root)
                        if name.startswith(".skinpack_stage_")]
        if staging_left:
            failures.append("el fallo post-publicacion dejo staging: %s" % staging_left)

        # 16. El padre se crea tras validar la entrada, el modo publicado es
        #     convencional y `--dry-run` no toca el filesystem.
        mode_root = os.path.join(root, "mode_and_parent_case")
        mode_source = os.path.join(mode_root, "pack")
        mode_out = os.path.join(mode_root, "missing", "nested", "out")
        _write_synthetic_pack(mode_source)
        mode_before = _tree_fingerprint(mode_root)
        cli_dry_out = os.path.join(mode_root, "cli_dry_run", "out")
        try:
            code = main(["skin_pack", "import", mode_source,
                         "--out", cli_dry_out, "--dry-run"])
        except TypeError as exc:
            failures.append("la CLI debe aceptar --dry-run (%s)" % exc)
            code = 2
        if code != 0:
            failures.append("la CLI dry-run debe devolver rc=0 (hubo %d)" % code)
        if _tree_fingerprint(mode_root) != mode_before:
            failures.append("la CLI dry-run toco el arbol de destino")
        try:
            code = import_pack(mode_source, mode_out, dry_run=True)
        except TypeError as exc:
            failures.append("import_pack debe aceptar dry_run=True (%s)" % exc)
            code = 2
        if code != 0:
            failures.append("un dry-run valido debe devolver rc=0 (hubo %d)" % code)
        if _tree_fingerprint(mode_root) != mode_before:
            failures.append("el dry-run toco el arbol de destino")
        code = import_pack(mode_source, mode_out)
        if code != 0:
            failures.append("el importador debe crear el padre inexistente "
                            "(rc=%d)" % code)
        if not os.path.isdir(os.path.dirname(mode_out)):
            failures.append("el padre inexistente no fue creado")
        else:
            root_mode = stat.S_IMODE(os.stat(mode_out).st_mode)
            if root_mode != 0o755:
                failures.append("el destino publicado tiene modo anomalo %o"
                                % root_mode)
            for path in _tree_files(mode_out):
                file_mode = stat.S_IMODE(os.stat(path).st_mode)
                if file_mode != 0o644:
                    failures.append("el frame publicado tiene modo anomalo %o: %s"
                                    % (file_mode, path))

        preserved_out = os.path.join(mode_root, "preserved_mode")
        os.makedirs(preserved_out, exist_ok=True)
        os.chmod(preserved_out, 0o751)
        code = import_pack(mode_source, preserved_out, force=True)
        if code != 0:
            failures.append("no se pudo reemplazar el destino con modo previo "
                            "(rc=%d)" % code)
        elif stat.S_IMODE(os.stat(preserved_out).st_mode) != 0o751:
            failures.append("el modo previo del destino no se conservo")

        # 17. Una frontera de montaje simulada se detecta antes de publicar y
        #     el borrado seguro no cruza esa frontera.
        mount_root = os.path.join(root, "mount_boundary_case")
        mount_source = os.path.join(mount_root, "pack")
        mount_out = os.path.join(mount_root, "destination")
        mount_point = os.path.join(mount_out, "mounted")
        _write_synthetic_pack(mount_source)
        os.makedirs(mount_point, exist_ok=True)
        external_file = os.path.join(mount_root, "external.txt")
        with open(external_file, "wb") as handle:
            handle.write(b"external data")
        fake_mountinfo = os.path.join(mount_root, "mountinfo")
        with open(fake_mountinfo, "w", encoding="utf-8") as handle:
            handle.write("36 25 0:32 / %s rw,relatime - ext4 /dev/test rw\n"
                         % mount_point)
        original_mountinfo = globals().get("_MOUNTINFO_PATH")
        globals()["_MOUNTINFO_PATH"] = fake_mountinfo
        try:
            mount_before = _tree_fingerprint(mount_root)
            code = import_pack(mount_source, mount_out, force=True)
            if code != 2:
                failures.append("un destino con frontera de montaje debe rechazarse "
                                "(rc=2, hubo %d)" % code)
            if _tree_fingerprint(mount_root) != mount_before:
                failures.append("la frontera de montaje permitio modificar el arbol")
            with open(external_file, "rb") as handle:
                if handle.read() != b"external data":
                    failures.append("el borrado seguro cruzo la frontera simulada")
            safe_remove = globals().get("_safe_remove_tree")
            if safe_remove is None:
                failures.append("falta el helper de borrado seguro")
            else:
                try:
                    safe_remove(mount_out)
                except OSError:
                    pass
                else:
                    failures.append("el borrado seguro no detecto la frontera")
                if _tree_fingerprint(mount_root) != mount_before:
                    failures.append("el borrado seguro modifico el arbol con frontera")
        finally:
            if original_mountinfo is None:
                globals().pop("_MOUNTINFO_PATH", None)
            else:
                globals()["_MOUNTINFO_PATH"] = original_mountinfo

        # 18. Un crash simulado entre los dos renombres deja estado durable;
        #     la siguiente importacion recupera el destino anterior.
        crash_root = os.path.join(root, "crash_recovery_case")
        crash_source = os.path.join(crash_root, "pack")
        crash_out = os.path.join(crash_root, "destination")
        _write_synthetic_pack(crash_source)
        os.makedirs(crash_out, exist_ok=True)
        with open(os.path.join(crash_out, "old.txt"), "wb") as handle:
            handle.write(b"previous destination")
        crash_before = _tree_fingerprint(crash_out)
        checkpoint = globals().get("_transaction_checkpoint")
        if checkpoint is None:
            failures.append("falta el seam de checkpoint transaccional")
        else:
            class SimulatedCrash(BaseException):
                pass

            def crash_after_backup_move():
                raise SimulatedCrash("crash sintetico tras mover el backup")

            globals()["_transaction_checkpoint"] = crash_after_backup_move
            try:
                import_pack(crash_source, crash_out, force=True)
            except SimulatedCrash:
                pass
            except Exception as exc:
                failures.append("el seam de crash lanzo una excepcion inesperada: %s"
                                % exc)
            else:
                failures.append("el seam de crash no fue ejecutado")
            finally:
                globals()["_transaction_checkpoint"] = checkpoint
            if os.path.lexists(crash_out):
                failures.append("el crash no reprodujo el destino ausente")
            empty_source = os.path.join(crash_root, "empty_source")
            os.makedirs(empty_source, exist_ok=True)
            code = import_pack(empty_source, crash_out, force=True)
            if code != 2:
                failures.append("la recuperacion seguida de un origen invalido "
                                "debe devolver rc=2 (hubo %d)" % code)
            if _tree_fingerprint(crash_out) != crash_before:
                failures.append("la recuperacion no restauro el destino anterior")
            transactions = [name for name in os.listdir(crash_root)
                            if name.startswith(".skinpack_txn_")]
            if transactions:
                failures.append("la recuperacion no limpio la transaccion: %s"
                                % transactions)

        # 19. El lock por destino impide dos importadores concurrentes.
        lock_root = os.path.join(root, "lock_case")
        lock_source = os.path.join(lock_root, "pack")
        lock_out = os.path.join(lock_root, "destination")
        _write_synthetic_pack(lock_source)
        os.makedirs(lock_out, exist_ok=True)
        lock_before = _tree_fingerprint(lock_root)
        destination_lock = globals().get("_destination_lock")
        if destination_lock is None:
            failures.append("falta el lock por destino")
        else:
            with destination_lock(lock_out):
                code = import_pack(lock_source, lock_out, force=True)
            if code != 2:
                failures.append("un importador concurrente debe rechazarse "
                                "(rc=2, hubo %d)" % code)
            if _tree_fingerprint(lock_root) != lock_before:
                failures.append("el importador concurrente toco el destino")

        # 20. El fallback de lock sin fcntl/msvcrt tambien evita dos
        #     importadores concurrentes.
        fallback_root = os.path.join(root, "fallback_lock_case")
        fallback_source = os.path.join(fallback_root, "pack")
        fallback_out = os.path.join(fallback_root, "destination")
        _write_synthetic_pack(fallback_source)
        os.makedirs(fallback_out, exist_ok=True)
        fallback_before = _tree_fingerprint(fallback_root)
        original_fcntl = globals().get("fcntl")
        original_msvcrt = globals().get("msvcrt")
        globals()["fcntl"] = None
        globals()["msvcrt"] = None
        try:
            try:
                with destination_lock(fallback_out):
                    code = import_pack(fallback_source, fallback_out, force=True)
            except Exception as exc:
                failures.append("el fallback de lock fallo: %s" % exc)
                code = 2
        finally:
            if original_fcntl is None:
                globals().pop("fcntl", None)
            else:
                globals()["fcntl"] = original_fcntl
            if original_msvcrt is None:
                globals().pop("msvcrt", None)
            else:
                globals()["msvcrt"] = original_msvcrt
        if code != 2:
            failures.append("el fallback de lock debe rechazar concurrencia "
                            "(rc=2, hubo %d)" % code)
        if _tree_fingerprint(fallback_root) != fallback_before:
            failures.append("el fallback de lock toco el destino")

        # 21. La recuperacion ocurre ANTES de validar el origen nuevo. Un
        #     crash tras apartar el backup debe restaurar el destino anterior
        #     aunque la siguiente invocacion use un origen inexistente. El
        #     journal ademas conserva version, had_destination y el manifest
        #     SHA-256 exacto del staging ya escrito.
        recovery_root = os.path.join(root, "recovery_before_source_case")
        recovery_source = os.path.join(recovery_root, "pack")
        recovery_out = os.path.join(recovery_root, "destination")
        _write_synthetic_pack(recovery_source)
        os.makedirs(recovery_out, exist_ok=True)
        with open(os.path.join(recovery_out, "old.txt"), "wb") as handle:
            handle.write(b"previous destination")
        recovery_checkpoint = globals().get("_transaction_checkpoint")

        class RecoveryCrash(BaseException):
            pass

        def crash_after_recovery_backup_move():
            raise RecoveryCrash("crash sintetico tras mover el backup")

        globals()["_transaction_checkpoint"] = crash_after_recovery_backup_move
        try:
            import_pack(recovery_source, recovery_out, force=True)
        except RecoveryCrash:
            pass
        except Exception as exc:
            failures.append("el seam de recovery lanzo una excepcion inesperada: %s"
                            % exc)
        else:
            failures.append("el seam de recovery no fue ejecutado")
        finally:
            globals()["_transaction_checkpoint"] = recovery_checkpoint

        recovery_paths = _transaction_paths(recovery_out)
        try:
            with open(recovery_paths["state"], "r", encoding="utf-8") as handle:
                recovery_state = json.load(handle)
        except (OSError, ValueError) as exc:
            failures.append("el journal de recovery no es legible: %s" % exc)
            recovery_state = {}
        if recovery_state.get("version") != 2:
            failures.append("el journal de recovery no tiene la version 2")
        if recovery_state.get("had_destination") is not True:
            failures.append("el journal de recovery no conserva had_destination=true")
        if recovery_state.get("phase") != "moving_old":
            failures.append("el journal de recovery no conserva la fase moving_old")
        expected_outputs = sorted(_expected_output_pngs())
        if recovery_state.get("expected_pngs") != expected_outputs:
            failures.append("el journal de recovery no conserva expected_pngs")
        recovery_manifest = recovery_state.get("manifest")
        if not isinstance(recovery_manifest, dict) or \
                sorted(recovery_manifest) != expected_outputs:
            failures.append("el journal de recovery no conserva el manifest completo")
        else:
            actual_manifest = {}
            for relative in expected_outputs:
                staged_path = os.path.join(recovery_paths["staging"], relative)
                try:
                    with open(staged_path, "rb") as handle:
                        actual_manifest[relative] = hashlib.sha256(
                            handle.read()).hexdigest()
                except OSError as exc:
                    failures.append("no se pudo verificar el manifest del staging: %s"
                                    % exc)
                    actual_manifest = {}
                    break
            if actual_manifest and actual_manifest != recovery_manifest:
                failures.append("el manifest del journal no coincide con los bytes "
                                "del staging")
        if not os.path.lexists(os.path.join(recovery_paths["previous"], "old.txt")):
            failures.append("el crash no dejo el backup integro")
        missing_recovery_source = os.path.join(recovery_root, "SOURCE_INEXISTENTE")
        code = import_pack(missing_recovery_source, recovery_out, force=True)
        if code != 2:
            failures.append("un origen inexistente tras un crash debe devolver rc=2 "
                            "(hubo %d)" % code)
        try:
            with open(os.path.join(recovery_out, "old.txt"), "rb") as handle:
                restored_bytes = handle.read()
        except OSError:
            restored_bytes = None
        if restored_bytes != b"previous destination":
            failures.append("la recuperacion no restauro el destino antes de "
                            "validar el origen nuevo")

        # 22. Un crash en building/prepared sin destino previo es descartable:
        #     had_destination=false demuestra que todavia no se publico nada.
        for recovery_phase in ("building", "prepared"):
            discard_root = os.path.join(root, "discard_%s_case" % recovery_phase)
            discard_source = os.path.join(discard_root, "pack")
            discard_out = os.path.join(discard_root, "destination")
            _write_synthetic_pack(discard_source)
            discard_paths = _transaction_paths(discard_out)
            os.makedirs(discard_paths["dir"], exist_ok=True)
            os.makedirs(discard_paths["staging"], exist_ok=True)
            discard_expected = sorted(_expected_output_pngs())
            discard_manifest = {}
            if recovery_phase == "prepared":
                for relative in discard_expected:
                    staged_path = os.path.join(discard_paths["staging"], relative)
                    os.makedirs(os.path.dirname(staged_path), exist_ok=True)
                    staged_bytes = relative.encode("utf-8")
                    with open(staged_path, "wb") as handle:
                        handle.write(staged_bytes)
                    discard_manifest[relative] = hashlib.sha256(
                        staged_bytes).hexdigest()
            _write_transaction_state(discard_paths["dir"], {
                "version": 2,
                "dest": discard_paths["dest"],
                "had_destination": False,
                "phase": recovery_phase,
                "expected_pngs": discard_expected,
                "manifest": discard_manifest,
            })
            code = import_pack(discard_source, discard_out, force=True)
            if code != 0:
                failures.append("un crash %s sin destino previo debe permitir una "
                                "importacion limpia (rc=%d)" % (recovery_phase, code))
            if os.path.lexists(discard_paths["dir"]):
                failures.append("un crash %s sin destino previo no se descarto"
                                % recovery_phase)

        # 23. Un journal corrupto, no UTF-8, o con version/tipos invalidos se
        #     traduce a rc=2 sin traceback y conserva todos los artefactos.
        invalid_states = (
            ("json_corrupto", b"{broken"),
            ("unicode_invalido", b"\xff\xfe"),
            ("version_invalida", {"version": "dos"}),
            ("version_nula", {"version": None}),
            ("tipos_invalidos", {
                "had_destination": "no",
                "phase": [],
                "expected_pngs": "ninguno",
                "manifest": [],
            }),
        )
        for invalid_name, invalid_payload in invalid_states:
            invalid_root = os.path.join(root, "invalid_%s_case" % invalid_name)
            invalid_source = os.path.join(invalid_root, "pack")
            invalid_out = os.path.join(invalid_root, "destination")
            _write_synthetic_pack(invalid_source)
            invalid_paths = _transaction_paths(invalid_out)
            os.makedirs(invalid_paths["dir"], exist_ok=True)
            if isinstance(invalid_payload, dict):
                invalid_state = {
                    "version": 2,
                    "dest": invalid_paths["dest"],
                    "had_destination": False,
                    "phase": "building",
                    "expected_pngs": sorted(_expected_output_pngs()),
                    "manifest": {},
                }
                invalid_state.update(invalid_payload)
                invalid_payload = json.dumps(invalid_state).encode("utf-8")
            with open(invalid_paths["state"], "wb") as handle:
                handle.write(invalid_payload)
            invalid_before = _tree_fingerprint(invalid_root)
            propagated = False
            try:
                code = import_pack(invalid_source, invalid_out, force=True)
            except Exception as exc:
                propagated = True
                code = 99
                failures.append("un journal %s propagó %s" %
                                (invalid_name, type(exc).__name__))
            if propagated:
                code = 99
            if code != 2:
                failures.append("un journal %s debe devolver rc=2 (hubo %d)" %
                                (invalid_name, code))
            if _tree_fingerprint(invalid_root) != invalid_before:
                failures.append("un journal %s no conservo los artefactos" %
                                invalid_name)

        # Un journal que declara had_destination=true pero no conserva ni el
        # destino ni el backup es inequivocamente ambiguo: no se puede
        # afirmar que no se publico y todos los artefactos deben quedar intactos.
        ambiguous_root = os.path.join(root, "ambiguous_missing_both_case")
        ambiguous_source = os.path.join(ambiguous_root, "pack")
        ambiguous_out = os.path.join(ambiguous_root, "destination")
        _write_synthetic_pack(ambiguous_source)
        ambiguous_paths = _transaction_paths(ambiguous_out)
        os.makedirs(ambiguous_paths["dir"], exist_ok=True)
        os.makedirs(ambiguous_paths["staging"], exist_ok=True)
        ambiguous_expected = sorted(_expected_output_pngs())
        _write_transaction_state(ambiguous_paths["dir"], {
            "version": 2,
            "dest": ambiguous_paths["dest"],
            "had_destination": True,
            "phase": "old_moved",
            "expected_pngs": ambiguous_expected,
            "manifest": {relative: "0" * 64 for relative in ambiguous_expected},
        })
        ambiguous_before = _tree_fingerprint(ambiguous_root)
        code = import_pack(ambiguous_source, ambiguous_out, force=True)
        if code != 2:
            failures.append("had_destination=true sin destino ni backup debe "
                            "devolver rc=2 (hubo %d)" % code)
        if _tree_fingerprint(ambiguous_root) != ambiguous_before:
            failures.append("un estado ambiguo sin destino ni backup no conservo "
                            "los artefactos")

        # 24. La publicacion se identifica por bytes exactos. Un destino con
        #     los nombres correctos pero otro contenido no se puede publicar:
        #     se conservan tanto el destino inesperado como el backup intacto.
        manifest_root = os.path.join(root, "manifest_mismatch_case")
        manifest_source = os.path.join(manifest_root, "pack")
        manifest_clean = os.path.join(manifest_root, "clean")
        manifest_out = os.path.join(manifest_root, "destination")
        _write_synthetic_pack(manifest_source)
        code = import_pack(manifest_source, manifest_clean)
        if code != 0:
            failures.append("no se pudo crear la referencia del manifest (rc=%d)" % code)
        manifest_expected = sorted(_expected_output_pngs())
        manifest_values = {}
        for relative in manifest_expected:
            with open(os.path.join(manifest_clean, relative), "rb") as handle:
                manifest_values[relative] = hashlib.sha256(handle.read()).hexdigest()
        manifest_paths = _transaction_paths(manifest_out)
        os.makedirs(manifest_paths["dir"], exist_ok=True)
        os.makedirs(manifest_paths["previous"], exist_ok=True)
        with open(os.path.join(manifest_paths["previous"], "old.txt"), "wb") as handle:
            handle.write(b"must survive")
        os.makedirs(manifest_out, exist_ok=True)
        for relative in manifest_expected:
            wrong_path = os.path.join(manifest_out, relative)
            os.makedirs(os.path.dirname(wrong_path), exist_ok=True)
            with open(wrong_path, "wb") as handle:
                handle.write(b"wrong bytes")
        _write_transaction_state(manifest_paths["dir"], {
            "version": 2,
            "dest": manifest_paths["dest"],
            "had_destination": True,
            "phase": "published",
            "expected_pngs": manifest_expected,
            "manifest": manifest_values,
        })
        code = import_pack(manifest_source, manifest_out, force=True)
        if code != 2:
            failures.append("un destino publicado con bytes distintos debe rechazarse "
                            "(rc=%d)" % code)
        if not os.path.isfile(os.path.join(manifest_paths["previous"], "old.txt")):
            failures.append("el backup se elimino ante un destino con bytes distintos")
        wrong_survived = True
        for relative in manifest_expected:
            with open(os.path.join(manifest_out, relative), "rb") as handle:
                if handle.read() != b"wrong bytes":
                    wrong_survived = False
                    break
        if not wrong_survived:
            failures.append("el destino inesperado no se conservo")

        # 25. El dry-run es estrictamente read-only: no crea el namespace global
        #     de locks y rechaza una transaccion pendiente sin tocarla.
        dry_lock_root = os.path.join(root, "dry_lock_tmp")
        os.makedirs(dry_lock_root, exist_ok=True)
        dry_out = os.path.join(root, "dry_read_only_out")
        original_gettempdir = tempfile.gettempdir
        tempfile.gettempdir = lambda: dry_lock_root
        try:
            code = import_pack(valid_pack, dry_out, dry_run=True)
        finally:
            tempfile.gettempdir = original_gettempdir
        if code != 0:
            failures.append("el dry-run read-only debe devolver rc=0 (hubo %d)" % code)
        if os.path.lexists(os.path.join(dry_lock_root, "skinpack-locks")):
            failures.append("el dry-run creo el namespace global de locks")

        pending_dry_root = os.path.join(root, "pending_dry_case")
        pending_dry_source = os.path.join(pending_dry_root, "pack")
        pending_dry_out = os.path.join(pending_dry_root, "destination")
        _write_synthetic_pack(pending_dry_source)
        pending_dry_paths = _transaction_paths(pending_dry_out)
        os.makedirs(pending_dry_paths["dir"], exist_ok=True)
        _write_transaction_state(pending_dry_paths["dir"], {
            "version": 2,
            "dest": pending_dry_paths["dest"],
            "had_destination": False,
            "phase": "building",
            "expected_pngs": sorted(_expected_output_pngs()),
            "manifest": {},
        })
        pending_dry_before = _tree_fingerprint(pending_dry_root)
        code = import_pack(pending_dry_source, pending_dry_out, dry_run=True)
        if code != 2:
            failures.append("el dry-run debe rechazar una transaccion pendiente "
                            "(rc=%d)" % code)
        if _tree_fingerprint(pending_dry_root) != pending_dry_before:
            failures.append("el dry-run toco una transaccion pendiente")

    print("SKIN_PACK_SELFTEST failures=%d" % len(failures))
    for failure in failures:
        print("  - %s" % failure)
    return 1 if failures else 0


# ---------------------------------------------------------------------------
# Importacion de packs externos
# ---------------------------------------------------------------------------

def _is_strictly_within(path: str, root: str) -> bool:
    """True si ``path`` esta estrictamente dentro de ``root``.

    La exclusion de la propia ruta mantiene independientes las puertas
    "mismo lugar", "descendiente" y "ancestro": cada una puede(mutarse) sin
    quedar tapada por otra.
    """
    try:
        real_path = os.path.realpath(path)
        real_root = os.path.realpath(root)
        return (real_path != real_root and
                os.path.commonpath([real_path, real_root]) == real_root)
    except (OSError, ValueError):
        return False


def _is_within(path: str, root: str) -> bool:
    """True si ``path`` esta dentro de ``root`` tras resolver enlaces.

    ``commonpath`` lanza ``ValueError`` cuando las rutas pertenecen a
    volumenes distintos. En ese caso no existe contencion y se devuelve
    False; nunca se deben comparar rutas de volumenes diferentes como si
    fueran prefijos de texto.
    """
    try:
        real_path = os.path.realpath(path)
        real_root = os.path.realpath(root)
        return os.path.commonpath([real_path, real_root]) == real_root
    except (OSError, ValueError):
        return False


def _same_location(left: str, right: str) -> bool:
    """True si dos rutas designan el mismo objeto del sistema de ficheros.

    ``samefile`` es mas fuerte que comparar cadenas, pero solo funciona si
    ambas rutas existen y puede lanzar OSError para rutas distintas o de
    volumenes diferentes. ``realpath`` cubre los alias que aun no existen.
    """
    try:
        if os.path.samefile(left, right):
            return True
    except (OSError, ValueError):
        pass
    try:
        return os.path.realpath(left) == os.path.realpath(right)
    except (OSError, ValueError):
        return False


class _PostPublishCleanupError(OSError):
    """La salida ya se publico; solo fallo una limpieza posterior."""

    def __init__(self, out_dir: str, cause: BaseException):
        errno_value = getattr(cause, "errno", None)
        super().__init__(
            errno_value,
            "la salida se publico correctamente en '%s', pero fallo la "
            "limpieza posterior: %s" % (out_dir, cause))
        self.out_dir = out_dir


def _fsync_directory(path: str) -> None:
    """Sincroniza un directorio cuando el filesystem lo soporta."""
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    try:
        fd = os.open(path, flags)
    except OSError:
        return
    try:
        try:
            os.fsync(fd)
        except OSError as exc:
            if exc.errno not in (errno.EINVAL, errno.ENOTSUP,
                                 getattr(errno, "EOPNOTSUPP", errno.EINVAL)):
                raise
    finally:
        os.close(fd)


def _transaction_paths(out_dir: str) -> dict:
    """Rutas deterministas de la transaccion sibling de un destino."""
    absolute = os.path.realpath(os.path.abspath(out_dir))
    parent = os.path.dirname(absolute)
    key = hashlib.sha256(absolute.encode("utf-8")).hexdigest()[:20]
    transaction_dir = os.path.join(parent, ".skinpack_txn_%s" % key)
    return {
        "dest": absolute,
        "parent": parent,
        "dir": transaction_dir,
        "staging": os.path.join(transaction_dir, "staging"),
        "previous": os.path.join(transaction_dir, "previous"),
        "state": os.path.join(transaction_dir, "state.json"),
    }


def _expected_output_pngs() -> set:
    expected = set()
    for anim, count in ANIM_FRAMES.items():
        for index in range(1, count + 1):
            expected.add("%s/%s_%02d.png" % (anim, anim, index))
        expected.add("%s_strip.png" % anim)
    return expected


_TRANSACTION_VERSION = 2
_TRANSACTION_PHASES = {"building", "prepared", "moving_old", "old_moved",
                       "published"}


def _write_transaction_state(transaction_dir: str, state: dict) -> None:
    """Escribe y sincroniza el estado durable de una transaccion."""
    state_path = os.path.join(transaction_dir, "state.json")
    descriptor, temporary = tempfile.mkstemp(prefix=".state_", dir=transaction_dir)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(state, handle, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, state_path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
    _fsync_directory(transaction_dir)


class _RecoveryError(OSError):
    """El journal o la transaccion pendiente no permiten decidir con seguro."""


def _read_transaction_state(transaction_dir: str) -> dict | None:
    """Lee y valida el journal durable de una transaccion.

    Un journal ausente solo es valido si no existe una transaccion; quien
    llama decide. JSON roto, texto no UTF-8 y schemas invalidos se traducen
    a ``OSError`` controlado para que la CLI termine con rc=2, nunca con un
    traceback. Los journals sin ``version`` se tratan como legado y solo se
    admiten en el caso segura de ``building/prepared`` sin destino previo.
    """
    state_path = os.path.join(transaction_dir, "state.json")
    try:
        state_stat = os.lstat(state_path)
    except FileNotFoundError:
        return None
    except OSError as exc:
        raise _RecoveryError(errno.EIO,
                             "no se pudo inspeccionar el journal: %s" % exc,
                             state_path) from exc
    if not stat.S_ISREG(state_stat.st_mode):
        raise _RecoveryError(errno.EIO,
                             "el journal no es un fichero regular", state_path)
    try:
        with open(state_path, "r", encoding="utf-8") as handle:
            state = json.load(handle)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise _RecoveryError(
            errno.EIO,
            "estado de transaccion corrupto (%s): %s" % (state_path, exc),
            state_path,
        ) from None
    except OSError as exc:
        raise _RecoveryError(errno.EIO,
                             "no se pudo leer el journal: %s" % exc,
                             state_path) from exc

    if not isinstance(state, dict):
        raise _RecoveryError(errno.EIO,
                             "estado de transaccion invalido", state_path)

    dest = state.get("dest")
    phase = state.get("phase")
    expected = state.get("expected_pngs")
    if not isinstance(dest, str) or not dest:
        raise _RecoveryError(errno.EIO,
                             "el destino del journal es invalido", state_path)
    if not isinstance(phase, str):
        raise _RecoveryError(errno.EIO,
                             "la fase del journal es invalida", state_path)
    if (not isinstance(expected, list) or
            any(not isinstance(item, str) for item in expected) or
            len(expected) != len(set(expected)) or
            set(expected) != _expected_output_pngs()):
        raise _RecoveryError(errno.EIO,
                             "expected_pngs del journal es invalido", state_path)

    if "had_destination" in state and type(state["had_destination"]) is not bool:
        raise _RecoveryError(errno.EIO,
                             "had_destination del journal es invalido", state_path)
    manifest = state.get("manifest", {})
    if not isinstance(manifest, dict):
        raise _RecoveryError(errno.EIO,
                             "el manifest del journal es invalido", state_path)
    for relative, digest in manifest.items():
        if (not isinstance(relative, str) or
                not isinstance(digest, str) or len(digest) != 64 or
                any(character not in "0123456789abcdef" for character in digest)):
            raise _RecoveryError(errno.EIO,
                                 "el manifest del journal contiene un hash invalido",
                                 state_path)

    if "version" not in state:
        # Solo se conserva compatibilidad de lectura segura con journals
        # legacy de building/prepared. Las fases de publicacion exigen el
        # manifest v2 y fallan cerrados mas abajo.
        return state
    version = state["version"]
    if type(version) is not int or version != _TRANSACTION_VERSION:
        raise _RecoveryError(
            errno.EIO,
            "version de transaccion no soportada: %r" % (version,),
            state_path,
        )
    if type(state.get("had_destination")) is not bool:
        raise _RecoveryError(errno.EIO,
                             "had_destination del journal es invalido", state_path)
    if phase not in _TRANSACTION_PHASES:
        raise _RecoveryError(errno.EIO,
                             "fase de transaccion desconocida: %s" % phase,
                             state_path)
    if phase == "building":
        if manifest:
            raise _RecoveryError(errno.EIO,
                                 "building no puede tener un manifest publicado",
                                 state_path)
    elif set(manifest) != set(expected):
        raise _RecoveryError(errno.EIO,
                             "el manifest del journal no cubre expected_pngs",
                             state_path)
    if "destination_mode" in state:
        mode = state["destination_mode"]
        if type(mode) is not int or not 0 <= mode <= 0o7777:
            raise _RecoveryError(errno.EIO,
                                 "destination_mode del journal es invalido", state_path)
    return state


@contextlib.contextmanager
def _destination_lock(out_dir: str):
    """Lock no bloqueante y por destino, con backend por plataforma."""
    absolute = os.path.realpath(os.path.abspath(out_dir))
    key = hashlib.sha256(absolute.encode("utf-8")).hexdigest()[:20]
    lock_dir = os.path.join(tempfile.gettempdir(), "skinpack-locks")
    os.makedirs(lock_dir, mode=0o700, exist_ok=True)

    if fcntl is not None:
        lock_path = os.path.join(lock_dir, "%s.lock" % key)
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        acquired = False
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                acquired = True
            except (BlockingIOError, OSError) as exc:
                if (isinstance(exc, BlockingIOError) or
                        getattr(exc, "errno", None) in (errno.EACCES,
                                                       errno.EAGAIN)):
                    yield False
                    return
                raise
            yield True
        finally:
            if acquired:
                fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)
        return

    if msvcrt is not None:
        lock_path = os.path.join(lock_dir, "%s.winlock" % key)
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        acquired = False
        try:
            if os.fstat(fd).st_size == 0:
                os.write(fd, b"0")
            os.lseek(fd, 0, os.SEEK_SET)
            try:
                msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
                acquired = True
            except OSError as exc:
                if getattr(exc, "errno", None) in (
                        errno.EACCES, errno.EAGAIN,
                        getattr(errno, "EDEADLK", errno.EACCES)):
                    yield False
                    return
                raise
            yield True
        finally:
            if acquired:
                try:
                    os.lseek(fd, 0, os.SEEK_SET)
                    msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
                except OSError:
                    pass
            os.close(fd)
        return

    # Ultimo recurso coherente: lock atomico O_CREAT|O_EXCL. El fichero
    # incluye el PID y un lock de un proceso muerto se puede recuperar.
    lock_path = os.path.join(lock_dir, "%s.excl.lock" % key)
    fd = None
    for _attempt in (0, 1):
        try:
            fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600)
            break
        except FileExistsError:
            try:
                with open(lock_path, "r", encoding="ascii") as handle:
                    owner = int(handle.read().strip() or "0")
            except (OSError, ValueError):
                owner = 0
            alive = False
            if owner <= 0:
                # El fichero se acaba de crear pero su PID aun no se ha
                # escrito: tratarlo como ocupado evita una carrera en la que
                # un segundo proceso lo robe.
                alive = True
            else:
                try:
                    os.kill(owner, 0)
                    alive = True
                except ProcessLookupError:
                    alive = False
                except OSError:
                    alive = True
            if alive or _attempt:
                yield False
                return
            try:
                os.unlink(lock_path)
            except FileNotFoundError:
                pass
    if fd is None:
        yield False
        return
    try:
        os.write(fd, str(os.getpid()).encode("ascii"))
        yield True
    finally:
        os.close(fd)
        try:
            os.unlink(lock_path)
        except FileNotFoundError:
            pass


def _sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise OSError(errno.EIO, "el fichero del manifest no es regular", path)
        with os.fdopen(descriptor, "rb", closefd=False) as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
    finally:
        os.close(descriptor)
    return digest.hexdigest()


def _output_tree_entries(root: str) -> tuple[set, set] | None:
    """Devuelve (ficheros, directorios) sin seguir enlaces, o None si es inseguro."""
    if not os.path.isdir(root) or os.path.islink(root):
        return None
    files = set()
    directories = set()

    def raise_walk_error(exc: OSError) -> None:
        raise exc

    for base, dirnames, filenames in os.walk(root, topdown=True,
                                             followlinks=False,
                                             onerror=raise_walk_error):
        for name in list(dirnames):
            path = os.path.join(base, name)
            if os.path.islink(path):
                return None
            relative = os.path.relpath(path, root).replace(os.sep, "/")
            directories.add(relative)
        for name in filenames:
            path = os.path.join(base, name)
            if os.path.islink(path) or not os.path.isfile(path):
                return None
            relative = os.path.relpath(path, root).replace(os.sep, "/")
            files.add(relative)
    return files, directories


def _expected_output_directories(expected: set) -> set:
    return {os.path.dirname(relative) for relative in expected
            if os.path.dirname(relative)}


def _manifest_for_output(root: str, expected: set) -> dict:
    """Calcula el manifest SHA-256 del arbol exacto de PNG publicado."""
    entries = _output_tree_entries(root)
    if entries is None:
        raise OSError(errno.EIO, "el staging no es un arbol seguro", root)
    files, directories = entries
    if files != expected or directories != _expected_output_directories(expected):
        raise OSError(errno.EIO,
                      "el staging no contiene el conjunto exacto de PNG", root)
    return {relative: _sha256_file(os.path.join(root, relative))
            for relative in sorted(expected)}


def _published_output_is_valid(out_dir: str, expected: set,
                               manifest: dict) -> bool:
    """True solo si el arbol publicado coincide byte a byte con el manifest."""
    if not expected or not isinstance(manifest, dict):
        return False
    if set(manifest) != expected:
        return False
    try:
        actual = _manifest_for_output(out_dir, expected)
    except (OSError, ValueError):
        return False
    return actual == manifest


def _restore_previous_destination(previous: str, out_dir: str) -> None:
    os.replace(previous, out_dir)
    _fsync_directory(os.path.dirname(out_dir))


def _discard_transaction(transaction_dir: str, parent: str) -> None:
    if os.path.lexists(transaction_dir):
        _safe_remove_tree(transaction_dir)
    _fsync_directory(parent)


def _finish_published_recovery(paths: dict, state: dict) -> None:
    """Limpia una publicacion ya confirmada por manifest."""
    try:
        mode = state.get("destination_mode")
        if mode is not None:
            # Un journal manipulado no puede activar bits setuid/setgid.
            os.chmod(paths["dest"], mode & 0o777)
        if os.path.lexists(paths["previous"]):
            _safe_remove_tree(paths["previous"])
        if os.path.lexists(paths["dir"]):
            _safe_remove_tree(paths["dir"])
    except OSError as exc:
        raise _PostPublishCleanupError(paths["dest"], exc) from exc
    _fsync_directory(paths["parent"])


def _recover_pending_transaction(out_dir: str) -> bool:
    """Recupera una transaccion interrumpida sin deshacer una publicacion.

    La tabla es deliberadamente fail-closed: un destino presente que no
    coincide byte a byte con el manifest nunca se borra ni se sustituye. En
    ese caso se conservan destino, backup y journal, y la importacion termina
    con rc=2 porque no es seguro afirmar que la publicacion no ocurrio.
    """
    paths = _transaction_paths(out_dir)
    transaction_dir = paths["dir"]
    if not os.path.lexists(transaction_dir):
        return False
    if os.path.islink(transaction_dir):
        raise _RecoveryError(errno.EIO,
                             "la transaccion pendiente es un enlace simbolico",
                             transaction_dir)

    state = _read_transaction_state(transaction_dir)
    if state is None:
        # Crash en la ventana entre os.mkdir(transaction_dir) y la primera
        # escritura del journal: no hay artefactos que recuperar. Descartar
        # el directorio vacio para no dejar el importador inoperativo en cada
        # importacion posterior. Con cualquier artefacto presente se falla
        # cerrado, porque no es seguro afirmar que no hubo publicacion.
        try:
            leftovers = os.listdir(transaction_dir)
        except OSError as exc:
            raise _RecoveryError(
                errno.EIO,
                "no se pudo inspeccionar la transaccion sin estado durable",
                transaction_dir,
            ) from exc
        if leftovers:
            raise _RecoveryError(errno.EIO,
                                 "transaccion sin estado durable pero con artefactos",
                                 transaction_dir)
        _discard_transaction(transaction_dir, paths["parent"])
        return True
    if state.get("dest") != paths["dest"]:
        raise _RecoveryError(errno.EIO,
                             "la transaccion pertenece a otro destino",
                             transaction_dir)

    phase = state["phase"]
    previous = paths["previous"]
    expected = set(state["expected_pngs"])
    manifest = state.get("manifest", {})
    dest_exists = os.path.lexists(paths["dest"])
    previous_exists = os.path.lexists(previous)
    staging_exists = os.path.lexists(paths["staging"])
    legacy = "version" not in state

    if previous_exists:
        if os.path.islink(previous) or not os.path.isdir(previous):
            raise _RecoveryError(
                errno.EIO,
                "el backup pendiente no es un directorio seguro; se conservan "
                "los artefactos",
                previous,
            )
        boundary = _find_mount_boundary(previous)
        if boundary is not None:
            raise _RecoveryError(
                errno.EIO,
                "el backup pendiente contiene una frontera de montaje '%s'; se "
                "conservan los artefactos" % boundary,
                previous,
            )

    if legacy:
        # Un journal legacy solo puede descartarse mientras demuestra que no
        # hubo destino previo ni publicacion. Las fases de publicacion sin
        # manifest no se pueden distinguir de un swap ya realizado.
        if phase not in ("building", "prepared"):
            raise _RecoveryError(
                errno.EIO,
                "la transaccion legacy no tiene manifest y no se puede recuperar "
                "con seguridad",
                transaction_dir,
            )
        if previous_exists or dest_exists:
            raise _RecoveryError(errno.EIO,
                                 "la transaccion legacy esta en estado ambiguo",
                                 transaction_dir)
        _discard_transaction(transaction_dir, paths["parent"])
        return True

    had_destination = state["had_destination"]
    if phase in ("building", "prepared"):
        if previous_exists:
            raise _RecoveryError(errno.EIO,
                                 "la transaccion preparing tiene un backup inesperado",
                                 transaction_dir)
        if had_destination:
            if not dest_exists:
                raise _RecoveryError(
                    errno.EIO,
                    "la transaccion preparing no tiene destino ni backup; se "
                    "conservan los artefactos por ambiguedad",
                    transaction_dir,
                )
            # El swap todavia no habia empezado: el destino sigue siendo el
            # anterior y solo hay que descartar staging + journal.
            _discard_transaction(transaction_dir, paths["parent"])
            return True
        if dest_exists:
            raise _RecoveryError(
                errno.EIO,
                "la transaccion preparing sin destino previo encuentra un "
                "destino inesperado; se conservan los artefactos",
                transaction_dir,
            )
        _discard_transaction(transaction_dir, paths["parent"])
        return True

    if phase not in ("moving_old", "old_moved", "published"):
        raise _RecoveryError(errno.EIO,
                             "fase de transaccion desconocida: %s" % phase,
                             transaction_dir)

    if not dest_exists:
        if previous_exists and phase in ("moving_old", "old_moved"):
            # Fallo antes de publicar: el backup integro es la version
            # anterior y se restaura antes de validar el origen nuevo.
            _restore_previous_destination(previous, paths["dest"])
            _discard_transaction(transaction_dir, paths["parent"])
            return True
        if (not previous_exists and not had_destination and
                phase in ("moving_old", "old_moved") and staging_exists):
            # No existia destino previo, el staging sigue presente y el swap
            # todavia no habia ocurrido: la transaccion es descartable.
            _discard_transaction(transaction_dir, paths["parent"])
            return True
        raise _RecoveryError(
            errno.EIO,
            "la transaccion no tiene destino ni backup; el estado es ambiguo y "
            "se conservan los artefactos",
            transaction_dir,
        )

    if phase == "moving_old" and had_destination and not previous_exists:
        # El journal se persistio antes del swap, pero el backup aun no existe:
        # el destino presente sigue siendo el anterior y puede descartarse solo
        # el staging + journal.
        _discard_transaction(transaction_dir, paths["parent"])
        return True
    if phase == "moving_old":
        raise _RecoveryError(
            errno.EIO,
            "la transaccion sigue antes del swap pero ya existe un destino; se "
            "conservan el destino y el backup",
            transaction_dir,
        )
    if phase == "old_moved" and staging_exists:
        raise _RecoveryError(
            errno.EIO,
            "la transaccion aun conserva el staging pero ya existe un destino; "
            "se conservan el destino y el backup",
            transaction_dir,
        )
    if not _published_output_is_valid(paths["dest"], expected, manifest):
        raise _RecoveryError(
            errno.EIO,
            "el destino presente no coincide con el manifest SHA-256; se "
            "conservan el destino y el backup",
            transaction_dir,
        )

    # El manifest exacto demuestra que la publicacion ocurrio. Solo se puede
    # limpiar el backup; nunca se hace rollback de una salida ya visible.
    _finish_published_recovery(paths, state)
    return True


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
            stream.flush()
            os.fsync(stream.fileno())
        # mkstemp crea 0600; el pack publicado usa el modo convencional 0644.
        os.chmod(temporary, 0o644)
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


def _preflight_output_paths(out_dir: str, counts: dict) -> tuple | None:
    """Valida todos los destinos planificados antes de escribir nada.

    Devuelve ``(directorios, ficheros)`` o None si el plan no es seguro.
    Los enlaces simbolicos se rechazan incluso con ``--force``: nunca se
    sigue un enlace para escribir fuera del destino solicitado.
    """
    planned_dirs, planned_files = _plan_output_paths(out_dir, counts)
    for path in planned_dirs:
        if os.path.lexists(path):
            if os.path.islink(path):
                print("ERROR: '%s' es un enlace simbolico; no se escribe nada"
                      % path)
                return None
            if not os.path.isdir(path):
                print("ERROR: el directorio planificado '%s' ya es un fichero"
                      % path)
                return None
        if not _is_within(path, out_dir):
            print("ERROR: '%s' resuelve fuera del destino; no se escribe nada"
                  % path)
            return None
    for path in planned_files:
        if os.path.lexists(path):
            if os.path.islink(path):
                print("ERROR: '%s' es un enlace simbolico; no se escribe nada"
                      % path)
                return None
            if not os.path.isfile(path):
                print("ERROR: el fichero planificado '%s' ya es un directorio"
                      % path)
                return None
        if not _is_within(path, out_dir):
            print("ERROR: '%s' resuelve fuera del destino; no se escribe nada"
                  % path)
            return None
    return planned_dirs, planned_files


def _write_staged_output(staging: str, anchored_by_anim: dict) -> tuple:
    """Escribe en ``staging`` el conjunto exacto de frames y strips."""
    frame_count = 0
    for anim in sorted(ANIM_FRAMES):
        anim_dir = os.path.join(staging, anim)
        os.makedirs(anim_dir, mode=0o755)
        os.chmod(anim_dir, 0o755)
        for idx, (width, height, pixels) in enumerate(anchored_by_anim[anim], 1):
            path = os.path.join(anim_dir, "%s_%02d.png" % (anim, idx))
            _write_png_atomic(path, width, height, bytearray(pixels))
            frame_count += 1
        _fsync_directory(anim_dir)

    strip_count = 0
    for anim in sorted(ANIM_FRAMES):
        frames = anchored_by_anim[anim]
        strip = strip_bytes(frames, CELL)
        path = os.path.join(staging, "%s_strip.png" % anim)
        _write_png_atomic(path, CELL * len(frames), CELL, bytearray(strip))
        strip_count += 1
    _fsync_directory(staging)
    return frame_count, strip_count


def _publish_staging(staging: str, out_dir: str,
                     transaction_dir: str | None = None) -> None:
    """Publica ``staging`` con estado durable y rollback antes del swap."""
    paths = _transaction_paths(out_dir)
    transaction_dir = transaction_dir or paths["dir"]
    previous = paths["previous"]
    state = _read_transaction_state(transaction_dir)
    if state is None or state.get("version") != _TRANSACTION_VERSION:
        raise OSError(errno.EIO,
                      "transaccion sin journal v2 para publicar", transaction_dir)
    expected = set(state["expected_pngs"])
    manifest = state["manifest"]
    had_destination = state["had_destination"]
    if not _published_output_is_valid(staging, expected, manifest):
        raise OSError(errno.EIO,
                      "el staging no coincide con su manifest SHA-256", staging)

    previous_mode = state.get("destination_mode", 0o755)
    if had_destination:
        if not os.path.lexists(out_dir):
            raise OSError(errno.EIO,
                          "el destino anterior ya no existe antes de publicar",
                          out_dir)
        try:
            previous_mode = stat.S_IMODE(
                os.stat(out_dir, follow_symlinks=False).st_mode)
        except OSError:
            previous_mode = state.get("destination_mode", 0o755)
    elif os.path.lexists(out_dir):
        raise OSError(errno.EIO,
                      "aparecio un destino que no existia al iniciar la transaccion",
                      out_dir)

    state["phase"] = "moving_old"
    state["destination_mode"] = previous_mode
    _write_transaction_state(transaction_dir, state)

    try:
        if had_destination:
            os.replace(out_dir, previous)
            _fsync_directory(paths["parent"])
            _fsync_directory(transaction_dir)
            # Seam determinista: un crash aqui debe dejar estado durable y el
            # backup listo para la recuperacion del siguiente importador.
            _transaction_checkpoint()
        state["phase"] = "old_moved"
        _write_transaction_state(transaction_dir, state)
        os.replace(staging, out_dir)
        _fsync_directory(paths["parent"])
        _fsync_directory(transaction_dir)
        os.chmod(out_dir, previous_mode & 0o777)
        state["phase"] = "published"
        _write_transaction_state(transaction_dir, state)
    except OSError as exc:
        # Si el rename del staging se completo, la salida ya es visible: no se
        # deshace. La ausencia de staging evita confundir un destino antiguo
        # identico con una publicacion terminada.
        if not os.path.lexists(staging):
            if _published_output_is_valid(out_dir, expected, manifest):
                raise _PostPublishCleanupError(out_dir, exc) from exc
            raise _RecoveryError(
                errno.EIO,
                "el staging ya no existe pero el destino no coincide con el "
                "manifest; se conservan el destino y los artefactos",
                out_dir,
            ) from exc
        # Fallo PRE-publicacion: el destino anterior sigue en `previous` y
        # debe restaurarse. Un destino presente que no coincide con el
        # manifest no se borra: se conserva junto al backup y se falla cerrado.
        if os.path.lexists(previous):
            try:
                if os.path.lexists(out_dir):
                    raise _RecoveryError(
                        errno.EIO,
                        "el destino inesperado no coincide con el manifest; se "
                        "conservan el destino y el backup",
                        out_dir,
                    )
                os.replace(previous, out_dir)
                _fsync_directory(paths["parent"])
            except _RecoveryError:
                raise
            except OSError as rollback_error:
                raise OSError(
                    getattr(exc, "errno", None),
                    "fallo al publicar y fallo el rollback (%s); el backup "
                    "anterior se conserva en %s" % (rollback_error, previous)
                ) from None
        raise

    # A partir de aqui la publicacion esta completa. Un fallo de limpieza es
    # posterior: se informa sin rollback y la transaccion queda disponible
    # para limpiarse o recuperarse en la siguiente ejecucion.
    try:
        if os.path.lexists(previous):
            _safe_remove_tree(previous)
        if os.path.lexists(transaction_dir):
            _safe_remove_tree(transaction_dir)
    except OSError as exc:
        raise _PostPublishCleanupError(out_dir, exc) from exc
    _fsync_directory(paths["parent"])


def _stage_and_publish(out_dir: str, anchored_by_anim: dict) -> tuple:
    """Construye un pack sibling y lo publica mediante una transaccion durable."""
    parent = os.path.dirname(out_dir)
    os.makedirs(parent, exist_ok=True)
    paths = _transaction_paths(out_dir)
    transaction_dir = paths["dir"]
    staging = paths["staging"]
    if os.path.lexists(transaction_dir):
        raise OSError(errno.EEXIST, "ya existe una transaccion pendiente",
                      transaction_dir)
    os.mkdir(transaction_dir, 0o700)
    os.chmod(transaction_dir, 0o700)
    _fsync_directory(parent)
    os.mkdir(staging, 0o755)
    os.chmod(staging, 0o755)

    expected = _expected_output_pngs()
    state = {
        "version": _TRANSACTION_VERSION,
        "dest": paths["dest"],
        "had_destination": os.path.lexists(out_dir),
        "phase": "building",
        "expected_pngs": sorted(expected),
        "manifest": {},
    }
    _write_transaction_state(transaction_dir, state)
    try:
        counts = _write_staged_output(staging, anchored_by_anim)
        # El manifest se calcula sobre los bytes YA escritos y se sincroniza
        # antes de Apartar el destino anterior. Asi recovery puede distinguir
        # una publicacion exacta de un destino con los mismos nombres.
        state["manifest"] = _manifest_for_output(staging, expected)
        state["phase"] = "prepared"
        _write_transaction_state(transaction_dir, state)
        _publish_staging(staging, out_dir, transaction_dir)
        return counts
    except _RecoveryError:
        # Un journal/manifest que no se puede interpretar deja los artefactos
        # intactos para una inspeccion posterior.
        raise
    except OSError:
        # Un fallo anterior a publicar se limpia por completo. Un crash
        # BaseException sale de este bloque y deja el estado para recuperar.
        # Si existe un backup, la transaccion completa se conserva para que
        # recovery pueda restaurarlo o conservarlo fail-closed.
        if os.path.lexists(transaction_dir) and \
                not os.path.lexists(paths["previous"]):
            try:
                _safe_remove_tree(transaction_dir)
            except OSError:
                pass
        raise


def import_pack(pack_dir: str, out_dir: str | None, force: bool = False,
                dry_run: bool = False) -> int:
    """Normaliza un pack externo al layout del proyecto.

    Los errores de filesystem se convierten en rc=2 con diagnostico; nunca
    escapan como traceback ni dejan un pack publicado a medias. Un lock por
    destino serializa importadores concurrentes. El dry-run omite ese lock
    de escritura para ser estrictamente read-only: no crea ficheros ni el
    namespace global de locks.
    """
    try:
        if not out_dir or dry_run:
            return _import_pack_impl(pack_dir, out_dir, force, dry_run)
        normalized_out = os.path.abspath(os.path.expanduser(out_dir))
        with _destination_lock(normalized_out) as acquired:
            if not acquired:
                print("ERROR: otra importacion ya esta operando sobre %s"
                      % normalized_out)
                return 2
            return _import_pack_impl(pack_dir, out_dir, force, dry_run)
    except _PostPublishCleanupError as exc:
        print("ERROR: la importacion se publico, pero fallo la limpieza "
              "posterior: %s" % exc)
        print("AVISO: la salida completa esta disponible en '%s'; no se "
              "realizo rollback" % exc.out_dir)
        return 1
    except _RecoveryError as exc:
        print("ERROR: no se pudo recuperar la transaccion de forma segura: %s"
              % exc)
        print("ERROR: el estado es ambiguo; se conservan el destino y los "
              "artefactos de la transaccion")
        return 2
    except OSError as exc:
        print("ERROR: no se pudo completar la importacion: %s" % exc)
        print("ERROR: no se publico una salida parcial")
        return 2


def _import_pack_impl(pack_dir: str, out_dir: str | None,
                      force: bool = False, dry_run: bool = False) -> int:
    if not out_dir:
        print("ERROR: `import` exige --out <destino> explicito")
        return 2

    out_dir = os.path.abspath(os.path.expanduser(out_dir))
    pack_dir = os.path.abspath(os.path.expanduser(pack_dir))

    # El destino no puede ser el origen, ni un ancestro o descendiente de
    # este. La relacion se evalua sobre la identidad real del filesystem:
    # cubre aliases por symlink y rutas equivalentes. `samefile` y
    # `commonpath` se tratan por separado porque pueden fallar si una ruta
    # no existe o si los volumenes son distintos. Estas comprobaciones son
    # de rutas y no requieren que el origen exista todavia.
    if _same_location(out_dir, pack_dir):
        print("ERROR: el destino es el propio pack de origen (%s); la "
              "importacion destruiria la entrada. Usa otro --out." % pack_dir)
        return 2
    if _is_strictly_within(out_dir, pack_dir):
        print("ERROR: el destino '%s' es descendiente del pack de origen "
              "'%s'; usa otra ubicacion." % (out_dir, pack_dir))
        return 2
    if _is_strictly_within(pack_dir, out_dir):
        print("ERROR: el destino '%s' es ancestro del pack de origen '%s'; "
              "usa otra ubicacion." % (out_dir, pack_dir))
        return 2

    if os.path.islink(out_dir):
        print("ERROR: el destino es un enlace simbolico: %s" % out_dir)
        return 2
    if os.path.lexists(out_dir) and not os.path.isdir(out_dir):
        print("ERROR: el destino no es un directorio: %s" % out_dir)
        return 2
    if _is_within(out_dir, SKIN_DIR) and not force:
        print("ERROR: no se puede escribir en el pack canonico %s sin --force" %
              SKIN_DIR)
        return 2

    transaction_dir = _transaction_paths(out_dir)["dir"]
    if dry_run and os.path.lexists(transaction_dir):
        # El dry-run rechaza la transaccion pendiente sin leerla, recoverla o
        # modificarla. El importador normal es quien debe resolverla.
        print("ERROR: hay una transaccion pendiente para %s; ejecuta una "
              "importacion normal para recuperarla" % out_dir)
        return 2

    # Seguridad del destino ANTES de recovery. Un mountpoint o una ruta
    # planificada insegura hacen que la transaccion pendiente quede intacta.
    if os.path.isdir(out_dir):
        boundary = _find_mount_boundary(out_dir)
        if boundary is not None:
            print("ERROR: el destino contiene una frontera de montaje '%s'; "
                  "no se publica ni se elimina nada" % boundary)
            return 2
    if _preflight_output_paths(out_dir, ANIM_FRAMES) is None:
        return 2

    if not dry_run:
        # Recovery ocurre bajo el lock de escritura y antes de validar que el
        # origen nuevo existe o es valido. Asi un crash que dejo el destino
        # en `previous` se restaura aunque la siguiente entrada falle.
        _recover_pending_transaction(out_dir)

    # Recovery puede haber restaurado el destino anterior: se repiten las
    # comprobaciones de seguridad sobre el arbol ya restaurado.
    if os.path.isdir(out_dir):
        boundary = _find_mount_boundary(out_dir)
        if boundary is not None:
            print("ERROR: el destino contiene una frontera de montaje '%s'; "
                  "no se publica ni se elimina nada" % boundary)
            return 2
    if _preflight_output_paths(out_dir, ANIM_FRAMES) is None:
        return 2

    # A partir de aqui se valida el origen nuevo. Si la recovery anterior
    #restauro una version anterior, un error del origen deja ese destino
    # integro y devuelve rc=2.
    if not os.path.isdir(pack_dir):
        print("ERROR: no existe el directorio %s" % pack_dir)
        return 2

    # Por defecto no se toca un destino no vacio: no se borran ficheros
    # ajenos ni se conservan frames obsoletos extra. `--force` permite
    # reemplazar el arbol por el conjunto exacto generado.
    if os.path.isdir(out_dir) and os.listdir(out_dir) and not force:
        print("ERROR: el destino ya no esta vacio: %s; usa --force para "
              "reemplazarlo por el conjunto exacto" % out_dir)
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

    if dry_run:
        frame_count = sum(len(frames) for frames in anchored_by_anim.values())
        strip_count = len(anchored_by_anim)
        print("SKIN_IMPORT_DRY_RUN frames=%d strips=%d -> %s" % (
            frame_count, strip_count, out_dir))
        return 0

    # Todo se construye primero en un sibling staging. Solo se publica un
    # pack completo; un fallo intermedio limpia el staging y conserva el
    # destino anterior intacto.
    frame_count, strip_count = _stage_and_publish(out_dir, anchored_by_anim)

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
        dry_run = False
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
            elif arg == "--dry-run":
                dry_run = True
            else:
                print("ERROR: argumento desconocido para import: %s" % arg)
                return 2
            index += 1
        return import_pack(pack_dir, out_dir, force, dry_run=dry_run)
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
