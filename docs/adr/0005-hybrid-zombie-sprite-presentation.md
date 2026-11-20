# ADR-005: Presentación híbrida de los zombis: skin de sprites para el rango bajo y cubo para los rangos altos

- **Status**: accepted
- **Date**: 2026-11-20
- **Amended**: 2026-11-20 (R2-hotfix, revisión adversarial; el registro original se conserva)
- **Deciders**: Lead Orchestrator + subagentes ECC
- **Technical Story**: Ronda R2 de integración de la presentación de zombis
- **Supersedes (parcialmente)**: [ADR-004](0004-revert-presentation-and-real-lighting.md)
  únicamente en su §1, «Presentación: cubo simple, con el banco de arte
  conservado». La iluminación, las sombras proyectadas y las demás
  invariantes de ADR-004 permanecen vigentes.
- **Related**: [ADR-001](0001-pixel-art-pipeline.md), cuyo pipeline canónico pasa
  a ser también la fuente del skin de rango bajo, no solo un banco de arte.

## Context

ADR-004 devolvió la presentación runtime al cubo `Polygon2D` porque el autor
iba a producir el arte pixel-art del juego. La nueva petición es más matizada:
el zombi normal, de rango bajo, debe tener una skin de sprites, mientras que
los rangos altos conservan el cubo para que su silueta, escala y tinte sigan
leyéndose como arquetipos distintos.

El pack entregado por el autor en `~/zombie_sprites/` no puede usarse tal cual.
La auditoría reproducible implementada en `game/tools/skin_pack.py` lee RGBA,
detecta frames vacíos, tarjetas de color plano, tamaños variables y strips no
rebanables (`game/tools/skin_pack.py:209-244`,
`game/tools/skin_pack.py:251-345`). Se reproduce desde `game/` con
`python3 tools/skin_pack.py audit ~/zombie_sprites`. Sobre sus 33 frames de
animación se verificó lo siguiente:

- Cuatro frames son completamente vacíos (`alpha = 0`):
  `walk/walk_03.png`, `attack_alt/attack_alt_01.png`,
  `special/special_03.png` y `walk_alt/walk_alt_03.png`.
- Los frames con contenido son tarjetas de color plano, entre 1 y 22 colores
  opacos por frame, sin una silueta de personaje reconocible. Los cuatro
  frames vacíos y diez tarjetas se reportan como incidencias por el auditor
  (`game/tools/skin_pack.py:280-337`).
- Los anchos no son uniformes. En `attack`, por ejemplo, son
  `43/64/64/45/64/64`; el strip mide 344 px, la suma exacta de esos seis
  frames. Los strips son concatenaciones de los frames individuales, pero sus
  celdas no son de 64 px y por tanto no son rebanables con el contrato del
  runtime (`game/tools/skin_pack.py:301-317`).
- La paleta de los 33 frames de animación contiene 84 colores RGB opacos y no
  comparte ningún color con la paleta canónica de 16 colores del proyecto
  (`game/tools/gen_art.py:23-50`).

El proyecto ya tenía un banco de arte determinista y compatible: nueve hojas
canónicas, entre ellas `zombie_walker.png`, se verifican en
`gen_art.py --check` (`game/tools/gen_art.py:578-615`). El humanoide se dibuja
sobre una retícula lógica de 32×32 px y es cenital
(`game/tools/gen_art.py:52-55`, `game/tools/gen_art.py:265-267`); la biblia
prohíbe el antialiasing y fija el filtrado `NEAREST`
(`game/assets/art/ART_BIBLE.md:7-14`). Ese arte era banco de trabajo desde
ADR-004, pero no se usaba en runtime
(`docs/adr/0004-revert-presentation-and-real-lighting.md:48-63`).

La decisión debe, por tanto, conservar el fallo cerrado: un pack ausente o
incompleto nunca puede impedir que el juego arranque o que un zombi exista.
Tampoco puede alterar las hitboxes, la colisión ni la presentación de los
rangos altos.

## Decision

### 1. Alcance: solo el WALKER lleva skin

El skin se aplica únicamente a los tipos incluidos en una allowlist explícita.
A la fecha de esta decisión, la allowlist contiene solo `WALKER`, el zombi
normal de rango bajo (`game/03_zombies/ZombieVisual.gd:72-77`). Ampliarla es
una decisión de diseño explícita, no un efecto colateral de reutilizar el
mismo asset.

`RUNNER`, `TANK`, `SPITTER`, `SCREAMER` y `BOSS` («Tanque Alfa») conservan el
cubo `Body`/`Nose`, con su escala y tinte de arquetipo. Sus perfiles siguen
siendo los que define `Zombie.gd:_apply_kind()`
(`game/03_zombies/Zombie.gd:914-1052`).

### 2. El skin se genera con el pipeline canónico del repositorio

No se importa el pack externo defectuoso. El pack versionado vive en
`game/assets/enemies/zombie/` y sigue esta forma:

