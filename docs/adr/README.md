# Architecture Decision Records (ADRs)

Este directorio contiene las decisiones de arquitectura del proyecto
`zombie-survival-3d`, registradas en formato Nygard adaptado. Cada ADR es
inmutable: para cambiar una decisión se crea un nuevo ADR que la reemplaza.

## Índice

| ADR | Title | Status | Date |
| --- | --- | --- | --- |
| [ADR-001](0001-pixel-art-pipeline.md) | Pipeline de pixel art determinista | accepted (parcialmente superseded por ADR-004) | 2026-11-19 |
| [ADR-002](0002-hit-stop.md) | Hit-stop en kills y headshots | accepted | 2026-11-19 |
| [ADR-003](0003-meta-progression-tree.md) | Árbol de progresión entre partidas | accepted | 2026-11-19 |
| [ADR-004](0004-revert-presentation-and-real-lighting.md) | Reversión de la presentación e iluminación 2D real | accepted | 2026-11-20 |

## Notas de estado

- **ADR-001** sigue vigente como **herramienta**: `tools/gen_art.py`,
  `assets/art/ART_BIBLE.md`, las hojas PNG y el paso
  `verify deterministic art pipeline` del CI se conservan. Lo que ADR-004
  cambia es su alcance en *runtime*: el pipeline deja de ser la presentación
  del juego y pasa a ser el banco de trabajo del arte futuro, con
  `USE_SPRITE_ART = false` como interruptor explícito.
- **ADR-002** y **ADR-003** no se ven afectados por ADR-004: hit-stop y
  meta-árbol son mecánicas, no presentación.
