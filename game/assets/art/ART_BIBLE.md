# ART BIBLE — Pixel Art Pipeline (ADR-001)

Capa 0 del plan maestro. Toda la representación bitmap del juego queda
bloqueada a esta biblia. Generador canónico: `tools/gen_art.py` (Python puro,
stdlib `zlib` + `struct`, sin PIL/ImageMagick, semilla fija `1337`).

## 1. Retícula y tamaño

- Tile y personaje: **32×32 px**. Un frame = una celda de 32×32.
- Grid: cada hoja es una retícula de celdas de 32×32 alineadas al origen
  (0,0); nunca hay frames a medio píxel. `cell(col,row)` → `x=col*32, y=row*32`.
- Todas las hojas se importan con `texture_filter = NEAREST` y el proyecto
  activa el snap 2D a píxel. **Prohibido antialiasing y filtrado bilinear.**
- Las celdas vacías son transparentes (alpha 0), nunca negras opacas.

## 2. Paleta canónica — 16 colores (hex exacto)

Índice 0 = transparente. Los índices 1..16 son los únicos colores permitidos.
Cualquier píxel de cualquier hoja debe ser uno de estos valores o transparente.

| #  | Nombre        | Hex       | Uso principal                         |
|----|---------------|-----------|---------------------------------------|
| 1  | OUTLINE       | #0b0d0b   | contorno de siluetas, sombra extrema  |
| 2  | SHADOW_GREEN  | #1a2117   | sombra verde profunda, interior ropa  |
| 3  | OLIVE_DARK    | #33421f   | tono oscuro de tela / carne podrida   |
| 4  | OLIVE_MID     | #566e32   | tono medio de chaqueta / piel zombi   |
| 5  | OLIVE_LIGHT   | #7f9a45   | luz de tela / carne infectada         |
| 6  | OLIVE_HI      | #a9bf5e   | reflejo máximo, musgo, bilis          |
| 7  | LEATHER_DARK  | #33261a   | cuero oscuro, madera, manchas         |
| 8  | LEATHER_MID   | #5c4330   | correas, mochila, suciedad            |
| 9  | SKIN_MID      | #8b6b45   | piel media, cartón, adobe             |
| 10 | AMBER         | #d2a867   | pañuelo, piel clara, destello cálido  |
| 11 | BONE          | #efe4bd   | hueso, blanco roto, brillo, ojos      |
| 12 | BLOOD_DARK    | #6e1712   | sangre seca, moretón                  |
| 13 | BLOOD         | #b52b20   | **rojo sangre** (color explícito)     |
| 14 | BLOOD_BRIGHT  | #e8563c   | sangre fresca, fogonazo, herida       |
| 15 | STEEL_DARK    | #55626d   | metal, hormigón, sombra fría          |
| 16 | STEEL_LIGHT   | #9aabb6   | metal pulido, borde frío, humo        |

El rojo sangre canónico es `#b52b20` (índice 13, `BLOOD`). No se sustituye
por ningún otro rojo: `#6e1712` es sangre seca y `#e8563c` es sangre fresca.

Regla de los 3 tonos: cada superficie se pinta con un triple
`shadow / mid / light` de esta paleta; se permite un cuarto tono (`OUTLINE`)
solo para el contorno. Nunca se mezclan tonos nuevos por interpolación.

## 3. Silueta y outline