- frames sueltos: `game/assets/enemies/zombie/<anim>/<anim>_NN.png`;
- strips horizontales: `game/assets/enemies/zombie/<anim>_strip.png`;
- celda de 64×64 px; en el strip, la celda N comienza en `x = N * 64`.

El contrato, el recuento de frames y el mapa entre los nombres del pack y las
ocho animaciones canónicas están fijados en
`game/tools/gen_zombie_skin.py:3-30` y
`game/tools/gen_zombie_skin.py:50-86`. El generador produce 33 frames y ocho
strips; los strips se construyen concatenando frames ya normalizados
(`game/tools/gen_zombie_skin.py:246-264`).

El humanoide canónico se renderiza a 32×32 px lógicos y se escala ×2, con
vecino más próximo, a la celda de 64×64 px
(`game/tools/gen_zombie_skin.py:96-167`). Así, el PPU 64 del skin es el doble
del PPU nativo 32 del proyecto y la escala final 0.5 devuelve la retícula
lógica a su tamaño de diseño.

Todos los frames usan un **ancla global común**: se calcula el bounding box
opaco de la unión de todos los frames del pack y el personaje se coloca con
ese mismo ancla dentro de la celda de 64×64
(`game/tools/gen_zombie_skin.py:23-27`,
`game/tools/gen_zombie_skin.py:191-245`). El personaje queda centrado en la
celda y no patina entre frames ni entre animaciones. El origen del nodo, con
pivot `(0.5, 0.5)`, coincide con el centro del personaje y con el centro del
cubo.

### 3. Runtime: `AnimatedSprite2D` con atlas por celda y recursos por instancia

Se reutiliza el `AnimatedSprite2D` que ya forma parte de `Zombie.tscn`
(`game/03_zombies/Zombie.tscn:59-65`). Las ocho animaciones canónicas —`idle`,
`walk`, `run`, `attack`, `hit`, `hurt`, `death` y `crawl`— se crean siempre,
aunque el fallback al cubo las deje sin frames
(`game/03_zombies/ZombieVisual.gd:295-317`).

El runtime:

1. carga cada strip del pack;
2. crea un `AtlasTexture` por frame, con región
   `Rect2(N * 64, 0, 64, 64)`;
3. instala esas texturas en un `SpriteFrames` **por instancia**;
4. usa filtrado `NEAREST`.

La construcción de las regiones está en
`game/03_zombies/ZombieVisual.gd:242-259`. El `SpriteFrames` nunca se
comparte entre zombis porque `set_type()` cambia las velocidades de animación
y un recurso compartido contaminaría a otras instancias
(`game/03_zombies/ZombieVisual.gd:295-317`). El filtrado `NEAREST` se fija en
`game/03_zombies/ZombieVisual.gd:179-190`.

El WALKER usa escala `0.5`: 64 px de textura se convierten en 32 unidades.
Es coherente con el cubo visible de 24×24 unidades
(`game/03_zombies/Zombie.tscn:20-26`) y con
`HouseBuilder.TILE_SIZE = 64` (`game/05_house/HouseBuilder.gd:11`), es decir,
1 unidad de mundo equivale a 1 px. Con skin, el offset del sprite es `(0, 0)`
porque el personaje ya está centrado en la celda
(`game/03_zombies/ZombieVisual.gd:326-341`).

El `z_index` también baja con la skin: de 5 (el de la escena, calibrado para
el arte de 32×32 del cubo) a 0. El motivo es la coherencia de profundidad: el
cubo de los zombis vive en `z_index = 0` y el vehículo en `z_index = 4`
(`game/12_vehicles/DriveableVehicle.tscn:14`), de modo que un WALKER con
sprite en `z = 5` se dibujaría **delante** del vehículo mientras el resto de
zombis se dibujan detrás. Con skin a `z = 0`, el WALKER se ordena en
profundidad igual que sus pares de rango alto
(`game/03_zombies/ZombieVisual.gd:121-126`).

### 3.1 Mapa de animaciones: pack → canónica

El runtime siempre declara las ocho animaciones canónicas, con o sin skin. El
pack aporta el **contenido**; el mapa declara qué clip del pack corresponde a
cada animación del runtime (`game/03_zombies/ZombieVisual.gd:84-92`):

| Clip del pack | Animación canónica | Frames | FPS | Bucle |
|---|---|---:|---:|---|
| `idle` | `idle` | 2 | 4 | sí |
| `walk` | `walk` | 5 | 8 | sí |
| `walk_alt` | `run` | 3 | 12 | sí |
| `attack` | `attack` | 6 | 12 | no |
| `attack_alt` | `hit` | 2 | 10 | no |
| `special` | `hurt` | 4 | 10 | no |
| `rise` | `crawl` | 5 | 8 | sí |
| `death` | `death` | 6 | 7 | no |

