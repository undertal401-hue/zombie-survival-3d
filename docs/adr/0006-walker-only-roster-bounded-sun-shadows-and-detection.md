# ADR-006: Roster de un solo arquetipo, sombras solares acotadas y detección del jugador reforzada

- **Status**: accepted
- **Date**: 2026-11-20
- **Deciders**: Lead Orchestrator + subagentes ECC
- **Technical Story**: Ronda R3 (eliminar arquetipos, daytime realista, mejor detección)
- **Supersedes (parcialmente)**:
  - [ADR-005](0005-hybrid-zombie-sprite-presentation.md) en su §1 («solo el WALKER
    lleva skin») y en sus invariantes 2 y 15: ya no hay rangos altos que
    conserven el cubo como presentación propia, y el cubo queda como
    **fallback** único.
  - [ADR-004](0004-revert-presentation-and-real-lighting.md) solo en el punto
    «el sol proyecta sombras direccionales 2D»: la sombra **nocturna** del faro,
    la iluminación real, el `CanvasModulate`, el acabado nocturno y el resto de
    invariantes de ADR-004 siguen vigentes sin cambios.
- **Related**: [ADR-001](0001-pixel-art-pipeline.md) (el pipeline determinista
  sigue siendo la fuente del arte; en R3 su alcance baja a cinco hojas y añade
  una máscara de sombra), [ADR-005](0005-hybrid-zombie-sprite-presentation.md)
  (contrato de skin, fallback al cubo y puertas de CI).

## Context

La ronda R3 tiene tres peticiones del usuario:

1. **Un solo arquetipo de zombi**: el normal (el que ya lleva la skin
   pixel-art), y **más normales** para compensar la descompensación que dejan
   los arquetipos eliminados. El resto de arquetipos desaparecen.
2. **Daytime realista con sombras acotadas**: hoy las sombras llegan hasta el
   borde de pantalla.
3. **Mejorar la detección del jugador**.

Y una restricción explícita: **el faro nocturno no debe romperse**. Es la
parte de la iluminación que el usuario valora expresamente.

Las tres peticiones son independientes entre sí, pero comparten una condición:
la causa raíz de la primera y de la segunda era una **intención de diseño que
el motor no puede satisfacer**, y la tercera era un **bug silencioso** de
API. Ninguna se podía resolver «poniendo un valor»; había que distinguir el
síntoma de la causa.

### Causa raíz de las sombras: la sombra direccional 2D de Godot no tiene largo

La configuración anterior era:

- `SolarLighting.tscn`: `DirectionalLight2D` con `shadow_enabled = true` y
  `max_distance = 800.0`;
- `SolarLighting.gd`: un export `shadow_max_distance` con el comentario
  *«Los objetos a más de esta distancia del centro de la cámara no proyectan
  sombra»*, reasignado en cada `_setup_sun_light()`.

Ese comentario era una **concepción errónea**, verificada contra el motor:

- **`Light2D` no tiene `shadow_max_distance` en Godot 4.** Sonda con
  `ClassDB.class_get_property_list("Light2D")` en Godot 4.7.2: las únicas
  propiedades de sombra son `shadow_enabled`, `shadow_color`, `shadow_filter`,
  `shadow_filter_smooth` y `shadow_item_cull_mask`. El export
  `shadow_max_distance` no lo consumía nadie: no era un parámetro del motor,
  era un número muerto.
- **`DirectionalLight2D.max_distance` no acorta la sombra.** Es un margen de
  *cull* (valor por defecto 10000): amplía el rectángulo de oclusores
  considerados y suma al `z_far` del atlas de sombra.
- **`PointLight2D` no tiene `max_distance`.** El `max_distance = 700.0` que
  tenía el faro del jugador (`Player.tscn`) era otro no-op.
- **El largo de la sombra direccional 2D es la geometría de la pantalla.** En
  `servers/rendering/renderer_rd/renderer_canvas_render_rd.cpp`, la función
  `light_update_directional_shadow()` calcula el `z_far` del atlas como
  `distance = to_edge_distance * 2.0 + p_cull_distance`. Un fragmento queda en
  sombra si su profundidad supera la del oclusor, así que la sombra se
  prolonga **hasta el borde de pantalla** en la dirección opuesta a la luz.

Conclusión: **ningún parámetro acota la sombra direccional 2D**. Bajar
`max_distance` solo reduce el alcance del cull; no acorta la mancha. La
pregunta «¿cómo acoto la sombra del sol?» no tiene respuesta dentro de la
`DirectionalLight2D`.

