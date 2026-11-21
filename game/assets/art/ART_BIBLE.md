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
- Hojas de actor: `player_sheet.png`, `zombie_walker.png` y `boss_sheet.png`.
  **R3 (ADR-006)**: el juego tiene UN SOLO arquetipo de zombi (el caminante);
  el «Tanque Alfa» es un perfil del mismo zombi y usa `boss_sheet.png` como
  hoja de banco. Ya no se fabrican hojas de arquetipos eliminados.
- Hojas de apoyo: `effects.png` (salpicaduras, fogonazos, chispas, polvo,
  goteo y pequeñas explosiones genéricas; sin efectos ligados a arquetipos
  retirados), `tiles.png` (suelo, muro, escombros, manchas).
  `effects.png` conserva ocho celdas: las seis primeras pertenecen a la
  allowlist genérica y las dos últimas son transparentes.
- Mapas de luz (no son hojas de personaje): `assets/art/lights/light_cone.png`
  (cono del faro) y `assets/art/lights/light_halo.png` (halo del jugador).
- Máscara de sombra: `assets/art/shadows/sun_shadow.png` (64×64). Es una
  **máscara en canal alfa**, no una hoja con silueta: ver §8.
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
todos los píxeles opacos pertenecen a la paleta. Además, regenera las cinco
hojas, los dos mapas de luz y la máscara de sombra **en memoria** y compara
sus bytes con el disco: un PNG válido pero obsoleto hace fallar la puerta.
En `effects.png` exige además que solo las seis celdas de la allowlist
contengan píxeles y que las dos restantes sean transparentes. La salida es
determinista: regenerar produce bytes idénticos.

## 7. Addendum — Skin de zombi (caminante y perfil BOSS)

El pack de skin vive en `assets/enemies/zombie/` y lo usan tanto el caminante
como el **perfil BOSS** del Tanque Alfa: el jefe reutiliza el mismo sprite y
pack, con escala propia. `boss_sheet.png` es una **hoja de reserva del banco**,
no la presentación runtime del jefe. El pack sigue una retícula propia,
separada de las hojas canónicas de 32×32:

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
- **Fuente (R4 / ADR-007).** Los píxeles no se redibujan con el humanoide
  procedural: se derivan de `tools/art_source/zoimbie1_hold.png`, el sprite
  cenital de **35×43** que el autor entregó. El generador fija su **SHA-256**
  y falla si la fuente cambia. El original mira a la derecha; se rota **90° en
  sentido antihorario** para que el eje local −Y sea «adelante», se le aplica
  alpha binario (umbral 160) y la paleta de 16 colores (con un mapa explícito
  para los tonos dominantes), y se escala a **60×49** con vecino más próximo.
  La animación se deriva con transforms enteros sobre esa base: no hay frames
  oficiales en el Unity de origen.

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
`crawl`), no un levantamiento: el runtime lo reproduce en bucle. El clip
comprime la base al **55 %** de su altura y la ancla abajo, con un bob de
±1 px; no desplaza el sprite en horizontal. Todos los frames de `rise` deben
ser más bajos que todos los de `walk` y quedar en la mitad inferior del pack:
es una condición que comprueban `gen_zombie_skin.py --check` y
`skin_pack.py check`.

El pack tiene su propia puerta de CI:

```
python3 tools/gen_zombie_skin.py            # genera/sobrescribe el pack
python3 tools/gen_zombie_skin.py --check    # verifica; no escribe nada
```

`gen_zombie_skin.py --check` regenera los 33 frames y 8 strips en memoria
**desde la fuente fijada por SHA-256** y compara dimensiones, píxeles y bytes
PNG con el disco, además de validar el contrato estructural. Este pack queda
**fuera del alcance de `gen_art.py --check`**: esa puerta valida las 5 hojas
canónicas de 32×32, los 2 mapas de luz y la máscara de sombra (§8).

Las reglas del pack (celda, centrado, margen, paleta, semántica de `rise` y
unión global) viven en **una sola** función, `skin_pack.validate_pack_contract()`,
que consumen `gen_zombie_skin.py --check` y `skin_pack.py check`: antes cada
puerta tenía su propia copia y ya habían divergido. El contrato exige además
**completitud**: exactamente las ocho animaciones canónicas con su número de
frames (33) y nada más; un pack mutilado (por ejemplo, solo `idle`) ya no
pasa aunque cada frame individual sea correcto.

Además, `--check` ejecuta un **control de derivación**: perfora un píxel
interior de la fuente (sin tocar la silueta) y exige que el pack **cambie**.
Es la garantía de que lo que se ve en pantalla procede del sprite pedido y no
de un dibujo procedural que pasara la comprobación del hash. Ese control se
sometе a sí mismo en `gen_zombie_skin.py --selftest` (derivación real,
derivación neutralizada y derivación que revienta al mutar).

