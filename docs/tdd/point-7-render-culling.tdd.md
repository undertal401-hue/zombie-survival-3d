# TDD evidence — FASE 1, punto 7: culling visual reversible

## Requisito

El culling por distancia debe ahorrar trabajo de render sin desactivar la
simulación capaz de revertir el estado. Un zombi lejano deja de dibujarse,
pero conserva colisión e IA; al acercarse, vuelve a aparecer. La transición
debe ser estable, no reiniciar temporizadores de comportamiento y debe seguir
funcionando mientras el zombi muere lejos del jugador.

## RED 1 — culling básico

Checkpoint commit: `8d08290` (`test: exigir culling visual reversible`).

```bash
cd /home/unde/zombie-survival-3d/game
godot --headless --path . res://10_review/ZombieRenderCullingTest.tscn --quit-after 1200
```

Resultado: exit code `1`, `ZOMBIE_RENDER_CULLING_TEST failures=3`.

La implementación anterior:

1. dejaba visible el zombi lejano;
2. llamaba `set_physics_process(false)`, por lo que no podía reactivarse;
3. al acercarse no recuperaba el procesamiento.

## RED 2 — revisión independiente

Checkpoint commit: `a2b46bc` (`test: endurecer el contrato de culling reversible`).

La revisión detectó que la puerta anterior solo comprobaba dos estados y
permitía regresiones relevantes: un cadaver culled podía quedarse invisible,
la banda de histéresis no estaba garantizada, la IA y la colisión no se
comprobaban y un radio no positivo dejaba al zombi atrapado en el estado
oculto.

Resultado: exit code `1`, `ZOMBIE_RENDER_CULLING_TEST failures=4`:

```text
FAIL El culling conserva vivo el actualizador visual
FAIL La muerte conserva vivo el actualizador de visibilidad
FAIL El cadaver reaparece si el jugador se acerca durante su muerte
FAIL Una distancia de culling no positiva se normaliza
```

La segunda ejecución siguió RED por cuatro defectos de producción, no por un
fallo de sintaxis o del entorno de pruebas.

### RED 3 — temporizador de repath

Checkpoint commit: `d9ef03d` (`test: exigir que culling conserve el repath`).

La segunda revisión encontró que la transición de oculto a visible todavía
reiniciaba `_repath_timer` a cero. La puerta anterior no lo observaba y la
documentación afirmó incorrectamente que ya estaba eliminado.

Resultado: exit code `1`, `ZOMBIE_RENDER_CULLING_TEST failures=1`:

```text
FAIL La transicion de culling conserva el temporizador de repath
```

## GREEN

Checkpoint inicial: `cf8e612` (`fix: mantener visible el culling de zombis`).
Checkpoint final: `dda5c54` (`fix: conservar el repath al revertir culling`).

La GREEN mantiene el culling estrictamente visual:

- `_set_render_culled()` cambia únicamente `visible`; no toca la colisión,
  la capa física, la IA ni el estado de procesamiento de la simulación.
- La actualización de visibilidad se ejecuta en `_process()`, separada de
  `_physics_process()`. Así sigue disponible durante la animación de muerte,
  cuando la simulación del zombi ya está apagada.
- La banda de histéresis sigue siendo `culling_distance` para ocultar y
  `0.6 * culling_distance` para mostrar.
- Un cambio de culling ya no reinicia `_repath_timer`; el temporizador de
  comportamiento conserva su curso normal. La sonda de regresion lo invoca
  de forma sincronizada para evitar que un frame de fisica altere el valor.
- `culling_distance` se normaliza a un mínimo de `1.0`, evitando un radio no
  positivo que impediría recuperar el render. La puerta cubre tanto cero
  como un valor negativo.
- Sin jugador disponible, el render se restaura para no dejar zombis ocultos
  durante un cambio de escena.

Mismo comando RED:

```text
ZOMBIE_RENDER_CULLING_TEST failures=0
```

## Garantías de la puerta

| # | Garantía | Resultado |
|---|---|---|
| 1 | El zombi lejano no se renderiza | PASS |
| 2 | El culling no desactiva la física | PASS |
| 3 | El actualizador visual sigue vivo | PASS |
| 4 | La colisión y su capa permanecen intactas | PASS |
| 5 | La IA y sus temporizadores siguen avanzando | PASS |
| 6 | La transición de culling conserva `_repath_timer` | PASS |
| 7 | La banda de histéresis evita parpadeos | PASS |
| 8 | El zombi reaparece al entrar en el radio cercano | PASS |
| 9 | Un cadaver oculto reaparece si el jugador se acerca | PASS |
| 10 | Un radio cero o negativo se normaliza | PASS |

## Nota de reproducibilidad

En un checkout limpio se debe ejecutar primero `godot --headless --path game
--import`; sin la caché de clases globales, Godot puede terminar antes de
ejecutar las aserciones. CI ya realiza ese import antes de las suites.