Los **fps del pack mandan sobre los del arquetipo**: la ficha del arte es la
que define el ritmo. Esto tiene una consecuencia medible —el clip de ataque
dura 6/12 = 0,5 s, exactamente el `ATTACK_FALLBACK` del bloqueo de movimiento,
así que el fin de la animación no adelanta el desbloqueo—, y es la razón por
la que `set_type()` reinstala los frames del pack **después** de fijar las
velocidades por arquetipo.

El clip `rise` se mapea a `crawl` y **debe representar un arrastre**, no un
levantamiento: `crawl` se reproduce en bucle cuando al zombi le fallan las
piernas (`Zombie.gd:_apply_crawl()`). Un `rise` reproducido en bucle se leería
como un zombi que se levanta y se tumba sin parar, no como un arrastre. El
generador canónico dibuja por tanto la pose baja de `crawl` con un bob
vertical sutil de 1 px lógico por frame.

### 4. Fallback seguro al cubo

Si falta el pack, falta uno de sus strips, la carga no puede completarse o **las
dimensiones de un strip no son las del contrato**, el zombi vuelve al cubo y el
juego continúa. `install_skin()` valida el pack, limpia frames parciales y
desactiva la skin antes de restaurar la presentación del cubo
(`game/03_zombies/ZombieVisual.gd:206-226`).

La validación de dimensiones es parte del contrato, no un detalle: el runtime
construye una región `Rect2(i*64, 0, 64, 64)` por frame, así que un strip de
64×64 donde se esperan dos celdas deja el segundo frame **fuera del atlas** (la
región se sale de la textura y el frame sale recortado o vacío). El runtime
exige alto 64 y ancho `count * 64` antes de construir las regiones, y una carga
inválida **no** se cachea: el siguiente intento vuelve a mirar el disco
(`game/03_zombies/ZombieVisual.gd:240-279`).

`install_skin()` deja la presentación **coherente con el resultado**: si el
pack carga bien y el tipo vigente lo admite, la skin queda visible; si no, el
zombi queda con el cubo. Esto permite recuperar el skin tras un fallback sin
que nadie tenga que llamar a `set_type()` otra vez. El tipo vigente se guarda
en `_current_type` porque un TANK con el pack cargado **no** debe pasar a
mostrar la skin: la allowlist manda sobre la disponibilidad del pack.

La autoridad final para elegir presentación es `ZombieVisual.set_type()`: los
tests y los spawners pueden cambiar el tipo después de instanciar el zombi,
por lo que la decisión no puede fijarse solo en `_ready()`
(`game/03_zombies/ZombieVisual.gd:361-440`).

### 5. Game feel: los FX siguen a lo visible y la orientación se rota

Squash, stretch y telegrafía se aplican al elemento que realmente se ve: la
sprite cuando hay skin y los polígonos `Body`/`Nose` cuando hay fallback al
cubo. Nunca se tocan `Collision`, `SeparationArea` ni ninguna otra hitbox. De
lo contrario, el golpe recibido por el zombi sería invisible o alteraría la
colisión (`game/03_zombies/ZombieVisual.gd:554-566`,
`game/03_zombies/ZombieVisual.gd:608-714`).

Como el arte canónico es cenital, la skin **rota** hacia la dirección de
marcha, igual que el cubo; no se espeja. El cubo mantiene su flip horizontal
legacy únicamente cuando no usa skin
(`game/03_zombies/ZombieVisual.gd:467-480`).

El clip de impacto necesita un **lock propio**. Sin frames (cubo) no hacía
falta, porque no había clip que interrumpir; con skin, `play_hit()` reproduce
un clip real y el `update_state()` del siguiente frame físico lo pisaba con
`idle`/`walk`/`run`: el golpe se veía **un solo frame**. El lock `_hit_timer`
(0,2 s, el doble de la duración del clip de 2 frames a 10 fps) mantiene el
clip visible y deja que `update_state()` recupere el control al terminar
(`game/03_zombies/ZombieVisual.gd:55`, `game/03_zombies/ZombieVisual.gd:451-486`,
`game/03_zombies/ZombieVisual.gd:738-746`). El bloqueo de ataque ya existía
con su temporizador propio y no se modifica.

La muerte también necesita su propio tiempo: el clip de muerte del pack dura
6 frames a 7 fps ≈ 0,86 s, y el desvanecido antiguo de 0,3 s cortaba el clip
en el primer frame, desperdiciando cuatro de los seis. Con skin el cadaver
permanece 0,56 s y se desvanece en los 0,3 s finales; **sin** skin el
comportamiento del cubo no cambia. La escala del nodo no se toca al morir:
encoger un cadaver parece un popping, no una caida
(`game/03_zombies/Zombie.gd:1213-1231`).

El umbral de locomoción walk/run sube de 50 a 120 px/s. El WALKER camina a
80 px/s y el RUNNER a 150 px/s (`game/03_zombies/Zombie.gd:922-944`), por lo
que el umbral anterior dejaba al zombi normal siempre en `run`. Con 120 px/s,
el WALKER usa su animación de caminar y el RUNNER conserva `run`
(`game/03_zombies/ZombieVisual.gd:114-115`,
`game/03_zombies/ZombieVisual.gd:459-465`).

