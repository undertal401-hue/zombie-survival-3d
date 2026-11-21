#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generador del skin de zombi de rango bajo (ADR-005 / ADR-007).

Produce el pack que consume el runtime:

    assets/enemies/zombie/<anim>/<anim>_NN.png   frames sueltos (64x64)
    assets/enemies/zombie/<anim>_strip.png        strip horizontal uniforme

FUENTE (ADR-007): el sprite cenital real que el autor entrego en Descargas,
`zoimbie1_hold.png` (35x43, 235 combinaciones RGBA - 191 colores RGB -,
transparencia). El juego Unity de
origen solo contiene ESE sprite de zombi: no hay frames de animacion
oficiales. El pack se DERIVA de el de forma determinista:

  1. Se rota 90 grados en sentido antihorario. El sprite original mira a la
     derecha; el contrato del runtime exige que el eje local -Y sea "adelante"
     (ZombieVisual rota la sprite con `velocity.angle() + PI/2`).
  2. El alpha se vuelve binario (umbral 160) y los colores se traducen a la
     paleta canonica de 16 colores. Los tonos dominantes tienen un mapeo
     explicito (piel ambar, camisa verde, cabeza gris, acentos rojos) para
     conservar el contraste; el resto cae al color canonico mas cercano.
  3. Se escala a 60x49 px con vecino mas proximo (el sprite conserva su
     silueta; no se inventan pixeles).
  4. Cada frame aplica una transformacion entera (bob, balanceo, estocada,
     derrumbe) sobre esa misma base. No se redibuja el personaje.

CONTRATO (ficha del pack):
  - Celda de 64x64 px, PPU 64, pivot centro (0.5, 0.5).
  - Animaciones y numero de frames:
        idle 2, walk 5, walk_alt 3, attack 6,
        attack_alt 2, rise 5, death 6, special 4
  - Strips horizontales listos para AnimationPlayer: celda N en x = N*64.

ANCLAJE: se calcula el bbox opaco de la UNION de todos los frames del pack y
se aplica una traslacion global entera para centrarla en la celda 64x64. Nunca
se reencuadra un frame contra su propio bbox.

Uso:
    python3 tools/gen_zombie_skin.py           # genera el pack
    python3 tools/gen_zombie_skin.py --check   # verifica (gate de CI)
