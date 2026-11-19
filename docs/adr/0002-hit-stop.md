# ADR-002: Hit-stop en kills y headshots

- **Status**: accepted
- **Date**: 2026-11-19
- **Deciders**: Lead Orchestrator + subagentes ECC
- **Technical Story**: Capa 1 del plan maestro de conversión a pixel art profesional

## Context

`Player.gd:19-20` y `WeaponController.gd:296-298` evitan deliberadamente
tocar `Engine.time_scale` para no alterar la cadencia del combate: la
regeneración en combate se resuelve midiendo tiempo real y sin pausar el
mundo. Los mejores action games, sin embargo, usan un micro-congelamiento en
kills y headshots para dar peso tangible a los impactos. GameClock fue
eliminado en la Ronda 14, así que no existe un reloj escalado propio sobre
el que apoyar este efecto; cualquier solución debe gestionar su propio
temporizador y garantizar la restauración del escalado de tiempo.

## Decision

Aplicamos `Engine.time_scale = 0.05` durante 50-80 ms SOLO en kills y
headshots, usando un `SceneTreeTimer` creado con `process_always=true` para
que el temporizador corra aunque el mundo esté ralentizado, y garantizamos la
restauración a `1.0` en `_exit_tree()`. Nunca se aplica hit-stop en disparos
normales.

## Alternatives Considered

### (a) Freeze global en cada disparo

- **Pros**: Implementación trivial; máxima sensación de impacto en cada tiro.
- **Cons**: Arruina la cadencia de fuego, hace el combate espeso y frustra
  al jugador en hordas.
- **Why not**: Rompe el principio de no alterar el ritmo en disparos
  normales, que es la razón por la que el código evitó `time_scale`.

### (b) `Engine.time_scale` sin timer no escalado

- **Pros**: Muy pocas líneas; no requiere gestionar un `SceneTreeTimer`.
- **Cons**: Con `time_scale` bajo, un temporizador normal nunca llega a
  dispararse y el juego se queda permanentemente ralentizado.
- **Why not**: No garantiza la restauración: el valor queda en 0.05 para
  siempre.

### (c) No hacer nada

- **Pros**: Cero riesgo, cero cambios.
- **Cons**: Pérdida de game feel; los impactos carecen de peso frente a
  referentes del género.
- **Why not**: Renuncia a un objetivo explícito del plan (impacto tangible)
  sin contrapartida aceptable.

## Consequences

### Positive

- Impacto tangible y peso en los kills/headshots sin tocar disparos normales.
- El timer con `process_always=true` y la restauración en `_exit_tree()`
  hacen el efecto autocontenido y predecible.

### Negative

- Altera brevemente el timing del combate durante el hit-stop.
- Puede afectar a arneses de prueba que usan `--quit-after` si miden tiempo
  de simulación en lugar de tiempo real.

### Risks

- `time_scale` quede en 0.05 tras un crash o salida anómala → mitigación:
  restauración garantizada en `_exit_tree()` más un test de restauración
  que verifique el valor tras el hit-stop y tras salir de la escena.
