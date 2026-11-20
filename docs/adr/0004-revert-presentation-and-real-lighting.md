# ADR-004: Reversión de la presentación y adoptamos iluminación 2D real

- **Status**: accepted
- **Date**: 2026-11-20
- **Deciders**: Lead Orchestrator + subagentes ECC
- **Technical Story**: Ronda R1 de revisión de incongruencias y errores sobre el
  plan maestro de 18 mejoras (Capas 0-3, commits `beb9a1a`, `00afcb0`,
  `a7ceeb7`, `d8d24a2`)
- **Replaces (parcialmente)**: [ADR-001](0001-pixel-art-pipeline.md) en su
  vertiente de *presentación en runtime* (el pipeline y el banco de arte se
  conservan; ver "Consecuencias")

## Context

La Capa 0 del plan maestro sustituyó la presentación procedural por sprites
pixel-art generados por `tools/gen_art.py`. La revisión R1 detectó que esa
sustitución **no era lo que el usuario quería**: el usuario hará el arte
personalmente más adelante y pidió explícitamente volver a una presentación
simple de cubo. Además, la propia revisión encontró tres defectos reales en el
estado entregado:

1. **Los botones de la pantalla de derrota no funcionaban.** Al morir,
   `HUD.gd:_end_game()` pausa el árbol (`get_tree().paused = true`). Las
   escenas `MainMenu.tscn` y `GameOver.tscn` heredaban `process_mode = 0`
   (`PROCESS_MODE_PAUSABLE`), por lo que sus `Button` quedaban con
   `can_process() == false` y el clic nunca llegaba al handler. Reproducido en
   el juego real: con el CanvasLayer en modo pausable, un clic real sobre
   "Reintentar" deja el árbol pausado y la pantalla abierta; con
   `PROCESS_MODE_ALWAYS` el clic despausa y recarga la partida.
2. **Flood de errores en consola.** `HUD.gd:_tutorial_on_input()` leía
   `event.echo` sobre cualquier `InputEvent`, incluidos
   `InputEventMouseMotion`/`InputEventMouseButton`, que no tienen esa
   propiedad. Producía ~1206 `SCRIPT ERROR` por sesión de juego.
3. **La iluminación no era real.** `CanvasModulate.color` usaba su canal alpha
   como "energía ambiente", de modo que la noche se renderizaba como un
   desvanecido contra el fondo plano en lugar de una atenuación de la escena.
   El mundo quedaba lavado y el faro no destacaba. Además el tinte de fase de
   `WorldDirector` se multiplicaba sin normalizar, oscureciendo dos veces.

A esto se suma la petición explícita de eliminar la música adaptativa (dañaba
el ambiente de supervivencia) y de quitar el movimiento de cámara con el
ratón (el seguimiento se conserva). La mecánica (combos x3, boss Tanque Alfa,
meta-árbol v2, extracción de 12 s, tutorial y menús) **no** se toca: R1 solo
revierte la presentación y arregla los bugs verificados.

## Decision

### 1. Presentación: cubo simple, con el banco de arte conservado

El runtime vuelve a `Polygon2D` (cubo `Body` + `Nose`) como representación
visible del jugador y de los zombis. `PlayerVisual.gd` y `ZombieVisual.gd`
dejan de cargar las hojas PNG en runtime y exponen el interruptor
`USE_SPRITE_ART = false` para que el usuario pueda activarlo cuando tenga su
arte. Se conservan:

- `assets/art/ART_BIBLE.md` (paleta de 16 colores, sprites de 32 px),
- las 9 hojas PNG generadas por `tools/gen_art.py`,
- los hooks `load_sprite_sheet()` / `load_all_from_atlas()`,
- el paso `verify deterministic art pipeline` del CI (`gen_art.py --check`).

Es decir: **el pipeline es una herramienta, la presentación es una decisión
editable**. No se elimina trabajo previo; se le baja el rango de "presenta el
juego" a "soporta el arte futuro".

### 2. Oscuridad nocturna: media luz con faro

La noche se implementa con `CanvasModulate` cuyo **alpha es siempre 1.0** y
cuyo RGB multiplica la escena. La tabla de fase es:

| Fase | Grade (RGB) | Carácter |
| --- | --- | --- |
| `day` | `(1.00, 1.00, 1.00)` | sin oscurecer |
| `dawn` | `(0.92, 0.82, 0.72)` | cálido |
| `dusk` | `(0.68, 0.48, 0.40)` | crepúsculo cálido |
| `night` | `(0.42, 0.46, 0.56)` | media luz **azul** |

`ambient_energy` conserva su contrato 0..1.5 (lo emite `WorldDirector`, 0.24
de noche) y se usa como factor con suelo `AMBIENT_FLOOR = 0.72`. El tinte de
`WorldDirector` se normaliza a matiz (`_hue_only`) para no oscurecer dos
veces. `PHASE_SUN_GAIN` (día 3.4, amanecer 1.8, atardecer 1.4, noche 0.0)
amplifica la `DirectionalLight2D`; `PHASE_FLASHLIGHT` (día 0.0, amanecer 0.45,
atardecer 1.05, noche 1.60) enciende el faro.

### 3. Faro real y sombras proyectadas

- `Flashlight`: `PointLight2D` hijo de `Player`, textura de cono de 512×256
  generada por `tools/gen_art.py`, `shadow_enabled`, `shadow_filter = 1`,
  `shadow_filter_smooth = 2.0`, `max_distance = 700`, `range_layer_min/max = 0`
  para afectar solo al canvas del mundo y no al HUD.
- `MuzzleLight`: fogonazo de disparo, textura de halo de 128×128.
- Sombras **proyectadas de verdad** (`DirectionalLight2D` y `PointLight2D` con
  `shadow_enabled`). Se elimina `PixelShadowController` y el grupo
  `pixel_shadows` (polígonos falsos desplazados a mano).
- Las capas de pantalla (`GlareRect`, `NightGradeRect`) llevan `light_mask = 0`
  para que el faro no las ilumine, y viven en `GlareLayer` (CanvasLayer 0),
  por debajo del HUD (layer 1).
- `assets/shaders/NightGrade.gdshader` añade viñeta + grano animado + tinte
  frío de acabado nocturno.

### 4. Sin música adaptativa

`AudioDirector.gd` pierde por completo el subsistema musical: bus
`MUSIC_BUS`, tabla `MUSIC_TRACKS`, crossfade, ducking (`DUCK_SFX_IDS`), API
`play_music()` / `set_music_state()` / `set_music_volume()` y la síntesis
`_music_day` / `_music_explore` / `_music_combat` / `_synth_night_music`. Se
conservan el **ambiente** (viento, lluvia, noche, tensión, bosque) y los
**SFX** (armas, zombis, loot por rareza, UI, telegrafía de arquetipo).

### 5. Cámara sin ratón

Se elimina `game/02_player/CameraController.gd` (look-ahead con
`get_global_mouse_position()`). La `Camera2D` vuelve a ser un nodo simple
hijo de `Player`, con `ignore_rotation = true`: el seguimiento se conserva
íntegro. El shake de disparo lo conserva `WeaponController`, que ya lo
gestiona por su cuenta.

### 6. Los menús funcionan con el árbol pausado

`MainMenu.tscn` y `GameOver.tscn` declaran `process_mode = 3`
(`PROCESS_MODE_ALWAYS`), y `MainMenu.gd` / `GameOver.gd` lo fuerzan también
en `_ready()` (defensa en profundidad: el ajuste en escena no puede
desincronizarse del ajuste en código). `HUD.gd` pasa a usar
`event.is_echo()` y a filtrar por tipo de evento, lo que elimina el flood de
errores.

### 7. Blindaje de `Zombie.gd`