### Causa raíz de la detección: el `exclude` del rayo nunca llegaba al motor

`Zombie.gd:_has_line_of_sight_to()` hacía:

```gdscript
query.exclude = [get_rid()]
query.exclude.append(node.get_rid())   # <- se perdia
```

La propiedad `exclude` de `PhysicsRayQueryParameters2D` es un **ARRAY sin
tipo**: el getter devuelve una **copia**, así que el `append` posterior a la
asignación se hacía sobre la copia y **nunca llegaba al motor**. El rayo
impactaba siempre contra el propio jugador, la línea de visión era siempre
falsa y el zombi solo detectaba al jugador a menos de `close_sense_radius`
(105 px). El comentario del código («el jugador siempre bloquea su propia
línea de visión») describía el síntoma como si fuera una decisión de diseño.

### Estado del arte y del pipeline al inicio de la ronda

El banco de arte determinista tenía nueve hojas, **cuatro** de ellas de
arquetipos que iban a desaparecer (`zombie_runner.png`, `zombie_tank.png`,
`zombie_spitter.png`, `zombie_screamer.png`); las **cinco** que se conservan son
`player_sheet.png`, `zombie_walker.png`, `boss_sheet.png`, `effects.png` y
`tiles.png`. ADR-005 y su pack de skin (`game/assets/enemies/zombie/`)
seguían vigentes: 33 frames, 8 strips, celda 64×64, escala runtime 0.5, pivot
centrado, fallback seguro al cubo.

## Decision

### 1. Roster: un solo arquetipo, y el jefe como perfil

`Zombie.Kind` y `ZombieVisual.ZombieType` quedan con **dos entradas**:

```gdscript
enum Kind { WALKER, BOSS }        # game/03_zombies/Zombie.gd:9
enum ZombieType { WALKER, BOSS }  # game/03_zombies/ZombieVisual.gd:67
```

- **`WALKER` es el único arquetipo**: el normal, el que lleva la skin
  pixel-art. Conserva sus estadísticas (68 HP, 80 px/s, 10 de daño).
- **`BOSS` no es un arquetipo**: es el **perfil «Tanque Alfa» del mismo
  zombi**. Se conserva íntegro para no perder el encuentro con el jefe, el
  meta-árbol v2, la extracción de 12 s, los combos ×3 y la barra de vida de
  jefe: 800 HP, escala 1.9 (cubo) / 0.95 (skin), carga telegrafiada y golpe
  de área en fase 2 (`enraged` al 50 % de vida).
- La **misma skin** sirve para ambos: el jefe es el mismo sprite, más grande.
  `SKIN_TYPES` pasa a ser `[WALKER, BOSS]`
  (`game/03_zombies/ZombieVisual.gd:88`).

`RUNNER`, `TANK`, `SPITTER` y `SCREAMER` se **eliminan del código**, no solo
del juego: enum, exports, funciones de habilidad, colores, sonidos, botín,
composición de hordas y hojas de arte. Se van con ellos el escupitajo, el
grito, la carga de tanque, los tintes por arquetipo y la horda compuesta.

El cubo `Body`/`Nose` **deja de ser la presentación de un arquetipo** y pasa a
ser el **fallback** de ADR-005: si el pack de skin falta o está incompleto, el
zombi vuelve al cubo y el juego continúa.

**El índice del jefe no puede ser un número mágico.** `Main.gd` usaba
`const BOSS_KIND: int = 5`, que en el roster nuevo (WALKER = 0, BOSS = 1)
dejó de ser válido: el Tanque Alfa spawneaba como un zombi **sin perfil** (sin
vida de jefe, sin barra, sin carga ni slam), y el fallo era invisible porque
ningún arnés miraba el índice. Ahora `Main.gd` resuelve el índice desde el
propio script del zombi (`_boss_kind()` →
`ZombieScript.get_script_constant_map()["Kind"]["BOSS"]`), de modo que un
cambio de orden del enum no pueda volver a descuadrarlo.

### 2. Compensación de spawn: más caminantes, hordas homogéneas

| Spawner | Antes | Ahora | Archivo |
|---|---:|---:|---|
| Barrio (`Neighborhood.ZOMBIE_SPAWN_COUNT`) | 26 | **42** | `game/05_house/Neighborhood.gd:17` |
| Bosque (`ForestZombies.MAX_ZOMBIES`) | 6 | **9** | `game/11_forest/ForestZombies.gd:10` |
| Horda base (`WorldDirector.horde_base_count`) | 2 | **4** | `game/01_core/WorldDirector.gd:62` |
| Horda máxima (`WorldDirector.horde_max_alive`) | 10 | **14** | `game/01_core/WorldDirector.gd:63` |
| Tope por oleada | 6 | **8** | `game/01_core/WorldDirector.gd:433` |