`game/tools/skin_pack.py` audita e importa packs externos. El pack entregado
por el autor (`~/zombie_sprites/`) es el ejemplo canónico de pack defectuoso:
contiene **4 frames vacíos y 29 tarjetas de color** sin silueta, tamaños
variables y strips que no se pueden rebanar en celdas de 64 px. Los frames con
contenido usan entre **1 y 42 colores RGB opacos** y el pack suma **84 colores
fuera de la paleta canónica**. La importación exige un `--out` explícito y se
niega a sobrescribir `assets/enemies/zombie/` sin `--force`. El **único PNG
válido** de ese material es `zoimbie1_hold.png` (35×43), que no forma parte de
los 33 frames auditados: es la fuente del pack canónico (ADR-007).

Además, `import` **rechaza** (código 2, sin escribir nada) cualquier pack con
frames «tarjeta de color»: una tarjeta no tiene silueta y ninguna
normalización —recuadrar, rellenar frames vacíos o cuantizar la paleta— puede
inventarla. Importar una tarjeta dejaría un rectángulo de color en pantalla.
`--force` permite la importación aun así, con un aviso explícito.

El importador tampoco escribe **fuera** del directorio pedido: si el destino
contiene enlaces simbólicos (un `out/<anim>` que apunte a otro directorio, o un
`out/<anim>_strip.png` que sea un enlace a un fichero), la importación se
rechaza con código 2 **sin escribir nada**. Los ficheros se escriben en un
temporal del mismo directorio y se renombran con `os.replace`, que no sigue
enlaces.

Comandos:

```
python3 tools/skin_pack.py audit <pack>      # informa; rc=1 si hay incidencias
python3 tools/skin_pack.py import <pack> --out <destino> [--force]
python3 tools/skin_pack.py check              # valida el pack canonico
python3 tools/skin_pack.py selftest           # autopruebas del importador
```

`audit` distingue las incidencias **mecánicas** (frames vacíos, tamaños
variables, strips no rebanables, colores fuera de paleta) de las **de calidad**
(tarjetas sin silueta). Las mecánicas se pueden reparar al importar; las de
calidad no. Las **estructurales** —faltan animaciones o strips, el número de
frames no coincide con la ficha, un strip no se puede rebanar o no tiene las
celdas esperadas— son incidencias de pleno derecho: `audit` devuelve **rc=1**
también con ellas (un directorio vacío es un pack inválido, no un pack «sin
incidencias»).

`selftest` es la puerta de CI del importador: monta packs sintéticos y
comprueba, sin tocar el proyecto, que (1) un pack con una tarjeta de color se
rechaza sin escribir nada, (2) un destino con enlaces simbólicos no permite
escribir fuera, (3) un PNG corrupto produce un diagnóstico (`ValueError`) y no
un *traceback*, (4) `audit` de un pack inválido devuelve rc=1, (5) un pack
válido se importa con rc=0 y (6) `import --out` sobre el propio pack de origen
se rechaza con **rc=2** sin modificarlo. La comparación de integridad usa
**SHA-256**, no MD5.

## 8. Addendum — R3: máscara de sombra solar acotada (ADR-006)

La sombra direccional 2D de Godot **no tiene largo**: llega hasta el borde de
pantalla (`z_far = 2 * to_edge_distance + cull_distance` en el motor), y
`DirectionalLight2D.max_distance` no la acorta. Las sombras **diurnas** son por
tanto **manchas** dibujadas por `game/08_ui/SunShadowController.gd`, con una
cota dura de 48 px en el eje largo y en el transversal. Cada mancha se ancla
**exactamente** al centro mundial del polígono real del oclusor y su eje largo
coincide con la dirección proyectada de la sombra. Usa `light_mask = 0` y un
`CanvasItemMaterial` `UNSHADED`: Godot 4.7 ignora `light_mask` para la
`DirectionalLight2D`, por lo que el material es imprescindible para que el sol
no aclare la mancha.

- `assets/art/shadows/sun_shadow.png` — **64×64**, elipse suave: opaca en el
  centro y transparente en el borde (`alpha = (1 - d)^1.6`, `d` = distancia
  normalizada al centro).
- Es una **máscara en canal alfa**, no una hoja con silueta: **no** está
  bloqueada por la paleta de 16 colores de la sección 2. El color y la
  elongación los pone el runtime; la máscara solo aporta la forma.
- `gen_art.py --check` la valida aparte (`check_shadows()`): exige 64×64, un
  centro opaco (alpha ≥ 240), una esquina transparente (alpha = 0) y al menos
  8 niveles de alpha distintos (es decir, un degradado real, no un disco duro).
- El faro **nocturno** no usa esta máscara: sigue siendo una `PointLight2D` con
  `light_cone.png` y **sombras reales del motor**.