## Enmienda R2-hotfix — revisión adversarial del contrato (2026-11-20)

Esta enmienda se añade como sección nueva; **no reescribe en silencio** el
apartado §5 ni la Invariante 13 del texto original. La revisión adversarial de
R2 encontró dos afirmaciones falsas en este ADR, varias puertas que podían dar
verde sin comprobar el comportamiento real y cuatro defectos de runtime. Esta
sección registra la evidencia y hace exigible el contrato corregido.

### Correcciones documentales

**E1 — el `z_index` final del vehículo (corrige §3 y la Invariante 12).** El
ADR decía que el vehículo vive en `z_index = 4`
(`game/12_vehicles/DriveableVehicle.tscn:14`) y que un WALKER con sprite en
`z = 5` se dibujaría «delante». En Godot 4.7.2, ese `4` pertenece al root
`CharacterBody2D`, que no dibuja; el `Sprite2D` visible tiene `z_index = 1` y
`z_as_relative = true`, por lo que su **z final es 5**. Con `z = 5` el WALKER
**empataba** con el vehículo y el orden dependía del árbol, no del `z_index`.
El valor elegido `SKIN_Z_INDEX = 0` sigue siendo correcto: queda detrás del
vehículo (z final 5) y en la misma profundidad que el resto de zombis.

**E2 — el lock de `hit` no era «el doble» (corrige §5).** El ADR decía que el
lock literal de `0,2 s` era el doble de un clip de 2 frames a 10 fps. La
duración del clip es exactamente `2 / 10 = 0,2 s`: el lock era **1×**, no 2×, y
se agotaba en el mismo instante en que terminaba el clip. Si el `fps` bajaba a
8, el lock cortaba la animación antes de tiempo.

**E3 — datos reales del pack del autor (corrige §1).** La auditoría
reproducible `python3 tools/skin_pack.py audit ~/zombie_sprites` devuelve 33
frames: **4 vacíos y 29 tarjetas de color** con contenido. Los frames con
contenido usan entre **1 y 42 colores RGB opacos** (los valores observados por
frame son 1, 3, 6, 11, 16, 18, 20, 21, 22 y 42). El pack contiene **84 colores
RGB fuera de la paleta canónica**. El valor «191» citado en la revisión no
procede de un frame del pack: pertenece a `zoimbie1_hold.png`, un PNG suelto
de 35×43 que no forma parte de la animación auditada.

**E4 — las citas apuntaban al código equivocado (corrige §1).** La auditoría
real está en `game/tools/skin_pack.py:533-664`; `check()` está en
`:729-...`, `selftest()` en `:900-...` e `import_pack()` en `:1074-...`. Las
citas anteriores al editor PNG y a las constantes no describían la auditoría.

**E5 — `animation_finished` sí puede adelantar el desbloqueo (corrige §3.1).**
`ZombieVisual._on_animation_finished()` pone `_is_attacking = false` y
`_attack_timer = 0.0`. Por tanto, la afirmación de que el fin de la animación
nunca adelanta el desbloqueo no estaba respaldada por el código. El lock de
ataque sigue siendo el mecanismo de gameplay; esta enmienda no promete una
garantía que el runtime no tiene.

**E6 — el alcance de `gen_art.py --check` cambió con ADR-006.** Hasta `8d4a4dd`
(R3) la puerta verificaba las nueve hojas canónicas de entonces; los commits
etiquetados R2 posteriores (`de970db` y sus hotfixes, incluido `7f16a2d`) ya
usaban cinco. En el estado vigente de R3 el banco se redujo a **cinco hojas** (`player_sheet.png`,
`zombie_walker.png`, `boss_sheet.png`, `effects.png`, `tiles.png`), además de
los dos mapas de luz y la máscara `sun_shadow.png`. El pack del skin sigue
teniendo sus propias puertas (`gen_zombie_skin.py --check` y
`skin_pack.py check|selftest`) y **no** forma parte del alcance de
`gen_art.py --check`. Esta enmienda deja explícita la diferencia sin reescribir
la decisión histórica de R2.

### Correcciones de runtime y de puertas

- **C1 — lock derivado del pack.** Con skin, el lock es
  `count / fps * HIT_LOCK_MARGIN`, con `HIT_LOCK_MARGIN = 1.5`; la fórmula
  exigida es **`count / fps * 1.5`**. Se deriva de
  `ZombieVisual.SKIN_ANIMATIONS` (`game/03_zombies/ZombieVisual.gd:102`,
  `:862`). El fallback al cubo conserva `HIT_FALLBACK = 0,2 s`.
  **Lock del cubo: `0.2 s`.** `ZombieSkinTest` exige el valor derivado y
  prueba por separado el lock del cubo.