Los tres spawners producen **solo caminantes**: `Main._spawn_zombies()` deja de
repartir por pesos, `ForestZombies` deja de tener `ZOMBIE_KINDS` y
`WorldDirector` fija `HORDE_KIND = 0` (la horda es homogénea). La tabla de
telegrafía sonora (`AudioDirector.TELEGRAPH_SFX`) queda con dos entradas:
caminante y jefe.

### 3. Arte: el banco de arte se reduce al banco que el juego usa

El generador determinista deja de fabricar las hojas de los arquetipos
eliminados: `gen_art.py` produce cinco hojas (`player_sheet.png`,
`zombie_walker.png`, `boss_sheet.png`, `effects.png`, `tiles.png`), dos mapas
de luz y **una máscara de sombra** nueva (`assets/art/shadows/sun_shadow.png`,
64×64, elipse suave determinista). `gen_art.py --check` verifica las cinco
hojas, los dos mapas de luz y la máscara, y sigue siendo puerta de CI.

El pack de skin del zombi **no cambia**: mismo contrato de celda 64×64, mismo
ancla, mismo pivot, mismos 33 frames y 8 strips. Lo que cambia es quién lo
usa: ahora lo usan el caminante y su perfil de jefe.

### 4. Sombras diurnas acotadas: manchas (blob) con cota dura

La decisión es explícita: **el sol deja de proyectar sombra direccional** y
las sombras diurnas las dibuja un sistema de **manchas acotadas**.

- `DirectionalLight2D` conserva la **luz** (color, energía, dirección) y
  desactiva `shadow_enabled` (`game/08_ui/SolarLighting.gd:292`).
- `SolarLighting.tscn` monta `SunShadows` (`game/08_ui/SunShadowController.gd`),
  un `Node2D` con `z_index = -1`: las manchas quedan **por debajo de los
  personajes** y **por encima del suelo** (el suelo vive en `z = -10`).
- Cada `LightOccluder2D` vivo tiene **como máximo una mancha**, rastreada con
  un sondeo periódico (0,5 s) desde la raíz del árbol, para que funcionan
  igual dentro del juego y dentro de un arnés.
- La mancha usa la máscara `sun_shadow.png` (canónica, determinista), se
  alarga en la dirección **opuesta** a la luz y tiene una **cota dura de
  longitud**: `MAX_SHADOW_LENGTH = 48 px` (`SunShadowController.gd:56`), con
  un mínimo de 16 px y un ancho mínimo de 14 px. Ninguna mancha puede llegar
  al borde de pantalla (1280×720).
- Las manchas **no reciben luz** (`light_mask = 0`): son oscuridad pintada, no
  una superficie iluminada.
- La opacidad depende de la fase (`day` 0.38, `dawn` 0.30, `dusk` 0.26,
  `night` **0**). De noche la mancha es invisible y el único cono de luz con
  sombras es el faro.

`SolarLighting` es la **única fuente de verdad** de la fase y del ángulo: los
manda al controlador, y solo cuando cambian (no cada frame), para no pisar
ajustes ajenos.

### 5. El faro nocturno no se toca

`Player.tscn`'s `Flashlight` (una `PointLight2D` con textura de cono) conserva
`shadow_enabled = true`, su `shadow_filter`, su textura y su
`shadow_filter_smooth`. Sus sombras **siguen siendo sombras reales del
motor**, acotadas por la forma del cono.

Lo único que se toca en ese nodo es la línea `max_distance = 700.0`, que era
un **no-op** (`PointLight2D` no tiene esa propiedad): mantenerla habría sido
dejar un número muerto que sugiere un control que no existe.

### 6. Detección: `exclude` correcto, tres rayos y radio mayor

El contrato de percepción queda en tres reglas:

1. **El `exclude` se construye entero antes de asignarlo.** `Array[RID]`
   local con el RID del zombi y el del objetivo; se asigna una sola vez. Es el
   patrón que ya usaban `Player.gd` y `DriveableVehicle.gd`.
2. **Tres rayos**: al centro del objetivo y a dos «hombros» laterales a ±6 px
   (`SIGHT_SHOULDER_OFFSET`). El jugador mide 16×16, así que 6 px caen dentro
   de su cuerpo: un poste estrecho ya no lo oculta entero, pero una pared que
   lo tapa, sí. Si **cualquiera** de los tres rayos llega sin golpear nada,
   el zombi ve al jugador.
