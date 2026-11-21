# ADR-007: El skin del zombi se deriva del sprite cenital real del autor

- **Status**: accepted
- **Date**: 2026-11-20
- **Deciders**: Lead Orchestrator + subagentes ECC
- **Technical Story**: Ronda R4 de corrección de la presentación de zombis
- **Amends**: [ADR-005](0005-hybrid-zombie-sprite-presentation.md) §2
  («El skin se genera con el pipeline canónico del repositorio») **en la
  fuente de los píxeles**, y §3.1 **en la descripción de implementación de
  `rise`** (de «pose baja dibujada con bob de 1 px lógico» a «base real
  comprimida al 55 % con bob entero de ±1 px»). El contrato de celda 64×64,
  PPU 64, pivot, ancla global, ocho clips, fallback al cubo y allowlist
  WALKER/BOSS sigue vigente.
- **Related**: [ADR-001](0001-pixel-art-pipeline.md) (paleta canónica de 16
  colores y pipeline determinista), [ADR-006](0006-walker-only-roster-bounded-sun-shadows-and-detection.md)
  (roster de un solo arquetipo).

## Context

El usuario reportó que «la textura que te pedí poner no la pusiste». La
investigación de las sesiones anteriores recuperó la petición literal: quería
el sprite de los zombis que estaba en Descargas, «con su debida animación», y
una carpeta para reutilizarlo. El pack `~/zombie_sprites/` que se había
auditado no sirve como animación: sus 33 frames son 4 vacíos y 29 tarjetas de
color plano, sin silueta (ADR-005 §1 y enmienda E3). Pero ese pack **sí**
contenía un PNG suelto válido, `zoimbie1_hold.png`, que no formaba parte de la
animación auditada.

El build de Unity que el usuario tenía en Descargas
(`this-world-definitely-need-a-hero-but-you-are-just-a-spear-linux-universal.zip`)
se extrajo y se inventarió con UnityPy. Contiene **un solo** `Texture2D`/
`Sprite` de zombi: `zoimbie1_hold`, de **35×43 px**, con transparencia y 235
combinaciones RGBA (191 colores RGB distintos). No hay frames de animación
oficiales que extraer: el juego original
anima a sus actores con transforms, no con una hoja de sprites.

El pack que el runtime estaba mostrando se dibujaba con `draw_humanoid` del
generador procedural (`gen_art.py`). Era un humanoide cenital válido, pero
**no era el arte que el usuario había pedido**. La compuerta headless no podía
detectarlo: verificaba paleta, celdas y bytes del pack, no la procedencia del
dibujo.

## Decision

### 1. Fuente única y verificable

La fuente de píxeles del pack es
`game/tools/art_source/zoimbie1_hold.png`, copia exacta del sprite entregado
por el usuario. El generador fija su **SHA-256**
(`61df3e84c18409b698b56273a0bd014f86a23dc5622380d5d10b82124afff84e`) y sus
dimensiones (35×43). Si la fuente falta, cambia o se sustituye, `python3
tools/gen_zombie_skin.py --check` falla y no se publica un pack distinto.

La fuente vive **fuera** de `assets/enemies/zombie/` para que
`skin_pack.py check` no la confunda con un PNG sobrante del pack. La carpeta
reutilizable que consume el runtime sigue siendo
`game/assets/enemies/zombie/` (33 frames sueltos + 8 strips).

### 2. Derivación determinista, no redibujo

El generador (`game/tools/gen_zombie_skin.py`) transforma la fuente en tres
pasos fijos:

1. **Orientación.** El sprite original mira a la derecha. El runtime rota la
   `AnimatedSprite2D` con `velocity.angle() + PI/2`, así que el eje local −Y
   debe ser «adelante». La fuente se rota **90° en sentido antihorario**.
2. **Color.** El alpha se vuelve binario con umbral 160. Los tonos dominantes
   tienen un mapeo explícito a la paleta canónica (ámbar para la piel, dos
   verdes para la camisa, gris acero para la cabeza, rojo para los acentos);
   los bordes antialiasados caen al color canónico más cercano. El resultado
   usa solo los 16 colores de `ART_BIBLE.md` §2.
3. **Escala.** La base rotada (43×35) se escala con vecino más próximo a
   **60×49 px** y se coloca en la celda de 64×64. No se interpola ni se
   inventan píxeles: cada píxel de la base procede de la fuente.

### 3. Animación derivada de una sola pose

El Unity original no tiene frames. El pack mantiene los **33 frames y 8
clips** del contrato (ADR-005 §3.1) aplicando transforms enteros sobre la
misma base:

| Clip | Frames | Movimiento derivado |
|---|---:|---|
| `idle` | 2 | bob vertical de 1 px |
| `walk` | 5 | bob + balanceo lateral de ±1 px |
| `walk_alt` (`run`) | 3 | bob de 2 px + balanceo |
| `attack` | 6 | anticipación, estocada de 5 px y recuperación |
| `attack_alt` (`hit`) | 2 | retroceso de 2–3 px |
| `special` (`hurt`) | 4 | sacudida lateral y retroceso |
| `rise` (`crawl`) | 5 | base comprimida al 55 % y bob |
| `death` | 6 | derrumbe progresivo hasta el 42 % de altura |

