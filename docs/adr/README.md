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
| [ADR-005](0005-hybrid-zombie-sprite-presentation.md) | Presentación híbrida de los zombis: skin de sprites para el rango bajo y cubo para los rangos altos | accepted (parcialmente superseded por ADR-006) | 2026-11-20 |
| [ADR-006](0006-walker-only-roster-bounded-sun-shadows-and-detection.md) | Roster de un solo arquetipo, sombras solares acotadas y detección del jugador reforzada | accepted | 2026-11-20 |

## Notas de estado

- **ADR-001** sigue vigente como **herramienta y fuente canónica**: se conservan
  `tools/gen_art.py`, `assets/art/ART_BIBLE.md`, las cinco hojas PNG del banco
  R3, dos mapas de luz, la máscara de sombra y su paso de CI. ADR-004 limitó su
  uso en runtime; ADR-005 vuelve a aprovechar el humanoide cenital y la paleta
  de 16 colores para generar el skin del WALKER, con un pack y una puerta de CI
  separados.
- **ADR-004** queda **parcialmente superseded por ADR-005** solo en la
  presentación de los zombis: el WALKER usa skin y los rangos altos conservan
  el cubo. La iluminación real, el faro, las sombras proyectadas y las demás
  invariantes de ADR-004 no cambian.
- **ADR-005** fija la presentación híbrida, el contrato de celda de 64×64 y el
  fallback seguro al cubo. `gen_art.py --check` conserva su alcance sobre las
  cinco hojas canónicas del banco R3; el skin tiene sus propias puertas de
  verificación. Las enmiendas R2-hotfix y R2-hotfix4 documentan sus
  correcciones de lock, carga, tinte, auditoría e importación transaccional
  sin reescribir el registro accepted.
- **ADR-006** (R3) **supersede a ADR-005 en su §1 y en sus invariantes 2 y
  15**: el juego tiene un solo arquetipo de zombi (el caminante) y el jefe
  «Tanque Alfa» pasa a ser un perfil del mismo zombi, así que el cubo queda
  como fallback único y no como la presentación de otro arquetipo. El contrato
  de skin (celda 64×64, ancla, pivot, fallback) y sus puertas de CI siguen
  vigentes. **ADR-006 también toca ADR-004 en un solo punto**: el sol deja de
  proyectar sombra direccional (en Godot 4 esa sombra no tiene largo y llega
  hasta el borde de pantalla) y las sombras diurnas pasan a ser manchas
  acotadas con cota dura. Su enmienda R3-hotfix precisa el anclaje mundial
  exacto, el eje largo, la cota transversal, la convención real de
  `DirectionalLight2D`, el material `UNSHADED`, el faro en runtime, el roster de
  FX y la puerta determinista del banco de arte.
  **La iluminación nocturna, el faro y sus sombras reales no cambian**: es la
  restricción que el usuario puso expresamente.
- **ADR-002** y **ADR-003** no se ven afectados por ADR-004, ADR-005 ni
  ADR-006: hit-stop y meta-árbol son mecánicas, no presentación.
