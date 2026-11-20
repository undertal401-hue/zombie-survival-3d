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
| [ADR-004](0004-revert-presentation-and-real-lighting.md) | Reversión de la presentación e iluminación 2D real | accepted (parcialmente superseded por ADR-005) | 2026-11-20 |
| [ADR-005](0005-hybrid-zombie-sprite-presentation.md) | Presentación híbrida de los zombis: skin de sprites para el rango bajo y cubo para los rangos altos | accepted | 2026-11-20 |

## Notas de estado

- **ADR-001** sigue vigente como **herramienta y fuente canónica**: se conservan
  `tools/gen_art.py`, `assets/art/ART_BIBLE.md`, las nueve hojas PNG y su paso
  de CI. ADR-004 limitó su uso en runtime; ADR-005 vuelve a aprovechar el
  humanoide cenital y la paleta de 16 colores para generar únicamente el skin
  del WALKER, con un pack y una puerta de CI separados.
- **ADR-004** queda **parcialmente superseded por ADR-005** solo en la
  presentación de los zombis: el WALKER usa skin y los rangos altos conservan
  el cubo. La iluminación real, el faro, las sombras proyectadas y las demás
  invariantes de ADR-004 no cambian.
- **ADR-005** fija la presentación híbrida, el contrato de celda de 64×64 y el
  fallback seguro al cubo. `gen_art.py --check` conserva su alcance sobre las
  nueve hojas canónicas; el skin tiene sus propias puertas de verificación.
- **ADR-002** y **ADR-003** no se ven afectados por ADR-004 ni ADR-005:
  hit-stop y meta-árbol son mecánicas, no presentación.
