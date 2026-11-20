# ADR-007: El skin del zombi se deriva del sprite cenital real del autor

- **Status**: accepted
- **Date**: 2026-11-20
- **Deciders**: Lead Orchestrator + subagentes ECC
- **Technical Story**: Ronda R4 de corrección de la presentación de zombis
- **Amends**: [ADR-005](0005-hybrid-zombie-sprite-presentation.md) §2
  («El skin se genera con el pipeline canónico del repositorio») **solo en la
  fuente de los píxeles**. El contrato de celda 64×64, PPU 64, pivot, ancla
  global, ocho clips, fallback al cubo y allowlist WALKER/BOSS sigue vigente.
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
colores. No hay frames de animación oficiales que extraer: el juego original
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
- `python3 tools/skin_pack.py selftest`: importador transaccional.
- `ZombieSkinTest._source_asset_checks()` (nuevo): exige el PNG original, su
  SHA-256, sus dimensiones, una silueta de al menos 900 px opacos y que el
  generador lea la fuente y fije el mismo hash.
- Control negativo reproducible: alterar un byte de
  `tools/art_source/zoimbie1_hold.png` hace fallar `gen_zombie_skin.py
  --check` con el diagnóstico de SHA-256; restaurar el byte devuelve rc=0.

### 5.1 Endurecimiento de la ingesta

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
- La fuente antialiasada y de 235 colores se reduce a 16 colores y a una
  silueta binaria; el resultado es coherente con el resto del arte, pero no es
  un calco pixel-perfect del PNG original.
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