- **C2 — reintento real de skin.** Un fallo de carga ya no deja al zombi ciego
  para siempre. `ZombieVisual` recuerda el directorio intentado y lo reintenta
  desde `_process()` (`game/03_zombies/ZombieVisual.gd:245`, `:315`) con un
  cooldown y backoff **compartidos por ruta** (250 ms iniciales, máximo 5 s).
  Una carga correcta borra la entrada; una horda no genera una estampida. Las
  APIs públicas `skin_load_attempts()` y `skin_attempted_dir()` hacen el
  contrato observable.
- **C3 — el cadáver no queda congelado en rojo.** `Zombie.gd:_die()` restaura
  `modulate = Color.WHITE` antes de desactivar `_physics_process`, de modo que
  el tinte del golpe no queda congelado durante la muerte. `ZombieSkinTest`
  comprueba el color con tolerancia `0.001`.
- **C4 — el importador no puede destruir su entrada.** Si `out` y el pack
  fuente son el mismo directorio, `import_pack()` devuelve **2**, no escribe
  nada y conserva el origen. `skin_pack.py selftest` lo exige por código de
  salida y compara una huella SHA-256 del árbol antes y después.
- **C5 — la deriva de `fps` ya no es invisible.** `ZombieSkinTest` acota el
  parser al bloque `SKIN_ANIMS` del generador, exige exactamente ocho clips y
  ocho claves únicas y cruza `fps`, `count`, bucle y nombre canónico con
  `ZombieVisual.SKIN_ANIMATIONS`. El mapa duplicado `CANONICAL_MAP` se elimina:
  el nombre canónico vive en la propia tupla `SKIN_ANIMS`.
- **C6 — la puerta del estilo visual deja de ser tautológica.**
  `VisualStyleTest` ya no acepta que `ART_BIBLE.md` contenga la cadena suelta
  `"32"`; exige `32×32`, `32 px` o `32x32` con su unidad.

### Hallazgos aceptados sin cambio

- `set_modulate_color()` y `get_sprite_rect()` se conservan como API pública
  paralela a `PlayerVisual`; no tienen llamantes activos, pero retirarlos
  ampliaría el alcance del hotfix.
- No se abre deuda por el rollback de un `--force` sobre el pack canónico: el
  pack es determinista y `gen_zombie_skin.py --check` lo regenera byte a byte;
  `skin_pack.py check` detecta además una instalación incompleta.
- `_is_dying` no se limpia porque hoy no existe un pool de zombis que reutilice
  la instancia. Queda anotado para cuando ese pool exista.

### Invariante añadida

**Ninguna puerta puede depender de un valor que el arte pueda cambiar:** el
lock del golpe se deriva del pack, la puerta de `fps` cruza generador y runtime,
el importador no puede sobrescribir su propia entrada y el reintento de skin
ocurre en el ciclo de vida real con backoff compartido.

## Enmienda R2-hotfix4 — importador transaccional y backoff observable (2026-11-20)

Esta enmienda amplía el cierre R2 sin reescribir el registro `accepted` del ADR.
La segunda revisión adversarial exigía que el contrato de entrada del skin y el
reintento runtime fueran comprobables **por comportamiento**, no solo por
búsquedas de texto o por un caso feliz.

### Correcciones del importador

- **Relación de rutas por identidad real.** El destino no puede ser el origen,
  un alias del mismo directorio, un descendiente del origen ni un ancestro que
  lo contenga. La comparación usa `samefile()` y `realpath()`; `commonpath()`
  resuelve la contención y trata `ValueError` (por ejemplo, volúmenes
  distintos) como «no contenido», nunca como una coincidencia por prefijo de
  texto.
- **Preflight completo antes de escribir.** Se calculan primero todos los
  directorios y ficheros planificados. Se rechazan los enlaces simbólicos, los
  directorios que ya son ficheros y los ficheros que ya son directorios. El
  rechazo ocurre antes de construir el staging y no modifica origen ni destino.
- **Publicación transaccional.** El pack completo se construye en un staging
  sibling. La publicación mueve el destino anterior a un backup sibling y
  publica el staging mediante `os.replace`; si falla, restaura el destino
  anterior. Un fallo intermedio limpia el staging y devuelve **rc=2** sin
  salida parcial.
- **Destino no vacío por defecto.** Sin `--force`, un destino no vacío se
  rechaza sin borrar contenido ajeno. Con `--force`, el destino se reemplaza
  por el conjunto exacto importado —**33 frames y 8 strips**—, por lo que no
  conserva frames obsoletos ni ficheros extra.
- **Errores de filesystem sin traceback.** Un `OSError` se traduce en un
  diagnóstico y **rc=2**; la puerta nunca afirma que existe una salida parcial
  cuando el pack completo ya se publicó.

### Correcciones del reintento runtime

El cooldown compartido por ruta queda fijado a la secuencia exacta
**250 → 500 → 1000 → 2000 → 4000 → 5000 → 5000 ms**. El cálculo es una función
pura y cada fallo posterior duplica el intervalo hasta el tope de 5000 ms. Una
carga exitosa borra el estado de retry de la ruta y restaura la skin visible;
por tanto, el siguiente fallo vuelve al primer intervalo y no hereda un
cooldown de una recuperación anterior. El `HIT_FALLBACK = 0,2 s` del cubo sigue
siendo un valor **independiente** del lock derivado `count / fps * 1,5` de la
skin.

