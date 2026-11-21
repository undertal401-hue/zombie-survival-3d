# TDD evidence — FASE 1, punto 7: culling visual reversible

## Requisito

El culling por distancia debe ahorrar trabajo de render sin desactivar el
único bucle capaz de revertir el estado. Un zombi lejano deja de dibujarse,
pero la física sigue viva; al acercarse, vuelve a aparecer.

## RED

Checkpoint commit: `8d08290` (`test: exigir culling visual reversible`).

```bash
cd /home/unde/zombie-survival-3d/game
godot --headless --path . res://10_review/ZombieRenderCullingTest.tscn --quit-after 700
```

Resultado: exit code `1`, `ZOMBIE_RENDER_CULLING_TEST failures=3`.

La implementación anterior:

1. dejaba visible el zombi lejano;
2. llamaba `set_physics_process(false)`, por lo que no podía reactivarse;
3. al acercarse no recuperaba el procesamiento.

## GREEN

La GREEN separa el culling de la simulación:

- `Zombie._render_culled` y `_update_render_culling()` aplican una banda de
  histéresis (`culling_distance` y `0.6 * culling_distance`).
- `_set_render_culled()` cambia únicamente `visible` del `CharacterBody2D`;
  no toca `set_physics_process`, colisión, IA ni el `_physics_process`.
- Si no hay jugador disponible, el render se restaura para no dejar zombis
  ocultos durante un cambio de escena.

Resultado:

```text
ZOMBIE_RENDER_CULLING_TEST failures=0
```

## Garantías de la puerta

| # | Garantía | Resultado |
|---|---|---|
| 1 | El zombi lejano no se renderiza | PASS |
| 2 | La física permanece activa durante el culling | PASS |
| 3 | El zombi reaparece al acercarse | PASS |
| 4 | La física sigue activa tras la reactivación | PASS |
