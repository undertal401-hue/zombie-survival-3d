# ADR-003: Árbol de progresión entre partidas

- **Status**: accepted
- **Date**: 2026-11-19
- **Deciders**: Lead Orchestrator + subagentes ECC
- **Technical Story**: Capa 2 del plan maestro de conversión a pixel art profesional

## Context

`MetaProgress.gd` es hoy un contenedor de progreso meta persistente y logros
en `user://` (`meta_progress.json`, versión 1): registra logros cosméticos y
títulos, y vuelve silenciosamente a valores iniciales si el archivo está
corrupto. No ofrece ninguna decisión entre partidas: no hay ramas, niveles ni
efectos que el jugador elija al empezar una nueva run. El plan maestro pide
sistemas que incentiven la rejugabilidad sin invadir el inventario o la
artesanía propios de cada partida.

## Decision

Convertimos `MetaProgress.gd` en un árbol de progresión de 3 ramas —
supervivencia, arsenal y botín — con al menos 2 niveles por rama, persistido
en `user://` con migración segura de saves antiguos (versionado + fallback)
y con los efectos de los nodos desbloqueados aplicados al iniciar partida.

## Alternatives Considered

### (a) Mejoras temporales dentro de la partida

- **Pros**: Fácil de balancear por run; no toca el sistema de guardado.
- **Cons**: Solapa con el inventario y la artesanía ya existentes y no
  perdura entre partidas.
- **Why not**: El inventario/la artesanía ya cubren las mejoras
  intra-partida; no aporta progresión meta ni decisiones entre runs.

### (b) Microtransacciones

- **Pros**: Fuente de ingresos y aceleración de progresión.
- **Cons**: Fuera de alcance del plan, añade backend, pagos y consideraciones
  legales; rompe el alcance offline del juego.
- **Why not**: Explícitamente fuera de alcance; el juego es offline y no hay
  infraestructura de pagos.

### (c) Simplemente más logros

- **Pros**: Coste mínimo; reutiliza el sistema actual de logros y títulos.
- **Cons**: Los logros son retrospective y cosméticos; no generan decisiones
  ni cambian la siguiente partida.
- **Why not**: No aporta decisiones entre partidas, que es el objetivo de
  esta decisión.

## Consequences

### Positive

- Rejugabilidad: el jugador elige qué rama priorizar entre partidas.
- Progreso persistente con sentido, separado del estado de cada run.

### Negative

- Mayor complejidad en el esquema de guardado y en la migración de versiones.
- Hay que definir y balancear los efectos aplicados al inicio de partida.

### Risks

- Corromper saves antiguos al cambiar el formato → mitigación: versionado
  del JSON (`SAVE_VERSION`), migración controlada y fallback a valores
  iniciales si la lectura falla, preservando el comportamiento silencioso
  actual ante archivos corruptos.