### Puertas exigibles

`skin_pack.py selftest` cubre ahora la identidad de rutas, el preflight, el
rollback de una publicación sobre un destino existente, el conjunto exacto de
`--force`, el destino no vacío y el `OSError` intermedio. `ZombieSkinTest`
exige la secuencia completa del backoff, la recuperación posterior de la misma
ruta y la cancelación del estado de retry tras un éxito. Los controles
negativos revierten cada corrección y deben producir una puerta roja.

### 6. Puertas de CI propias, sin ampliar el alcance del pipeline antiguo

El pack nuevo tiene **tres** verificaciones independientes (comandos ejecutados
desde `game/`):

- `python3 tools/gen_zombie_skin.py --check` reconstruye y compara byte a
  byte los 33 frames y los 8 strips, además de comprobar el contrato
  estructural (recuento y celdas de 64×64); la comprobación está en
  `game/tools/gen_zombie_skin.py:292-467`.
- `python3 tools/skin_pack.py check` verifica que cada strip coincide
  con la concatenación normalizada de sus frames
  (`game/tools/skin_pack.py:754-780`, con la concatenación normalizada en
  `game/tools/skin_pack.py:386-402`).
- `python3 tools/skin_pack.py selftest` es la **regresión del importador**:
  monta un pack sintético y comprueba que un pack sin silueta se rechaza sin
  escribir nada, que un destino con enlaces simbólicos no deja escribir fuera,
  que un PNG corrupto produce un diagnóstico y que `audit` de un pack
  inválido devuelve rc=1. Comprueba además que un pack **válido** se importa
  con rc=0, para que los rechazos no sean verdes triviales
  (`game/tools/skin_pack.py:889-987`).

Las tres se ejecutan en el mismo paso del CI y se reportan juntas: un fallo no
impide ver el resultado de las otras
(`.github/workflows/ci.yml:90-123`).

Hasta `8d4a4dd` (R3), `python3 tools/gen_art.py --check` verificaba las nueve
hojas canónicas de entonces y sus mapas de luz, **no** el pack nuevo; los
hotfix de R2 ya usaban cinco hojas. **El alcance vigente cambió con ADR-006:**
la puerta verifica ahora las **cinco hojas** del banco R3, los dos mapas de luz
y la máscara `sun_shadow.png`; el pack canónico del skin sigue teniendo su
propio generador y queda fuera de su alcance. Esta enmienda añade además la
comparación byte-a-byte, la allowlist de seis efectos, el rechazo de PNG extra
en los tres directorios y `rc=2` para argumentos CLI desconocidos.

### 7. Relación con ADR-004

ADR-004 queda **parcialmente superado por ADR-005** solo en su decisión de
presentar todos los zombis como cubo (`docs/adr/0004-revert-presentation-and-real-lighting.md:46-63`).
No se reescribe ADR-004: el índice declara los ADR inmutables
(`docs/adr/README.md:3-5`). La iluminación nocturna real, el faro, las
sombras proyectadas, el tuning, la música y las demás invariantes de ADR-004
continúan vigentes sin cambios
(`docs/adr/0004-revert-presentation-and-real-lighting.md:65-124`).

## Alternatives Considered

### (a) Importar el pack entregado tal cual

- **Pros**: no requiere una segunda fuente de arte; conserva exactamente los
  archivos recibidos.
- **Cons**: cuatro frames están vacíos; las tarjetas planas no representan a un
  personaje; los anchos variables impiden rebanar los strips; cuatro de los
  ocho strips no se pueden dividir en celdas de 64 px; la paleta no comparte
  ningún color con la paleta canónica.
- **Why not**: el pack no satisface su propio contrato de animación. Importarlo
  produciría frames ausentes, movimientos entre celdas incorrectos y una
  ruptura visual de la paleta.

### (b) Usar sprites para todos los zombis

- **Pros**: presentación uniforme; menos ramas de runtime; una sola silueta
  sobre la que aplicar todos los efectos.
- **Cons**: obliga a fabricar o adaptar skins para `RUNNER`, `TANK`,
  `SPITTER`, `SCREAMER` y `BOSS`; diluye las diferencias de arquetipo que hoy
  aportan cubo, tinte y escala; aumenta memoria y superficie de sustitución.
- **Why not**: la petición es jerárquica: el skin mejora al zombi normal de
  rango bajo, mientras los rangos altos necesitan conservar una lectura
  fuerte de arquetipo.

### (c) Quedarse solo con el cubo

- **Pros**: la solución más simple y estable; cero assets y cero gateways de
  carga; ningún cambio de contrato visual.
- **Cons**: no cumple la nueva petición; el zombi normal sigue siendo un
  prototipo geométrico y no aprovecha el banco de arte ya existente; el
  trabajo de animaciones del pack no aporta nada al juego.