3. **Ver al jugador propaga la alerta al grupo**: `_become_alerted(...,
   propagate = true)`, acotado por `was_calm` y por un cooldown de 1,2 s. El
   zombi que recibe la alerta no la repropaga (evita la cascada infinita).

Además, el radio de detección sube de 430 a **520 px** y el sentido cercano de
105 a **120 px**.

### 7. Puertas de CI propias

Tres arneses nuevos, registrados en `.github/workflows/ci.yml` con su nombre
esperado, más la actualización de los arneses existentes que fijaban el
contrato viejo:

| Arnés | Contrato que fija |
|---|---|
| `ZombieRosterTest` | roster de 2 entradas, spawners solo caminantes, cantidades, índice real del jefe (runtime: `Main.spawn_boss()`), telegrafía de 2 entradas |
| `ZombiePerceptionTest` | `exclude` real, tres rayos, radio 520, propagación de alerta |
| `SunShadowTest` | sol sin sombra direccional, faro con sombras reales, manchas acotadas, `light_mask = 0`, alpha 0 de noche, textura canónica presente |

Y se actualizan `AiWaveTest`, `LightingTest`, `VisualStyleTest`,
`ZombieSkinTest` y `CubeFxLifecycleTest` al contrato nuevo (el cubo se prueba
por el camino de **fallback**, no por un arquetipo eliminado).

## Alternatives Considered

### (a) Bajar `max_distance` del sol para acortar la sombra

- **Pros**: un cambio de una línea.
- **Cons**: no acorta nada. `max_distance` es el margen de cull: controla qué
  oclusores se consideran y suma al `z_far` (`2 * to_edge_distance +
  cull_distance`). La sombra sigue llegando al borde de pantalla.
- **Why not**: la sonda sobre el código del motor descarta la hipótesis. Era
  la opción que parecía obvia y es exactamente la que el comentario original
  del código daba por hecha.

### (b) Reemplazar el sol por un `PointLight2D` gigante

- **Pros**: una luz de verdad, con sombras de verdad.
- **Cons**: una luz puntual diverge: cerca del foco la dirección de la sombra
  es radial y muy corta; lejos es casi horizontal. No existe una dirección
  solar coherente en todo el mapa. Además, el coste de un atlas de sombra
  punto gigante es alto y el resultado sigue sin tener un largo controlable.
- **Why not**: no reproduce la luz solar. Se evalúa como peor que la
  `DirectionalLight2D` sin sombras.

### (c) Mantener la sombra direccional y recortar la pantalla con un `CanvasModulate`

- **Pros**: no tocar la luz.
- **Cons**: no recorta nada; el `CanvasModulate` modula el color, no la
  geometría de la sombra. La franja seguiría llegando al borde.
- **Why not**: no ataca la causa.

### (d) Sombras de mancha (blob) por emisor de sombra — **elegida**

- **Pros**: cota dura y verificable (`MAX_SHADOW_LENGTH`), coste bajo, patrón
  estándar en 2D cenital, independiza la sombra de la geometría de pantalla y
  no toca el faro.
- **Cons**: la sombra deja de ser «real» (no la calcula el motor) y hay que
  mantener el asset de la máscara.
- **Why not**: es la única opción que **sí** satisface la petición («acotar las
  sombras») sin romper el faro, que es la restricción dura del usuario.

### (e) Quitar el sol del todo y quedarse solo con ambiente + faro

- **Pros**: cero sombras diurnas, cero problema.
- **Cons**: el día deja de ser «realista»; la petición es que el daytime sea
  realista **con sombras acotadas**, no sin sombras.
- **Why not**: cumple el efecto secundario (no hay sombra larga) pero
  incumple el objetivo (hay sombras).

### (f) Mantener el roster completo y solo reequilibrar los spawns

- **Pros**: no se pierde contenido.
- **Cons**: contradice la petición explícita del usuario.
- **Why not**: la petición es jerárquica y el usuario la formulas dos veces.

## Consequences

### Positive

- El juego tiene **un** arquetipo de zombi, legible y con skin de sprites; el
  banco de arte y el código coinciden con lo que el juego usa.
- El jefe conserva su encuentro, sus dos fases, su barra de vida y su botín,
  pero **degradado como perfil del mismo zombi**: no es una segunda familia.
- Las sombras diurnas **no pueden llegar al borde de pantalla**: la cota es
  un número, no una intención.
