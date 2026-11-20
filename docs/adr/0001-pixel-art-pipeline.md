# ADR-001: Pipeline de pixel art determinista

- **Status**: accepted — *parcialmente superseded por
  [ADR-004](0004-revert-presentation-and-real-lighting.md) (2026-11-20)*
- **Date**: 2026-11-19
- **Deciders**: Lead Orchestrator + subagentes ECC
- **Technical Story**: Capa 0 del plan maestro de conversión a pixel art profesional

> **Enmenda ADR-004 (2026-11-20).** Esta decisión sigue vigente **como
> herramienta**: el pipeline determinista, `ART_BIBLE.md`, las hojas PNG y su
> verificación en CI se conservan intactos. Lo que cambia es el **uso en
> runtime**: el pipeline deja de ser la presentación del juego (el jugador y
> los zombis vuelven a cubos `Polygon2D`) y pasa a ser el banco de trabajo del
> arte que hará el usuario, activable con `USE_SPRITE_ART`. Ver
> [ADR-004](0004-revert-presentation-and-real-lighting.md).

## Context

El juego tiene 0 imágenes en disco: toda la representación visual es
procedural, basada en `Polygon2D`, llamadas a `_draw()` y `ImageTexture`
generadas en tiempo de ejecución. Los hooks `load_sprite_sheet()` y
`load_all_from_atlas()` en `PlayerVisual.gd:221-227` llevan años sin
implementar y son hoy `pass` con un TODO, de modo que no existe una vía real
para integrar arte bitmap. El objetivo del plan maestro es competir
visualmente con los mejores títulos de pixel art, lo que exige una identidad
visual consistente, una paleta controlada y assets reproducibles en el repo.
Este entorno no dispone de PIL ni de ImageMagick (verificado), por lo que
cualquier pipeline debe apoyarse únicamente en la biblioteca estándar de
Python.

## Decision

Adoptamos un tile y personaje de 32 px con una paleta fija de 16 colores, y
generamos las hojas de sprites PNG mediante un script determinista
`tools/gen_art.py` que usa SOLO Python stdlib (`zlib` + `struct` para escribir
PNG; sin PIL ni ImageMagick). Las texturas se importan con
`texture_filter=NEAREST` y la cámara aplica snap a píxel para evitar
muestreo suavizado; si existe una herramienta de generación de imágenes
disponible, se usa exclusivamente para key art con el prompt "pixel art,
32x32, palette-locked, no antialiasing" y siempre con revisión humana antes
de integrarse.

## Alternatives Considered

### (a) Seguir con arte procedural

- **Pros**: Cero assets nuevos, sin coste de generación, ya funciona hoy.
- **Cons**: Techo visual bajo; la estética vectorial/procedural no transmite
  la identidad de pixel art buscada y deja los hooks de atlas sin uso.
- **Why not**: No permite competir visualmente con los mejores pixel arts,
  que es el objetivo explícito de la Capa 0.

### (b) Instalar Pillow / ImageMagick

- **Pros**: APIs maduras y cómodas para compose, escalado y paletas.
- **Cons**: Añade una dependencia externa no garantizada; el entorno actual
  no las tiene y el pipeline dejaría de ser reproducible sin instalarlas.
- **Why not**: Dependencia externa no disponible ni garantizada en este
  entorno; la generación con stdlib es autocontenida y determinista.

### (c) Sprites vectoriales

- **Pros**: Escalado limpio, tamaño de archivo pequeño, flujo de edición
  conocido.
- **Cons**: Antialiasing y curvas suaves son antitéticos al pixel art; el
  resultado se percibe como vectorial, no como sprite de 32 px.
- **Why not**: No es pixel art y contradice directamente el requisito de
  `NEAREST`, palette-locked y sin antialiasing.

## Consequences

### Positive

- Identidad visual cohesionada y palette-locked en todo el juego.
- Reproducibilidad: el mismo script genera siempre los mismos PNG.
- Diffs revisables en el repo al regenerar el arte.

### Negative

- Nuevos binarios PNG versionados en el repositorio.
- Curva de trabajo artístico: hay que producir y revisar hojas de sprites.

### Risks

- La generación determinista puede verse "machine-made" y carecer de
  intención artística → mitigación: revisión manual de cada hoja y
  cumplimiento estricto de la paleta de 16 colores antes de integrarla.