"""

from __future__ import annotations

import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gen_art import PALETTE  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(
    os.path.join(HERE, "..", "assets", "enemies", "zombie"))
SOURCE_PNG = os.path.normpath(
    os.path.join(HERE, "art_source", "zoimbie1_hold.png"))

# ---------------------------------------------------------------------------
# Contrato del skin
# ---------------------------------------------------------------------------

CELL = 64          # celda del pack (px) -> PPU 64
BASE_W = 60        # ancho de la base derivada (43 px de origen x ~1.4)
BASE_H = 49        # alto de la base derivada (35 px de origen x 1.4)
ALPHA_THRESHOLD = 160
SOURCE_SIZE = (35, 43)
# Tope de la fuente: el sprite real ocupa 2.465 bytes. El limite evita que un
# fichero sustituido (o un enlace a un fichero gigante) agote la memoria del
# proceso antes de que el hash pueda rechazarlo.
SOURCE_MAX_BYTES = 65536
SOURCE_SHA256 = (
    "61df3e84c18409b698b56273a0bd014f86a23dc5622380d5d10b82124afff84e"
)

# Tabla del skin: nombre del pack -> (accion canonica, indices de frame, fps,
# bucle). Los indices son ordinales (0..n-1): el movimiento real de cada frame
# vive en `MOTION`, que debe tener exactamente la misma longitud. El parser de
# `ZombieSkinTest._generator_runtime_cross_check()` lee esta tabla para cruzar
# recuento, fps, bucle y nombre canonico con `ZombieVisual.SKIN_ANIMATIONS`.
SKIN_ANIMS = {
    # 2 frames: respiracion sutil.
    "idle": ("idle", (0, 1), 4.0, True),
    # 5 frames: ciclo de caminata (izq, paso, der, paso, paso).
    "walk": ("walk", (0, 1, 2, 3, 4), 8.0, True),
    # 3 frames: zancada rapida (usada como `run`).
    "walk_alt": ("run", (0, 1, 2), 12.0, True),
    # 6 frames: carga, media, golpe, golpe, media, vuelta.
    "attack": ("attack", (0, 1, 2, 3, 4, 5), 12.0, False),
    # 2 frames: golpe alterno rapido (usada como `hit`).
    "attack_alt": ("hit", (0, 1), 10.0, False),
    # 5 frames: arrastre continuo en el suelo (runtime: `crawl`).
    # El bucle es TRUE: `crawl` se reproduce en bucle mientras al zombi le
    # fallan las piernas, asi que el clip debe ciclar.
    "rise": ("crawl", (0, 1, 2, 3, 4), 8.0, True),
    # 6 frames: de pie, tropiezo, cae, en el suelo.
    "death": ("death", (0, 1, 2, 3, 4, 5), 7.0, False),
    # 4 frames: sacudida de impacto (usada como `hurt`).
    "special": ("hurt", (0, 1, 2, 3), 10.0, False),
}

# ---------------------------------------------------------------------------
# Movimiento derivado: (dx, dy, escala_x, escala_y, bottom)
# ---------------------------------------------------------------------------
# `bottom=None` centra la base en la celda; un entero ancla el borde inferior
# de la base a esa fila (derrumbe/arrastre). Todos los valores son enteros o
# factores racionales pequenos: la regeneracion es determinista.
#
# La base ya mira hacia arriba, asi que "adelante" es -Y. Las estocadas del
# ataque y el rebote del golpe se mueven en ese eje. El balanceo lateral se
# limita a +-1 px para que el bbox de cada frame siga centrado (el contrato
# exige |centro_x - 32| <= 1).
BASE_BOTTOM = (CELL - BASE_H) // 2 + BASE_H

MOTION = {
    "idle": [
        (0, 0, 1.00, 1.00, None),
        (0, -1, 1.00, 1.00, None),
    ],
    "walk": [
        (0, 0, 1.00, 1.00, None),
        (-1, -1, 1.00, 1.00, None),
        (0, 0, 1.00, 1.00, None),
        (1, -1, 1.00, 1.00, None),
        (0, 0, 1.00, 1.00, None),
    ],
    "walk_alt": [
        (-1, -1, 1.00, 1.00, None),
        (0, -2, 1.00, 1.00, None),
        (1, -1, 1.00, 1.00, None),
    ],
    "attack": [
        (0, 0, 1.00, 1.00, None),
        (0, -2, 1.00, 1.00, None),
        (0, -4, 1.02, 0.98, None),
        (0, -5, 1.03, 0.96, None),
        (0, -3, 1.02, 0.98, None),
        (0, 0, 1.00, 1.00, None),
    ],
    "attack_alt": [
        (1, 2, 1.00, 1.00, None),
        (0, 3, 1.00, 1.00, None),
    ],
    "special": [
        (1, 1, 1.00, 1.00, None),
        (0, 2, 1.00, 1.00, None),
        (-1, 1, 1.00, 1.00, None),
        (0, 0, 1.00, 1.00, None),
    ],
    "rise": [
        (0, -1, 1.00, 0.55, BASE_BOTTOM),
        (0, 0, 1.00, 0.55, BASE_BOTTOM),
        (0, 1, 1.00, 0.55, BASE_BOTTOM),
        (0, 0, 1.00, 0.55, BASE_BOTTOM),
        (0, -1, 1.00, 0.55, BASE_BOTTOM),
    ],
    "death": [
        (0, 0, 1.00, 1.00, None),
        (0, 1, 1.00, 0.92, BASE_BOTTOM),
        (0, 0, 1.00, 0.80, BASE_BOTTOM),
        (0, 0, 1.00, 0.65, BASE_BOTTOM),
        (0, 0, 1.00, 0.50, BASE_BOTTOM),
        (0, 0, 1.00, 0.42, BASE_BOTTOM),
    ],
}


def _palette_rgb() -> dict[str, tuple[int, int, int]]:
    return {
        name: (int(value[1:3], 16), int(value[3:5], 16), int(value[5:7], 16))
        for _index, name, value in PALETTE
    }


PALETTE_RGB = _palette_rgb()

# Tonos dominantes del sprite -> color canonico. Sin este mapa, el gris de la
# cabeza y los dos verdes de la camisa caerian en el mismo tono y la silueta
# perderia lectura. El resto (bordes antialiasados) se cuantiza al mas cercano.
SOURCE_COLOR_MAP = {
    (196, 134, 71): PALETTE_RGB["AMBER"],
    (185, 126, 67): PALETTE_RGB["SKIN_MID"],
    (175, 119, 63): PALETTE_RGB["SKIN_MID"],
    (169, 115, 61): PALETTE_RGB["SKIN_MID"],
    (154, 105, 55): PALETTE_RGB["SKIN_MID"],
    (152, 103, 55): PALETTE_RGB["SKIN_MID"],
    (102, 102, 102): PALETTE_RGB["STEEL_DARK"],
    (79, 79, 79): PALETTE_RGB["OUTLINE"],
    (39, 174, 96): PALETTE_RGB["OLIVE_LIGHT"],
    (27, 123, 67): PALETTE_RGB["OLIVE_DARK"],
    (210, 96, 20): PALETTE_RGB["BLOOD_BRIGHT"],
}


# ---------------------------------------------------------------------------
# Derivacion de la base
# ---------------------------------------------------------------------------

def _read_source():
    """Lee la fuente UNA vez y devuelve sus pixeles ya decodificados.

    El hash y la decodificacion usan EXACTAMENTE el mismo buffer: si el
    fichero se sustituyera entre dos lecturas, la verificacion ya no
    describiria los pixeles que se decodifican (ventana TOCTOU).
    """
    from skin_pack import read_png_bytes
    if os.path.islink(SOURCE_PNG):
        raise RuntimeError(
            "la fuente %s es un enlace simbolico; se espera un fichero"
            % SOURCE_PNG)
    if not os.path.isfile(SOURCE_PNG):
        raise FileNotFoundError(
            "falta la fuente %s (sprite cenital del autor)" % SOURCE_PNG)
    size = os.path.getsize(SOURCE_PNG)
    if size <= 0 or size > SOURCE_MAX_BYTES:
        raise RuntimeError(
            "la fuente %s mide %d bytes; el maximo es %d" %
            (SOURCE_PNG, size, SOURCE_MAX_BYTES))
    with open(SOURCE_PNG, "rb") as handle:
        data = handle.read(SOURCE_MAX_BYTES + 1)
    if len(data) > SOURCE_MAX_BYTES:
        raise RuntimeError(
            "la fuente %s supera el maximo de %d bytes" %
            (SOURCE_PNG, SOURCE_MAX_BYTES))
    digest = hashlib.sha256(data).hexdigest()
    if digest != SOURCE_SHA256:
        raise RuntimeError(
            "la fuente %s no coincide con el SHA-256 fijado (%s != %s)" %
            (SOURCE_PNG, digest, SOURCE_SHA256))
    width, height, pixels = read_png_bytes(data)
    if (width, height) != SOURCE_SIZE:
        raise RuntimeError(
            "la fuente mide %dx%d; el contrato espera %dx%d" %
            ((width, height) + SOURCE_SIZE))
    return width, height, pixels


def _rotate_ccw(width: int, height: int, pixels: bytes):
    """Rota el sprite 90 grados en sentido antihorario (derecha -> arriba)."""
    out_w, out_h = height, width
    out = bytearray(out_w * out_h * 4)
    for y in range(height):
        for x in range(width):
            src = (y * width + x) * 4
            nx, ny = y, width - 1 - x
            dst = (ny * out_w + nx) * 4
            out[dst:dst + 4] = pixels[src:src + 4]
    return out_w, out_h, bytes(out)


def _quantize(width: int, height: int, pixels: bytes):
    """Alpha binario + traduccion de tonos dominantes + paleta canonica."""
    from skin_pack import quantize_to_canonical
    out = bytearray(pixels)
    for i in range(width * height):
        base = i * 4
        if out[base + 3] < ALPHA_THRESHOLD:
            out[base:base + 4] = b"\x00\x00\x00\x00"
            continue
        rgb = (out[base], out[base + 1], out[base + 2])
        target = SOURCE_COLOR_MAP.get(rgb)
        if target is not None:
            out[base:base + 4] = bytes((target[0], target[1], target[2], 255))
        else:
            out[base + 3] = 255
    return quantize_to_canonical((width, height, bytes(out)))


def _resize_nearest(width: int, height: int, pixels: bytes,
                    out_w: int, out_h: int):
    out = bytearray(out_w * out_h * 4)
    for y in range(out_h):
        sy = y * height // out_h
        for x in range(out_w):
            sx = x * width // out_w
            src = (sy * width + sx) * 4
            dst = (y * out_w + x) * 4
            out[dst:dst + 4] = pixels[src:src + 4]
    return out_w, out_h, bytes(out)


def _derive_base(width: int, height: int, pixels: bytes):
    """Orienta, cuantiza y escala unos pixeles de fuente a la base del pack.

    Separado de `build_base` para que el control de derivacion pueda aplicar
    la MISMA transformacion a una fuente mutada.
    """
    width, height, pixels = _rotate_ccw(width, height, pixels)
    width, height, pixels = _quantize(width, height, pixels)
    return _resize_nearest(width, height, pixels, BASE_W, BASE_H)


def build_base():
    """Carga, orienta, cuantiza y escala la fuente a la base del pack."""
    width, height, pixels = _read_source()
    return _derive_base(width, height, pixels)


def _mutated_source_candidates(width: int, height: int, pixels: bytes):
    """Genera variantes de la fuente con UN pixel interior perforado.

    El pixel elegido esta dentro de la silueta (no toca el bbox), de modo que
    la mutacion cambia los pixeles del pack sin romper el contrato. Se
    ofrecen VARIOS candidatos: si uno dejara la derivacion invalida (por
    ejemplo, eliminando el ultimo pixel de un color), se prueba el siguiente
    en vez de dar la puerta por rota.
    """
    data = bytearray(pixels)
    opaque = []
    for i in range(width * height):
        if data[i * 4 + 3] >= ALPHA_THRESHOLD:
            opaque.append(i)
    if not opaque:
        raise RuntimeError("la fuente no tiene pixeles opacos")
    xs = [i % width for i in opaque]
    ys = [i // width for i in opaque]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    for i in opaque:
        x = i % width
        y = i // width
        if x0 < x < x1 and y0 < y < y1:
            mutated = bytearray(pixels)
            mutated[i * 4:i * 4 + 4] = b"\x00\x00\x00\x00"
            yield width, height, bytes(mutated)


def control_derivacion_desde_pixeles() -> list[str]:
    """Control NEGATIVO: los pixeles de la FUENTE mandan en el pack.

    Si la derivacion dejase de usar la fuente (por ejemplo, volviendo al
    humanoide procedural), mutar un pixel de la fuente no cambiaria el pack
    y este control fallaria. Es la garantia permanente de que el pack que se
    muestra es el arte pedido y no un dibujo cualquiera.
    """
    problems = []
    width, height, pixels = _read_source()
    base_real = _derive_base(width, height, pixels)
    frames_real = None
    base_changed = False
    frames_changed = False
    tried = 0
    for mutated in _mutated_source_candidates(width, height, pixels):
        tried += 1
        if tried > 16:
            break
        base_mut = _derive_base(*mutated)
        if base_mut == base_real:
            continue
        base_changed = True
        try:
            frames_mut = _frames_from_base(base_mut)
        except RuntimeError:
            # Este pixel deja la derivacion invalida: se prueba otro.
            continue
        if frames_real is None:
            frames_real = _frames_from_base(base_real)
        if frames_mut != frames_real:
            frames_changed = True
            break
    if not base_changed:
        problems.append("la derivacion NO responde a los pixeles de la fuente")
    elif not frames_changed:
        problems.append(
            "los frames no cambian al cambiar los pixeles de la fuente")
    return problems


def _compose(base, dx: int, dy: int, scale_x: float, scale_y: float,
             bottom):
    width, height, pixels = base
    out_w = max(1, int(round(width * scale_x)))
    out_h = max(1, int(round(height * scale_y)))
    if (out_w, out_h) != (width, height):
        width, height, pixels = _resize_nearest(
            width, height, pixels, out_w, out_h)
    if width > CELL or height > CELL:
        raise RuntimeError(
            "el frame escalado (%dx%d) no cabe en la celda de %dx%d" %
            (width, height, CELL, CELL))
    x = (CELL - width) // 2 + dx
    if bottom is None:
        y = (CELL - height) // 2 + dy
    else:
        y = bottom - height + dy
    out = bytearray(CELL * CELL * 4)
    for row in range(height):
        ty = y + row
        for col in range(width):
            src = (row * width + col) * 4
            if pixels[src + 3] == 0:
                continue
            tx = x + col
            # FAIL CLOSED: si un pixel opaco caeria fuera de la celda, el
            # recorte perderia silueta en silencio y el frame dejaria de
            # encajar en el ancla global. Se aborta el generador.
            if ty < 0 or ty >= CELL or tx < 0 or tx >= CELL:
                raise RuntimeError(
                    "un pixel opaco caeria fuera de la celda (%d,%d)" % (tx, ty))
            dst = (ty * CELL + tx) * 4
            out[dst:dst + 4] = pixels[src:src + 4]
    return CELL, CELL, bytes(out)


def _shift(width: int, height: int, pixels: bytes, dx: int, dy: int):
    out = bytearray(width * height * 4)
    for y in range(height):
        ty = y + dy
        for x in range(width):
            src = (y * width + x) * 4
            if pixels[src + 3] == 0:
                continue
            tx = x + dx
            # FAIL CLOSED por el mismo motivo que en `_compose`.
            if ty < 0 or ty >= height or tx < 0 or tx >= width:
                raise RuntimeError(
                    "la traslacion global (%d,%d) saca un pixel opaco de la celda"
                    % (dx, dy))
            dst = (ty * width + tx) * 4
            out[dst:dst + 4] = pixels[src:src + 4]
    return width, height, bytes(out)


def _bbox(pixels: bytes):
    from skin_pack import pixel_stats
    _opaque, bbox, colors = pixel_stats(CELL, CELL, pixels)
    return bbox, colors


def _validate(frames):
    """Exige el contrato completo ANTES de escribir o comparar.

    El contrato vive en `skin_pack.validate_pack_contract`: el generador y la
    puerta del pack comparten la MISMA lista de reglas. Antes cada uno tenia
    su copia y ya habian divergido (solo el generador comprobaba la
    semantica de `rise`).
    """
    from skin_pack import validate_pack_contract
    problems = validate_pack_contract(frames)
    if problems:
        raise RuntimeError(
            "el pack derivado incumple el contrato:\n  " + "\n  ".join(problems))


def build_frames():
    """Deriva todos los frames del pack -> {ruta_rel: (w, h, rgba)}."""
    return _frames_from_base(build_base())


def _frames_from_base(base):
    """Aplica los movimientos de `MOTION` a una base ya derivada."""
    composed = {}
    for anim in sorted(SKIN_ANIMS):
        _action, poses, _fps, _loop = SKIN_ANIMS[anim]
        motions = MOTION[anim]
        if len(poses) != len(motions):
            raise RuntimeError(
                "%s: SKIN_ANIMS declara %d frames y MOTION %d" %
                (anim, len(poses), len(motions)))
        # Las poses son ordinales REALES: el indice selecciona el movimiento.
        # Si fueran metadatos muertos, cambiar (0, 1, 2, 3, 1) no cambiaria
        # el pack y ninguna puerta lo detectaria.
        if poses != tuple(range(len(poses))):
            raise RuntimeError(
                "%s: SKIN_ANIMS debe declarar poses ordinales 0..%d (tiene %s)"
                % (anim, len(poses) - 1, poses))
        for pose in poses:
            composed["%s/%s_%02d.png" % (anim, anim, pose + 1)] = _compose(
                base, *motions[pose])

    # Traslacion global: centra la UNION de todos los frames. Se aplica una
    # sola vez y a todos por igual; nunca se reencuadra un frame suelto.
    boxes = {}
    for rel, (_w, _h, pixels) in composed.items():
        bbox, _colors = _bbox(pixels)
        if bbox is not None:
            boxes[rel] = bbox
    union = (
        min(b[0] for b in boxes.values()),
        min(b[1] for b in boxes.values()),
        max(b[2] for b in boxes.values()),
        max(b[3] for b in boxes.values()),
    )
    shift_x = int(round(CELL / 2.0 - (union[0] + union[2]) / 2.0))
    shift_y = int(round(CELL / 2.0 - (union[1] + union[3]) / 2.0))
    frames = {}
    for rel, (width, height, pixels) in composed.items():
        frames[rel] = _shift(width, height, pixels, shift_x, shift_y)
    _validate(frames)
    return frames


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


def _write_png_atomic(path: str, width: int, height: int, rgba: bytes) -> None:
    """Escribe el PNG en un temporal y lo publica con `os.replace`.

    `os.replace` NO sigue enlaces: si el destino fuese un symlink, se
    sustituye el enlace, no el fichero al que apunta. Y un fallo a mitad no
    deja un PNG truncado en el pack.
    """
    from gen_art import write_png
    temp = "%s.tmp-%d" % (path, os.getpid())
    try:
        write_png(temp, width, height, bytearray(rgba))
        os.replace(temp, path)
    except OSError:
        if os.path.exists(temp):
            os.remove(temp)
        raise


def do_build() -> int:
    frames, strips = outputs()
    for rel, (w, h, rgba) in sorted(frames.items()):
        path = os.path.join(OUT_DIR, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        _write_png_atomic(path, w, h, rgba)
    for name, (w, h, rgba) in sorted(strips.items()):
        path = os.path.join(OUT_DIR, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        _write_png_atomic(path, w, h, rgba)
    print("SKIN_GENERATED frames=%d strips=%d -> %s" % (
        len(frames), len(strips), OUT_DIR))
    return 0


def do_check() -> int:
    """Puerta de CI: compara con disco y valida el contrato completo."""
    from skin_pack import png_bytes, read_png, validate_pack_contract

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
        disk_frames[rel] = (fw, fh, fp)

    # Contrato canonico: MISMA funcion que usa `skin_pack.py check`.
    for problem in validate_pack_contract(disk_frames):
        print("FAIL %s" % problem)
        bad += 1

    for anim, count in sorted(
            (anim, len(poses)) for anim, (_a, poses, _f, _l)
            in SKIN_ANIMS.items()):
        found = sum(1 for rel in disk_frames if rel.startswith(anim + "/"))
        if found != count:
            print("FAIL numero de frames %s: %d (esperado %d)" %
                  (anim, found, count))
            bad += 1

    # Control negativo: la derivacion tiene que responder a los PIXELES de la
    # fuente. Si el generador volviera a dibujar un humanoide procedural, este
    # control fallaria aunque el pack cumpliese el contrato estructural.
    control_problems = control_derivacion_desde_pixeles()
    for problem in control_problems:
        print("FAIL control: %s" % problem)
        bad += 1
    if not control_problems:
        print("OK   control: la derivacion responde a los pixeles de la fuente")

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


def selftest() -> int:
    """Autopruebas del generador (puerta de CI).

    El control negativo de derivacion es la garantia de que el pack sale de
    los PIXELES de la fuente. Estas pruebas lo someten a los dos modos de
    fallo que importan:

      1. la derivacion real responde a la fuente (control verde);
      2. una derivacion NEUTRALIZADA (base constante, pack que sigue cumpliendo
         el contrato) tiene que ser detectada: demuestra que el control llega
         a su rama y que es la unica barrera entre el arte pedido y un dibujo
         procedural;
      3. una derivacion que LANZA al mutar la fuente tiene que fallar de
         forma limpia (sin traceback y con diagnostico), no reventar la puerta.
    """
    global _derive_base
    failures = []
    original_derive = _derive_base

    # 1. El control real pasa.
    try:
        problems = control_derivacion_desde_pixeles()
        raised = None
    except Exception as exc:
        problems = []
        raised = exc
    if raised is not None:
        failures.append("el control real lanzo %s: %s" %
                        (type(raised).__name__, raised))
    elif problems:
        failures.append("el control real deberia pasar: %s" % problems)

    # 2. Derivacion neutralizada: base constante que TODAVIA cumple el
    #    contrato. El control tiene que decir que no responde a la fuente.
    try:
        width, height, pixels = _read_source()
        base_real = original_derive(width, height, pixels)
        _derive_base = lambda w, h, p: base_real
        problems = control_derivacion_desde_pixeles()
        raised = None
    except Exception as exc:
        problems = []
        raised = exc
    finally:
        _derive_base = original_derive
    if raised is not None:
        failures.append("el control lanzo %s: %s" %
                        (type(raised).__name__, raised))
    elif not any("NO responde" in problem for problem in problems):
        failures.append("el control debe detectar una derivacion que ignora "
                        "la fuente (problemas: %s)" % problems)

    # 3. Derivacion que lanza SOLO al mutar (la fuente real sigue deriving
    #    bien): el control tiene que fallar de forma limpia, sin traceback.
    def _boom_only_mutated(w, h, p):
        if p == pixels:
            return base_real
        raise RuntimeError("boom: la derivacion revienta al mutar la fuente")

    try:
        _derive_base = _boom_only_mutated
        problems = control_derivacion_desde_pixeles()
        raised = None
    except Exception as exc:
        problems = []
        raised = exc
    finally:
        _derive_base = original_derive
    if raised is not None:
        failures.append("el control debe fallar limpio cuando la derivacion "
                        "lanza al mutar, pero lanzo %s: %s" %
                        (type(raised).__name__, raised))
    elif not problems:
        failures.append("el control debe fallar cuando la derivacion lanza al "
                        "mutar la fuente")

    print("ZOMBIE_SKIN_SELFTEST failures=%d" % len(failures))
    for failure in failures:
        print("  - %s" % failure)
    return 1 if failures else 0


def main(argv) -> int:
    # Un fallo de la fuente (ausente, alterada o ilegible) es un diagnostico,
    # no una excepcion: la puerta debe salir con codigo 2 y sin traceback.
    try:
        if len(argv) > 1 and argv[1] == "--check":
            return do_check()
        if len(argv) > 1 and argv[1] == "--selftest":
            return selftest()
        return do_build()
    except (RuntimeError, FileNotFoundError, OSError, ValueError) as exc:
        print("FAIL %s" % exc)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