- **Why not**: ADR-004 reversó temporalmente el uso runtime del pipeline por
  una expectativa de arte futuro. ADR-005 concreta una solución de menor
  alcance y con fallback seguro.

## Consequences

### Positive

- El WALKER deja de ser un cubo genérico y obtiene una silueta y ocho
  animaciones sin perder la lectura de arquetipo de los rangos altos.
- El skin conserva el carácter determinista, el `NEAREST` y la paleta canónica
  del proyecto; el pack se puede regenerar y comparar byte a byte.
- La presentación nunca bloquea el juego: un recurso ausente o incompleto
  degrada al cubo.
- El contrato de 64×64, ancla global y pivot centrado desacopla el runtime
  del origen del arte: el futuro arte del autor no exige cambios de código.
- El umbral walk/run hace visible la animación de caminar del WALKER sin
  alterar la locomoción real del RUNNER.

### Negative

- El runtime mantiene dos representaciones y dos rutas de FX. La selección
  debe seguir siendo determinista y comprobable para que no aparezcan
  presentaciones mixtas.
- El pack carga ocho strips de 64 px de alto. En RGBA8 sin compresión, los
  33 frames de strip ocupan aproximadamente 528 KiB de píxeles por proceso,
  más el coste de importación/formato de Godot y los metadatos de los
  `AtlasTexture` creados por instancia. Las texturas se cachean por proceso,
  pero los `SpriteFrames` siguen siendo por instancia.
- El `LightOccluder2D` actual es un cuadrado de 24×24 unidades
  (`game/03_zombies/Zombie.tscn:9-12`,
  `game/03_zombies/Zombie.tscn:31-32`). La sombra proyectada será cuadrada y
  el oclusor no seguirá la silueta de la sprite.
- La rotación de un sprite pixel-art puede producir bordes irregulares fuera
  de la retícula aunque el filtrado sea `NEAREST`.
- El pack canónico es **arte de banco**, no arte final del autor: mejora la
  legibilidad, pero la calidad visual definitiva queda pendiente.

### Risks

- Que el fallback oculte un pack roto en desarrollo → mitigación: las dos
  puertas de CI verifican los 33 frames y los 8 strips antes de integrar.
- Que una sustitución futura cambie el ancla, el pivot o el tamaño de celda y
  introduzca patinado → mitigación: el importador y las comprobaciones deben
  validar el mismo contrato de 64×64, ancla global y origen centrado.
- Que el cubo alto y el skin bajo diverjan en escala aparente → mitigación:
  la escala del skin se fija en 0.5 y el cubo conserva sus escalas por
  arquetipo; ninguna de las dos rutas altera hitboxes.

## Invariants

Las siguientes reglas deben seguir siendo verdad:

1. Un pack ausente, incompleto o inválido produce fallback al cubo; nunca
   impide instanciar ni actualizar un zombi.
2. `RUNNER`, `TANK`, `SPITTER`, `SCREAMER` y `BOSS` siguen mostrándose con el
   cubo `Body`/`Nose`, su silueta, escala y tinte.
3. `Collision`, `SeparationArea` y las demás hitboxes no cambian de tamaño,
   forma, posición ni layer (`game/03_zombies/Zombie.tscn:6-12`,
   `game/03_zombies/Zombie.tscn:28-32`).
4. Squash, stretch y telegrafía solo alteran lo visible; nunca una hitbox.
5. El runtime mantiene exactamente las ocho animaciones canónicas y sus
   estados de `idle`, `walk`, `run`, `attack`, `hit`, `hurt`, `death` y
   `crawl`.
6. Cada frame usa el ancla global común; el personaje está centrado en la
   celda, el offset es `(0, 0)` y el pivot `(0.5, 0.5)` coincide con el centro.
7. El `SpriteFrames` es por instancia; las texturas pueden cachearse, pero las
   velocidades por arquetipo nunca se comparten.
8. El filtrado es `NEAREST`; el skin solo usa la paleta canónica de 16
   colores y transparencia.
9. La decisión de presentación se toma en `set_type()`, después de cualquier
   cambio de tipo posterior a la instanciación.
10. La orientación del skin se resuelve rotando hacia la marcha, sin espejar
    una sprite que ya está orientada.
11. La visibilidad es **exclusiva**: `AnimatedSprite2D` y `Body`/`Nose` nunca
    son visibles a la vez, en ningún tipo y en ningún estado.
12. Con skin, el `z_index` del sprite es 0, igual que el del cubo: el WALKER
    no puede dibujarse por delante del vehículo (`z = 4`) mientras los demás
    zombis quedan detrás.
13. `play_hit()` deja un lock de 0,2 s: el clip de impacto no puede ser
    sobrescrito por el `update_state()` siguiente.
14. `install_skin()` termina siempre con la presentación coherente con el
    resultado: skin visible si el pack cargó y el tipo la admite, cubo en
    cualquier otro caso.