- El faro nocturno conserva sus sombras reales: la restricción del usuario se
  respeta literalmente.
- La detección deja de estar rota por un bug de API: el zombi ve lo que el
  cono de visión dice que ve, y el aviso se propaga al grupo.
- El spawn compensa: 42 caminantes en el barrio, 9 en el bosque y hordas de 4
  a 14.

### Negative

- El runtime mantiene **dos representaciones** (skin y cubo) y **dos rutas de
  FX**; el cubo es el fallback y la skin la norma.
- El sistema de sombras diurnas es **código propio**: una malla de oclusores
  por mancha, con su asset, su cota y su coste de memoria (una textura de
  64×64 por emisor, que comparten la misma textura en memoria).
- La sombra diurna ya **no es la del motor**: su forma y su longitud son una
  aproximación, no un cálculo físico.
- La sombra del oclusor sigue siendo la del rectángulo del `LightOccluder2D`
  (24×24 para los zombis), no la de la silueta del sprite.
- Perder cuatro arquetipos significa perder **variedad de comportamiento**
  (escupitajo, grito, carga) y la lectura de rango que daban sus tintes.
- La rotación de un sprite pixel-art puede producir bordes irregulares fuera de
  la retícula aunque el filtrado sea `NEAREST` (heredado de ADR-005).

### Risks

- Que el controlador de sombras crezca sin control → mitigación: la cota dura
  de 48 px es un invariante exigible por `SunShadowTest`, y el rastro es
  periódico (0,5 s) con limpieza de oclusores liberados.
- Que la fase y el ángulo se desincronicen del director → mitigación:
  `SolarLighting` es la única fuente y solo publica cuando cambian.
- Que un cambio futuro del enum vuelva a descuadrar el índice del jefe →
  mitigación: `Main.gd` lo resuelve desde el script del zombi y
  `ZombieRosterTest` comprueba el spawn **real** (`Main.spawn_boss()` con 800
  HP y barra visible).
- Que el fallback al cubo oculte un pack roto → mitigación: las puertas
  deterministas (`gen_zombie_skin.py --check`, `skin_pack.py check|selftest`)
  siguen en el CI.
- Que la detección resultante sea demasiado agresiva → mitigación: la
  propagación está acotada por `was_calm` y por cooldown, y el grupo no
  repropaga.

## Invariants

Las siguientes reglas deben seguir siendo verdad:

1. `Zombie.Kind` y `ZombieVisual.ZombieType` tienen exactamente dos entradas:
   `WALKER` y `BOSS`.
2. Todos los spawners producen caminantes: barrio, bosque y horda.
3. El Tanque Alfa se spawnea con el índice **real** de `Zombie.Kind.BOSS`, no
   con un número mágico; su perfil (800 HP, barra, carga, slam) está activo.
4. El cubo `Body`/`Nose` es el **fallback**, no la presentación de un
   arquetipo: `AnimatedSprite2D` y `Body`/`Nose` nunca son visibles a la vez.
5. El runtime mantiene exactamente las ocho animaciones canónicas, el
   contrato de celda 64×64, el ancla global y el pivot centrado (ADR-005).
6. `Collision`, `SeparationArea` y las demás hitboxes no cambian de tamaño,
   forma, posición ni layer.
7. Squash, stretch y telegrafía solo alteran lo visible; nunca una hitbox.
8. La sombra direccional del **sol** está desactivada; no existe ningún
   parámetro de runtime que finja acortarla.
9. Cada mancha solar mide como máximo `MAX_SHADOW_LENGTH` (48 px) en su eje
   largo: no puede llegar al borde de pantalla.
10. Las manchas solares no reciben luz (`light_mask = 0`) y se dibujan por
    debajo de los personajes.
11. De noche la mancha solar es **invisible** (alpha 0) y el sol no aporta
    energía.
12. El **faro nocturno** conserva `shadow_enabled = true` y sus sombras reales
    del motor.
13. La línea de visión usa un `exclude` construido **entero antes de
    asignarse**, y lanza **tres** rayos (centro + dos hombros a ±6 px).
14. El radio de detección del caminante es de 520 px y el sentido cercano de
    120 px.
15. Ver al jugador propaga la alerta al grupo una sola vez (acotado por
    `was_calm` y cooldown); el receptor no repropaga.
16. La tabla de telegrafía sonora tiene dos entradas (caminante y jefe).
17. El repo no fabrica ni distribuye arte de arquetipos eliminados: el banco
    son cinco hojas y `gen_art.py --check` lo verifica.