`Zombie.gd` accede al jugador **solo** a través del helper `_player_node()`,
que valida `is_instance_valid()` antes de castear a `Node2D`. El error
reportado por el usuario no fue reproducible en headless ni en ventana (con
boss, muerte y recarga: 0 errores), por lo que no se puede afirmar su causa
exacta; el blindaje elimina la clase de fallo completa ("trying to cast a
freed object") en lugar de parchear una línea concreta.

### 8. Bugs de incongruencia corregidos en la misma ronda

La revisión no se limitó a lo pedido: al reescribir los visuales y los
arneses aparecieron defectos reales que se corrigieron con el mismo criterio
(evidencia, no impresión):

1. **Tween huérfano en los FX del cubo.** `PlayerVisual.gd` y
   `ZombieVisual.gd` creaban **un tween por polígono dentro de un bucle** y
   solo guardaban el último (`_squash_tween` / `_fx_tween`). Los anteriores
   quedaban vivos y peleaban por la escala del cubo. Ahora hay un tween por
   polígono, **todos** se guardan en un array y `_reset_fx()` los mata.
2. **La telegrafía no tenía "hold".** El patrón
   `set_parallel(true)` → `tween_interval()` → `set_parallel(true)` de
   `ZombieVisual.telegraph()` **no respeta la pausa**: la vuelta a la base
   arrancaba en el mismo instante que la subida y el pulso de aviso era
   invisible. Medido con una sonda sobre Godot 4.7.2:
   - patrón viejo → subida `0.007-0.076 s`, vuelta `0.076-0.173 s` (sin hold)
   - patrón nuevo → subida `0.007-0.076 s`, hold `0.076-0.376 s`, vuelta
     `0.376-0.476 s`
   El patrón nuevo es **secuencial puro** (subir → hold → bajar) con un tween
   por polígono; escala y tinte se animan juntos vía `tween_method`.
3. **La escala del cubo se acumulaba.** `ZombieVisual._cube_scale_targets()`
   releía la escala **deformada** en vez de la escala base del arquetipo: tras
   una telegrafía + un squash el cubo se quedaba en `1.38` cuando la base del
   arquetipo es `1.0`, y cada efecto se acumulaba sobre el anterior. Ahora
   `ZombieVisual` captura la escala base (`_cube_base_scales`) cuando
   `Zombie.gd:_apply_kind()` la aplica.
4. **La victoria se escribía de dos formas.** `HUD.gd` decía
   "¡EXTRACTION EXITOSA!" (sin tilde) mientras `GameOver.gd` decía
   "¡EXTRACCIÓN LOGARADA!" y `QA.gd` buscaba "EXTRACCIÓN": el check de
   extracción del QA salía `false` aunque la victoria fuera real. Se normaliza
   a "¡EXTRACCIÓN EXITOSA!".
5. **`VictoryTest.gd` era un arnés muerto.** Salía `RESULT: FAIL` desde la
   Capa 2/3 (esperaba el `EndOverlay` del HUD en vez de la pantalla
   dedicada, y solo esperaba 6 frames para una cuenta atrás de 12 s), pero
   terminaba con `quit(0)` y no estaba en el CI: nadie lo veía. Se reescribe
   como compuerta real y **se añade al CI**.
6. **Flood de `event.echo`** (ver §6): `HUD.gd` leía `event.echo` sobre
   `InputEventMouseMotion`, que no tiene esa propiedad.

### 9. El error reportado en "Zombies.gd" (cerrado tras el primer push)

El usuario reportó un error en un fichero llamado **`Zombies.gd`**. El único
fichero del repositorio cuyo nombre coincide exactamente es
`game/11_forest/ForestZombies.gd` (el resto es `Zombie.gd`), y el fallo se
reprodujo **de forma literal** con una sonda (`/tmp/opencode/repro_zs/game/r1_forest2.gd`):

```
SCRIPT ERROR: Left operand of 'is' is a previously freed instance.
       at: _kill_is_headshot (res://01_core/GameState.gd:361)
ERROR: Error calling from signal 'zombie_died' to callable:
       'Node2D(ForestZombies.gd)::_on_zombie_died': Cannot convert argument 1 from Object to Object.
```

**Causa raíz.** `EventBus.zombie_died` declaraba el payload como `Node2D`. Con
ese tipo, el motor **rechaza la llamada** a cualquier receptor tipado cuando la
instancia ya está liberada, y el error nombra el fichero del receptor: de ahí
el "error en Zombies.gd". Además, dentro de `GameState` el guard
`zombie != null` no protege: en Godot 4.7.2 una instancia liberada **compara
como `== null`** (medido: `libre == null` → `true`), de modo que
`zombie is Node2D` se ejecutaba sobre un objeto liberado y lanzaba
"previously freed instance".

**Semántica verificada en Godot 4.7.2** (sonda `r1_sem.gd`), que condiciona
el orden de los guards en todo el repo:

| Expresión | Instancia liberada | Null real |
|---|---|---|
| `libre == null` | `true` | `true` |
| `typeof(libre)` | `TYPE_OBJECT` (24) | `TYPE_NIL` (0) |
| `is_instance_valid(libre)` | `false` | `false` |
| `libre is Object` | **lanza error** | `false` |

Consecuencia: `== null` **no distingue** null de liberado; `typeof()` sí; y el
operador `is` no puede usarse antes de comprobar la vigencia.

**Arreglo.**
- `EventBus.gd`: `signal zombie_died(zombie)` sin tipo (coherente con
  `zombie_alerted(zombie, source)` y `game_state_changed(phase)`).
- `ForestZombies.gd`: receptor sin tipo y guards en el orden correcto
  (`typeof` → `is_instance_valid` → `is` → metadatos). Si el zombi ya está
  liberado, se limpia la entrada obsoleta de la lista en vez de ignorarla.
- `GameState.gd`: `_kill_is_headshot()` y `_kill_is_melee()` comprueban la
  vigencia antes de leer el zombi o de usar el operador `is`.
- `Main.gd`, `WeaponController.gd`, `QuestDirector.gd` y `QA.gd`: receptores
  sin tipo (no usan el payload).
- Nuevo arnés `ZombieEventPayloadTest` (**21 suites** en el CI): combina
  introspección determinista (señal y receptores sin tipo, guardas
  presentes) y regresión en runtime (payload liberado → `GameState` responde
  `bool`, la lista del spawner se limpia y el zombi vivo se conserva).
  Control negativo verificado: con el código anterior el arnés da **10 fallos**
  y reproduce los dos `SCRIPT ERROR`; con el arreglo, **0 fallos**.

### 10. Revisión de código de R1 (cierre de los riesgos latentes)

Una revisión de código posterior al push de R1 (`9594ff2`) dio veredicto
**SHIP** (0 bloqueantes) y dejó 3 riesgos latentes y 5 observaciones menores.
Todos se han cerrado y verificado:

| # | Hallazgo | Cierre |
|---|---|---|
| 1 | `_cube_base_scales` era una instantánea: el orden "asignar escala → `set_type()`" era un protocolo implícito | Nueva operación atómica `ZombieVisual.set_cube_base_scales()`: aplica la escala **y** actualiza la base en la misma llamada. `Zombie.gd:_apply_kind()` la usa en los 6 arquetipos vía `_apply_cube_scale()` |
| 2 | `telegraph()` conectaba `finished` solo al último tween (uno por polígono): el otro podía seguir escribiendo escala | Un **tween maestro** por efecto: `_apply_pulse_all()` / `_apply_cube_scale()` escriben todos los polígonos en la misma llamada. Un solo dueño del ciclo de vida |
| 3 | `set_type()` mataba los tweens pero no restauraba `_is_telegraphing`, el tinte ni la escala | `set_type()` llama a `_reset_fx()`: el cubo vuelve a su estado base completo |
| 4 | La casa usaba UN `LightOccluder2D` con el rectángulo entero: el faro no entraba por la puerta | Un oclusor **por segmento de muro**, creado desde el mismo `Rect2` que dibuja el muro: el hueco de la puerta queda abierto de verdad. Las ventanas siguen siendo solo visuales (decisión explícita) |
| 5 | El grading inicial arrancaba blanco (`_phase_grade` seguía en `Color.WHITE`) | `_phase_grade = _phase_grade_target` antes del primer `_apply_lighting()` |
| 6 | Comentario obsoleto sobre el bus de música en `AudioDirector.gd` | Comentario sustituido por la decisión vigente |
| 7 | El ADR afirmaba `ignore_rotation = true` sin declararlo en la escena | `ignore_rotation = true` declarado explícitamente en `Player.tscn` |
| 8 | Faltaba validación por píxeles del cono del faro | `LightingTest` comprueba ahora la geometría del mapa de luz por píxeles: vértice en el centro, transparencia detrás, apertura hacia `+X`, simetría vertical y borde difuminado |
| 9 | Línea en blanco al final de `docs/adr/README.md` | Eliminada (`git diff --check` limpio) |

**Validación visual** (la reserva que la revisión señalaba): con el jugador
fuera de una casa, de noche y apuntando a la puerta, el cono del faro
**entra por el hueco** y los muros proyectan sombras a ambos lados del haz
(`/tmp/opencode/r1/house/01_outside_door.png`); dentro de la casa, el interior
queda iluminado (`03_inside.png`). Luma media del centro: 0.095 fuera →
0.111 en el umbral → 0.090 dentro.

**Arneses**: `CubeFxLifecycleTest` (nuevo, escala base atómica + tween
maestro + cancelación completa) y `LightingTest` ampliado (grading inicial,
geometría del cono por píxeles, oclusores de la casa). CI: **22 suites**.

### 11. R1-hotfix: errores que solo aparecieron al JUGAR

La compuerta de R1-polish estaba verde (22 suites, `MECHANICS_READY 5/5`, CI
remoto en verde) y aun así el juego escupía errores en vivo. La diferencia
entre un arnés y el juego real es que el arnés **no carga todo**: la compuerta
arranca la escena principal y apaga el motor en el primer frame, y ninguna
suite ejercitaba la ruta vehiculo -> zombi ni compilaba los scripts que
nadie carga.

Los dos errores se Reprodujeron literalmente abriendo el juego:

**11.1 `Invalid operands 'Vector2' and 'Object' in operator '=='`**

```
SCRIPT ERROR: Invalid operands 'Vector2' and 'Object' in operator '=='.
       at: _on_bus_alert_2 (res://03_zombies/Zombie.gd:451)
   GDScript backtrace (most recent call last):
       [0] _on_bus_alert_2 (res://03_zombies/Zombie.gd:451)
       [1] _emit_alert (res://12_vehicles/DriveableVehicle.gd:353)
       [2] _physics_process (res://12_vehicles/DriveableVehicle.gd:204)
```

`EventBus.zombie_alerted` se declara como `zombie_alerted(zombie, source)`,
pero `DriveableVehicle._emit_alert()` inspecciona la firma y emite
`(posicion: Vector2, radio: float)`. El receptor del zombi hacia
`if a == self` con `a` = Vector2: en GDScript 4 comparar un Vector2 con un
Object es un **error en tiempo de ejecucion** (no un `false`), asi que el
handler abortaba, el zombi nunca oia el ruido del motor y el error se
repetia en cada frame de conduccion.

Arreglo: guard consciente de tipo `Zombie.gd:_is_self()`, que solo responde
`true` si el valor es un Node vivo (`typeof` -> `is_instance_valid` -> `is`).
El bus admite las dos convenciones y las tres variantes (`_on_bus_alert_1/2/3`)
usan el mismo guard.

**11.2 `HouseBuilder.gd` no compilaba**

```
SCRIPT ERROR: Parse Error: Cannot find member "keys" in base "int".
SCRIPT ERROR: Parse Error: Function "keys()" not found in base int.
ERROR: Failed to load script "res://05_house/HouseBuilder.gd" with error "Parse error".
```

`get_part()` hacia `material.keys()[material]`, es decir, `.keys()` sobre un
`int` (el enum `HousePart.WallMaterial`). El script entero no compilaba y el
error solo aparecia al abrir el **editor**, que escanea todo el sistema de
ficheros; `--import` y las suites headless solo compilan lo que la escena
carga. Arreglo: la biblioteca se indexa por los enums (int), no por nombres.

**11.3 Puertas nuevas (el lesson learned)**

| Puerta | Qué cubre | Por que faltaba |
|---|---|---|
| `ZombieAlertBusTest` (nuevo) | La ruta vehiculo -> zombi: emision directa al bus con las dos convenciones, el **vehiculo real** (`DriveableVehicle._emit_alert()`), los handlers de 1 y 3 argumentos y un **payload liberado** | Ninguna suite emitia `zombie_alerted` ni liberation un payload |
| `CodeIntegrityTest` (nuevo) | Compila **todos** los `.gd` del proyecto (**73 scripts**, recorrido recursivo de `res://`) y comprueba que un modulo huerfano (`HouseBuilder.get_part()`) responde | `--import` solo parsea lo que se carga; una lista manual de carpetas se quedo obsoleta y dejaba fuera 11 scripts |
| Smoke de juego en vivo (nuevo, CI) | `QA_MODE=smoke`: el juego real con el autopiloto y **centinela** `PLAY_SMOKE_COMPLETE`, mas grep de `SCRIPT ERROR` y de `FAIL ` | La compuerta apagaba el motor en el primer frame y el modo `play` dependia de un `--quit-after` externo sin centinela |

Control negativo de `ZombieAlertBusTest`: restaurando el fichero con el bug
(`git show ba9a7fb:game/03_zombies/Zombie.gd`) el arnes da **5 fallos** y el
`SCRIPT ERROR` original; con el arreglo, **0 fallos**. Segundo control
negativo: reintroduciendo solo el `_alert_point` roto (que devolvia `(0,0)`
en vez de `INF` ante un payload liberado) el arnes da **2 fallos** y el zombi
persigue un punto inventado. Control negativo de `CodeIntegrityTest`: un
script roto plantado en `04_items/` (carpeta que la primera version de la
puerta se saltaba) lo detecta y falla el arnes.

**11.4 Nota sobre `_is_self()` y el payload liberado**

La primera version del arreglo usaba `value is Node and is_instance_valid(value)`.
Medido en Godot 4.7.2, ese orden sigue siendo incorrecto: `instancia_liberada
is Node` **LANZA** "Left operand of 'is' is a previously freed instance"
(`is_instance_valid()` responde false sin lanzar, pero el `is` aborta). Por
eso el orden definitivo es `typeof` -> `is_instance_valid` -> `is`
(ADR-004 §9), en `_is_live_node()` y en los helpers `_alert_point()`,
`_alert_radius()` y `_alert_source()`.

**11.5 Invariantes de las puertas (la revision de R1-hotfix2)**

Una puerta verde no vale si su alcance puede encogerse en silencio. Las tres
invariantes que quedan fijadas:

| Invariante | Mecanismo | Control negativo |
|---|---|---|
| La puerta de integridad revisa **todos** los scripts versionados | `CodeIntegrityTest` contrasta el conjunto escaneado con el manifiesto de `git ls-files`; el CI exige ademas `checked=N` con el numero esperado | Inyectando una exclusion de carpeta con 2 scripts versionados: la puerta da `checked=71` y **falla** (`script versionado NO revisado`) |
| El smoke solo es verde si el juego **realmente corrio** | `QA_MODE=smoke` exige `reached == true` **y** `moved >= 100 px`, ademas de `alive` | Con el autopiloto incapable de moverse: `PLAY_SMOKE_FAILED`, rc=1 (antes era un falso verde) |
| Un error de lectura no reduce el alcance | `_scan_dir()` registra los `DirAccess.open()` fallidos como fallo, no los ignora en silencio | — |

Las carpetas `build/` y `export/` (ignoradas por git) quedan excluidas del
escaneo para que un artefacto local roto no produzca falsos positivos en la
compuerta local.

### Alternatives Considered

### (a) Mantener los sprites pixel-art generados como presentación

- **Pros**: el trabajo de Capa 0 se aprovecha tal cual; aspecto más "profesional" de inmediato.
- **Cons**: contradice una instrucción explícita del usuario; el arte generado
  por máquina es exactamente lo que el usuario quiere rehacer.
- **Why not**: la decisión de arte es del usuario, no del pipeline.

### (b) Revertir también el pipeline de arte (borrar `gen_art.py` y las PNG)

- **Pros**: repositorio mínimo, sin binarios ni deuda.
- **Cons**: se pierde el banco de trabajo y la herramienta determinista que el
  usuario necesitará cuando haga su arte; el CI pierde su paso de verificación.
- **Why not**: el pipeline no estorba en runtime y es reutilizable tal cual.

### (c) Oscuridad total de noche con el faro como única fuente de luz

- **Pros**: tensión máxima, el faro se convierte en el recurso central.
- **Cons**: el jugador deja de leer el terreno; el juego se vuelve injusto en
  oleadas grandes y el HUD compite con el brillo del cono.
- **Why not**: el usuario eligió explícitamente **media con faro**.

### (d) Alpha del `CanvasModulate` como energía ambiente (solución anterior)

- **Pros**: era la implementación existente; un solo canal de control.
- **Cons**: el canvas se desvanecía contra el fondo plano en lugar de
  atenuarse; la noche salía lavada y sin contraste.
- **Why not**: es un error de modelo, no de parámetro: la oscuridad debe ser un
  multiplicador de color, no de opacidad.

### (e) Quitar el tinte de fase de `WorldDirector` en lugar de normalizarlo

- **Pros**: menos código en `SolarLighting`.
- **Cons**: `WorldDirector` seguiría oscureciendo dos veces, porque su tinte
  también multiplica el color de la escena.
- **Why not**: el tinte cumple una función (color de la luz ambiente); lo que
  sobra es su componente de brillo, y eso se normaliza a matiz.

### (f) Mantener la música pero bajar su volumen

- **Pros**: no se pierde el trabajo de Capa 2.
- **Cons**: el usuario pidió eliminarla; "música muy baja" sigue siendo música y
  sigue dañando el ambiente de supervivencia.
- **Why not**: petición explícita del usuario.

## Consequences

### Positive

- La presentación vuelve a ser exactamente lo que el usuario pidió (cubo
  simple), con el arte futuro a un interruptor de distancia.
- Los botones de derrota y del menú vuelven a funcionar, con control negativo
  verificado en el juego real.
- Consola limpia: el flood de ~1206 `SCRIPT ERROR` por sesión desaparece.
- La noche es iluminación real: sombras proyectadas, faro con cono y viñeta, y
  la escena se lee sin el faro (media luz) mientras el cono destaca.
- `gen_art.py --check` sigue en el CI: el banco de arte no se degrada en
  silencio.
- Los FX del cubo (squash/stretch/telegrafía) ya no se pelean entre sí, el
  "hold" de aviso se respeta y la escala del arquetipo no se deforma.
- `VictoryTest` pasa a ser una compuerta real en el CI (antes era un arnés
  muerto que imprimía `FAIL` y salía con código 0).

### Negative

- El juego vuelve a verse "prototípico" hasta que el usuario incorpore su
  arte; el salto visual queda pendiente de su trabajo.
- Se pierde el trabajo de presentación de Capa 0 en runtime (≈9 hojas PNG
  quedan como material, no como presentación).
- El sistema de iluminación es más complejo que el anterior (más de un
  `CanvasModulate` con alpha, normales de color y un `CanvasLayer` de
  acabado).
- `VictoryTest` y `AudioPolicyTest`/`LightingTest`/`VisualStyleTest` suman
  tiempo de CI (20 suites en total frente a 18 antes).

### Risks

- Que el faro sea demasiado potente o direccional de forma que Moleste en
  interiores → mitigación: `range_layer` limitado al canvas del mundo,
  `max_distance = 700` y energía modulada por fase (`PHASE_FLASHLIGHT`).
- Que la falta de sprites haga creer que el juego está "sin terminar" →
  mitigación: `USE_SPRITE_ART` y la API de hojas documentadas en
  `ART_BIBLE.md` hacen que el cambio sea una línea, no una migración.
- Que `ambient_energy` siga siendo leído por `DriveableVehicle` y
  `MetaProgress` con el umbral `≤0.32 = noche` → mitigación: el contrato 0..1.5
  se conserva intacto; solo cambia cómo se aplica visualmente.