15. El runtime **valida las dimensiones de cada strip** antes de construir las
    regiones: alto 64 y ancho `count * 64`. Un strip más corto deja los
    últimos frames fuera del atlas; uno más alto desalinea las celdas. Un pack
    con dimensiones incorrectas produce fallback al cubo, no una animación
    rota (`game/03_zombies/ZombieVisual.gd:240-279`).
16. La muerte es la dueña del estado visual: `play_death()` cancela los tweens
    de FX y restaura escala y tinte antes de reproducir el clip de muerte. Un
    zombi que muere durante una telegrafía no queda deformado
    (`game/03_zombies/ZombieVisual.gd:766-777`).
17. El importador **no escribe fuera del destino**: un destino con enlaces
    simbólicos se rechaza con código 2 sin escribir nada, y los ficheros se
    escriben con temporal + `os.replace` (que no sigue enlaces)
    (`game/tools/skin_pack.py:1039-1156`).
18. `audit` trata las incidencias **estructurales** (animaciones o strips que
    faltan, recuentos que no coinciden con la ficha, strips no rebanables o
    con un número de celdas incorrecto) como incidencias de pleno derecho:
    devuelve rc=1 también con ellas (`game/tools/skin_pack.py:532-665`).
19. El rechazo de los packs sin silueta, la protección frente a los enlaces
    simbólicos, el diagnóstico de los PNG corruptos y el falso verde de
    `audit` tienen **regresión automatizada** en `skin_pack.py selftest`, que
    es una puerta de CI (`game/tools/skin_pack.py:889-987`).

## Sustitución por el arte final del autor

El arte final entra por el mismo contrato, sin cambiar el código de runtime:

1. El autor entrega los frames en una estructura compatible con
   `<anim>/<anim>_NN.png`.
2. `python3 tools/skin_pack.py import <directorio-origen> --out <destino>`
   importa y normaliza los frames: celda de 64×64, ancla global común,
   centrado del personaje y origen `(0.5, 0.5)`. El destino es obligatorio y
   el importador se niega a escribir sobre el pack canónico sin `--force`.
   El importador **rechaza** (código 2, sin escribir nada) los packs con
   frames «tarjeta de color»: una tarjeta no tiene silueta y ninguna
   normalización puede inventarla. `--force` permite la importación con un
   aviso explícito.
3. El importador genera los ocho strips con la celda N en `x = N * 64` y
   valida que el resultado sea completo y consistente.
4. Se ejecutan `gen_zombie_skin.py --check` y `skin_pack.py check` para
   verificar bytes, dimensiones y correspondencia entre frames y strips.
   Cuando el arte importado pasa a ser la nueva baseline, la puerta
   determinista debe verificar esos bytes en lugar de regenerar el placeholder;
   ese ajuste se limita a las herramientas y sus fixtures, no al runtime.
5. `ZombieVisual` sigue leyendo `game/assets/enemies/zombie/`; no necesita
   conocer el origen, el nombre de los archivos fuente ni el formato previo.

La sustitución solo es válida si conserva el contrato de celda, ancla y
pivot. Un cambio de contrato requiere otro ADR, no un ajuste ad hoc del
runtime.

## Enmienda R4 — la fuente de píxeles es el sprite real (ADR-007)

Esta sección **no reescribe** §2 ni el registro accepted: lo enmienda en un
solo punto, la fuente de los píxeles. El pack sigue generándose con
`game/tools/gen_zombie_skin.py` y sigue cumpliendo el contrato de celda
64×64, PPU 64, pivot `(0.5, 0.5)`, ancla global de la unión, ocho clips,
33 frames, ocho strips, paleta de 16 colores y fallback seguro al cubo.

Lo que cambia es de dónde salen los píxeles. El humanoide procedural de
`draw_humanoid` deja de ser la fuente: el pack se deriva de
`game/tools/art_source/zoimbie1_hold.png`, el sprite cenital de 35×43 que el
autor entregó en Descargas. El generador lo rota 90° en sentido antihorario
(el original mira a la derecha; el runtime espera «adelante» en −Y), le aplica
alpha binario y la paleta canónica, lo escala a 60×49 con vecino más próximo
y deriva los 33 frames con transforms enteros (bob, balanceo, estocada,
retroceso, derrumbe y arrastre). No hay frames oficiales que extraer: el
Unity de origen solo contiene esa `Texture2D`/`Sprite`.

La fuente queda fijada por SHA-256
(`61df3e84c18409b698b56273a0bd014f86a23dc5622380d5d10b82124afff84e`) y el
generador falla si cambia. `ZombieSkinTest._source_asset_checks()` exige el
PNG, su hash, sus dimensiones, una silueta real y que el generador lea esa
fuente. El resto de las puertas (`gen_zombie_skin.py --check`,
`skin_pack.py check|selftest`) no cambian de contrato.

La decisión completa, las alternativas descartadas y la nota de procedencia
del asset están en [ADR-007](0007-zombie-skin-derived-from-real-sprite.md).