Los recuentos, fps y bucles no cambian: el runtime, el lock de `hit`
(`count / fps * 1.5`) y las puertas existentes siguen siendo válidos. El ancla
global se recalcula sobre la **unión** de los 33 frames y se aplica una sola
traslación entera; ningún frame se reencuadra contra su propio bbox.

### 4. Contrato de runtime intacto

No se toca `ZombieVisual.gd`, `Zombie.tscn`, la allowlist WALKER/BOSS, la
escala 0.5, el `z_index`, el fallback al cubo, la caché por ruta, el backoff
de reintento ni las hitboxes. Cambian los **bytes del pack**, no el contrato
de presentación.

### 5. Puertas y control negativo

- `python3 tools/gen_zombie_skin.py --check`: regenera en memoria desde la
  fuente y compara los 33 frames y 8 strips byte a byte.
- `python3 tools/skin_pack.py check`: paleta, celdas, anclaje y strips.
- `python3 tools/skin_pack.py selftest`: importador transaccional y contrato.
- `python3 tools/gen_zombie_skin.py --selftest` (nuevo): autopruebas del
  generador; somete el control de derivación a sus tres modos de fallo.
- `ZombieSkinTest._source_asset_checks()` (nuevo): exige el PNG original, su
  SHA-256, sus dimensiones, una silueta de al menos 900 px opacos y que el
  generador lea la fuente y fije el mismo hash.
- Control negativo reproducible: alterar un byte de
  `tools/art_source/zoimbie1_hold.png` hace fallar `gen_zombie_skin.py
  --check` con el diagnóstico de SHA-256; restaurar el byte devuelve rc=0.

#### 5.1 El pack está ligado a los píxeles de la fuente (no solo a su hash)

Un hash demuestra que el **fichero** es el esperado, pero no que el **pack**
salga de sus píxeles: un generador que comprobase el hash y luego dibujara un
humanoide procedural pasaría todas las puertas. Para cerrar ese hueco:

- **Control de derivación** (`gen_zombie_skin.py --check`): el generador
  perfora un píxel **interior** de la fuente (sin tocar la silueta, de modo que
  el contrato sigue cumpliéndose; prueba varios candidatos y usa el primero
  que deja la derivación válida) y exige que el pack **cambie**. Si la
  derivación dejase de usar la fuente, la puerta falla con «la derivación NO
  responde a los píxeles de la fuente». Reproducido neutralizando la
  derivación en una copia del árbol: `FAIL control: la derivacion NO responde
  a los pixeles de la fuente`, rc=1.
- **Exigencia del marcador** (`ZombieSkinTest`): el arnés exige que la salida
  de `--check` contenga el marcador del control, de modo que el control no
  pueda desaparecer en silencio.
- **Poses vivas**: `SKIN_ANIMS` declara poses **ordinales** (0..n-1) y el
  índice selecciona el movimiento; el generador rechaza una tabla no ordinal
  y el arnés comprueba que cada token coincide con su posición.

#### 5.2 Contrato único del pack

Las reglas (**completitud**, celda, centrado, margen, paleta, semántica de
`rise`, unión global) viven en **una sola** función,
`skin_pack.validate_pack_contract()`, que consumen `skin_pack.py check` y
`gen_zombie_skin.py`. Antes cada puerta tenía su copia y **ya habían
divergido**: `skin_pack.py check` aceptaba un pack con `rise` a la misma altura
que `walk` (RED reproducido: `SKIN_PACK_CHECK failures=0`), mientras la
documentación atribuía esa comprobación a ambas puertas. Ahora la regla está en
el `selftest` (casos 26 y 27) y en el arnés de Godot.

**Completitud (R5-hotfix).** El contrato exige además que el pack contenga
**exactamente** las ocho animaciones canónicas con su número de frames (33
frames) y nada más. Antes, un pack mutilado —por ejemplo, solo `idle`— pasaba
el contrato: cada frame era correcto, pero al runtime le faltaban clips
enteros. RED reproducido: `validate_pack_contract` con un pack de un solo
`idle` devolvía `[]` (sin problemas); ahora devuelve los frames canónicos que
faltan. Caso 28 del `selftest`.

El generador, además, **falla cerrado**: si un píxel opaco caería fuera de la
celda (al componer o al aplicar la traslación global) aborta en vez de
recortarlo en silencio, porque un frame recortado rompería el ancla global.

#### 5.2.1 El control de derivación se somete a sí mismo (R5-hotfix)

`gen_zombie_skin.py --selftest` es la prueba permanente de que el control de
derivación **llega a su rama** y de que es la única barrera entre el arte
pedido y un dibujo procedural. Somete la derivación a cinco escenarios:

1. **Derivación real**: el control pasa (el pack responde a los píxeles).
2. **Derivación neutralizada** (base constante que **aún cumple el contrato**):
   el control tiene que decir «la derivación NO responde a los píxeles de la
   fuente». Esto responde a la pregunta que quedó abierta en la revisión
   anterior: la reproducción neutralizada **sí** alcanza la rama del control, y
   el pack resultante es válido, así que el control es lo único que lo detecta.
3. **Todos los candidatos fallan**: el control tiene que distinguir ese caso
   de una derivación que simplemente no responde y emitir un diagnóstico
   «falla al mutar la fuente».
4. **Excepción inesperada**: la puerta es el límite de confianza; cualquier
   excepción normal (`Exception`, no solo `RuntimeError`/`ValueError`/`OSError`)
   se convierte en diagnóstico y nunca en traceback.
5. **Candidatos mixtos**: un candidato inválido no significa que todos fallen.
   Si otro candidato responde con la misma base, el diagnóstico correcto es
   «la derivación NO responde a los píxeles», no «falla al mutar».

Control negativo del control: revirtiendo el fail-closed en una copia del
árbol, `ZOMBIE_SKIN_SELFTEST failures=2` («el control debe fallar limpio ante
una excepcion inesperada al mutar, pero lanzo TypeError» y «el control debe
distinguir todos los candidatos fallan de la derivacion NO responde»).

### 5.3 Endurecimiento de la ingesta

La revisión de seguridad de la ronda detectó tres puntos medios y los tres
quedan cerrados:

1. **Un solo buffer.** El hash y la decodificación usan exactamente los mismos
   bytes: `skin_pack.read_png_bytes(data)` recibe el buffer ya verificado, sin
   una segunda lectura del fichero (se elimina la ventana TOCTOU entre «lo que
   se comprobó» y «lo que se decodificó»).
2. **Tope de tamaño y rechazo de enlaces.** La fuente debe ser un fichero
   regular de 1 a 65.536 bytes y no puede ser un enlace simbólico. El test de
   Godot aplica el mismo tope y **no decodifica** el PNG si el hash no
   coincide: un contenido ya rechazado no llega al decodificador nativo.
3. **Escritura atómica.** Los 41 PNG se escriben en un temporal del mismo
   directorio y se publican con `os.replace`, que no sigue enlaces: un fallo a
   mitad no deja un PNG truncado y un enlace en el destino se sustituye, no se
   sigue.

El SHA-256 es un **pin de contenido**, no un control de autenticidad: quien
puede modificar la fuente puede modificar también el hash. Su valor es
detectar corrupción accidental y desincronización entre la fuente y el pack.
La procedencia real la dan la revisión del cambio y el registro en este ADR.

### 6. Procedencia y alcance del asset

`zoimbie1_hold.png` es un asset del juego original, entregado por el usuario y
usado **a su petición expresa** en este proyecto. No se generó con el pipeline
del repositorio ni se relicencia: sigue siendo propiedad de su autor. El ADR
deja constancia de la procedencia para que el asset no se reutilice fuera del
proyecto sin permiso. La alternativa (redibujar un humanoide «parecido») se
rechazó porque el usuario había pedido explícitamente **esa** textura.

## Consequences

- El pack visible cambia por completo: ya no es el humanoide procedural, es el
  sprite cenital real, cuantizado a la paleta del juego.
- La animación no es una animación oficial del juego de origen (no existe):
  es una derivación determinista documentada. Esto es una limitación conocida,
  no una regresión.
- La fuente antialiasada de **235 combinaciones RGBA (191 colores RGB
  distintos)** se reduce a 16 colores y a una silueta binaria; el resultado es
  coherente con el resto del arte, pero no es un calco pixel-perfect del PNG
  original.
- El coste de regeneración es despreciable (33 frames de 64×64 en Python puro).
- Cualquier cambio futuro de la fuente exige actualizar el SHA-256, regenerar
  el pack y volver a pasar las tres puertas. Es intencional: impide que el
  pack y la fuente se desincronicen en silencio.

## Alternatives considered

1. **Usar el pack `~/zombie_sprites/` completo.** Rechazado: 4 frames vacíos,
   29 tarjetas planas, tamaños variables y strips no rebanables (ADR-005 §1).
2. **Redibujar el sprite con `draw_humanoid`.** Era lo que había; el usuario
   lo rechazó porque no era su textura.
3. **Cargar el PNG de 35×43 directamente en runtime sin pack.** Rechazado:
   rompe el contrato de celdas de 64×64, el atlas por frame y el fallback;
   además el sprite mira a la derecha y el runtime espera «arriba».
4. **Animar con rotaciones arbitrarias.** Rechazado: rompe la retícula y
   descentra el bbox; el contrato exige centro_x dentro de ±1 px. Se usan
   transforms enteros y compresiones simétricas.