- Toda forma lleva un contorno de **1 px** en `OUTLINE` (#0b0d0b) calculado
  como la corona de 8 vecinos alrededor de la máscara de la forma.
- Iluminación consistente desde **arriba-izquierda**: borde superior/izquierdo
  en `light`, borde inferior/derecho en `shadow`, interior en `mid`.
- Las siluetas se leen a 32 px: cabeza redonda, hombros anchos, brazos
  diferenciados del torso, armas y extremidades desbordando el body box.
  **Prohibido rellenar un rectángulo y llamarle sprite.**
- Se permiten píxeles de detalle deliberados (ojos, hebillas, vendas,
  salpicaduras) siempre que usen colores de la paleta.
- Sin degradados, sin anti-aliasing, sin subpíxeles, sin rotaciones arbitrarias
  que rompan la retícula.

## 4. Convención de nombres de hojas

- `assets/art/sprites/<subject>.png` — minúsculas, `snake_case`, extensión
  `.png`. Nunca espacios ni mayúsculas.
- Hojas de actor: `player_sheet.png`, `zombie_<kind>.png` donde
  `<kind> ∈ {walker, runner, tank, spitter, screamer}`.
- Hojas de apoyo: `effects.png` (fogonazos, salpicaduras, impactos),
  `tiles.png` (suelo, muro, escombros, manchas).
- Layout canónico: actor = 4 frames por animación, 8 columnas por fila;
  `player_sheet` = 12 animaciones × 4 = 48 frames (8×6); cada hoja zombi =
  8 animaciones × 4 = 32 frames (8×4). Las celdas se numeran en orden de
  lectura (fila 0 primero, izquierda→derecha).

## 5. Animaciones canónicas

- Jugador (12): `idle, walk, run, attack_melee, attack_pistol, attack_shotgun,
  attack_rifle, reload_pistol, reload_shotgun, reload_rifle, hurt, death`.
- Zombi (8): `idle, walk, run, attack, hit, hurt, death, crawl`.
  `hurt` es el nombre canónico; `hit` se conserva por compatibilidad.

## 6. Regeneración

```
python3 tools/gen_art.py            # genera/sobrescribe las hojas
python3 tools/gen_art.py --check    # solo verifica; no escribe nada
```

El modo `--check` valida firma PNG, IHDR, dimensiones múltiplos de 32 y que
todos los píxeles opacos pertenecen a la paleta. La salida es determinista:
regenerar produce bytes idénticos.

## 7. Addendum — Skin de zombi de rango bajo

El pack de skin del walker vive en `assets/enemies/zombie/` y sigue una
retícula propia, separada de las hojas canónicas de 32×32:

- Celda de **64×64 px**, **PPU 64** y pivot de nodo en el **centro
  `(0.5, 0.5)`**.
- El personaje queda **centrado en la celda**, no anclado a los pies. El ancla
  se calcula una sola vez a partir del bbox opaco de la **unión de todos los
  frames del pack, de todas las animaciones**; esa caja se centra en 64×64 y
  todos los frames reciben la misma traslación global. Nunca se reencuadra un
  frame usando el bbox de su propio frame: así el personaje no patina entre
  frames ni entre animaciones.
- La paleta es exactamente la misma paleta canónica de **16 colores** de la
  sección 2. No se permiten colores nuevos.

Layout y mapa al runtime canónico:

| Clip del pack | Frames | Animación canónica del runtime |
|---|---:|---|
| `idle` | 2 | `idle` |
| `walk` | 5 | `walk` |
| `walk_alt` | 3 | `run` |
| `attack` | 6 | `attack` |
| `attack_alt` | 2 | `hit` |
| `special` | 4 | `hurt` |
| `rise` | 5 | `crawl` |
| `death` | 6 | `death` |

`rise` representa un **arrastre continuo en el suelo** (la acción canónica
`crawl`), no un levantamiento: el runtime lo reproduce en bucle. El clip usa
un bob vertical lógico de `[0, -1, 0, 1, 0]` y no desplaza el sprite en
horizontal.

El pack tiene su propia puerta de CI:

```
python3 tools/gen_zombie_skin.py            # genera/sobrescribe el pack
python3 tools/gen_zombie_skin.py --check    # verifica; no escribe nada
```

`gen_zombie_skin.py --check` regenera los 33 frames y 8 strips en memoria y
compara dimensiones, píxeles y bytes PNG con el disco, además de validar el contrato
estructural. Este pack queda **fuera del alcance de `gen_art.py --check`**:
esa puerta valida únicamente las 9 hojas canónicas de 32×32.

`game/tools/skin_pack.py` audita e importa packs externos. El pack entregado
por el autor (`~/zombie_sprites/`) es el ejemplo canónico de pack defectuoso:
contiene tarjetas de color sin silueta, cuatro frames vacíos, tamaños variables
y strips que no se pueden rebanar en celdas de 64 px. La importación exige un
`--out` explícito y se niega a sobrescribir `assets/enemies/zombie/` sin
`--force`.

Además, `import` **rechaza** (código 2, sin escribir nada) cualquier pack con
frames «tarjeta de color»: una tarjeta no tiene silueta y ninguna
normalización —recuadrar, rellenar frames vacíos o cuantizar la paleta— puede
inventarla. Importar una tarjeta dejaría un rectángulo de color en pantalla.
`--force` permite la importación aun así, con un aviso explícito.

Comandos:

```
python3 tools/skin_pack.py audit <pack>      # informa; rc=1 si hay incidencias
python3 tools/skin_pack.py import <pack> --out <destino> [--force]
python3 tools/skin_pack.py check              # valida el pack canonico
```

`audit` distingue las incidencias **mecánicas** (frames vacíos, tamaños
variables, strips no rebanables, colores fuera de paleta) de las **de calidad**
(tarjetas sin silueta). Las mecánicas se pueden reparar al importar; las de
calidad no.
