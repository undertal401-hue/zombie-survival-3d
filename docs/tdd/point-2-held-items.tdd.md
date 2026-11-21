# TDD evidence — FASE 1, punto 2: objetos visibles en la mano

## Requisito

Los objetos recogidos y las armas equipadas deben verse en el personaje con su
sprite real. El proyecto no contiene todavía el pack final de iconos y la
regla de arte es explícita: **no inventar assets**; cuando falte uno, mostrar
`FALTA ASSET - NO INVENTAR`.

## RED

Checkpoint commit: `274c03b` (`test: exigir sprites reales para objetos en mano`).

```bash
cd /home/unde/zombie-survival-3d/game
godot --headless --path . res://10_review/HeldItemVisualTest.tscn --quit-after 700
```

Resultado: exit code `1`, `HELD_ITEM_VISUAL_TEST failures=5`.

Los cinco fallos probaron que la implementación anterior:

1. no tenía un marcador para el asset pendiente;
2. fabricaba una `ImageTexture` de 16×16 como bloque de color;
3. no comunicaba `FALTA ASSET - NO INVENTAR`;
4. no aceptaba un `Texture2D` data-driven;
5. `Inventory` no resolvía rutas de iconos.

## GREEN

La GREEN reemplaza los bloques de color por una ruta data-driven:

- `Inventory.ITEM_DEFS` declara la ruta oficial de cada icono.
- `Inventory.get_item_texture(id)` carga y cachea el asset solo si existe;
  si falta, devuelve `null` sin crear arte sustituto.
- `PlayerVisual.set_held_item(id, texture)` muestra el `Texture2D` real cuando
  existe y, en caso contrario, muestra exactamente
  `FALTA ASSET - NO INVENTAR`.
- `Player` entrega `Weapon.icon` al cambiar de arma y
  `Inventory.get_item_texture(item_id)` al recoger un objeto.
- `assets/items/README.md` registra las 14 rutas pendientes y la política de
  no invención.

Resultado:

```text
HELD_ITEM_VISUAL_TEST failures=0
CI_LOCAL_SUMMARY total=30 passed=30 failed=0
PLAY_SMOKE_COMPLETE reached=true moved=122
MECHANICS_READY 5/5
```

## Garantías de la puerta

| # | Garantía | Resultado |
|---|---|---|
| 1 | `HeldItem` es un `Sprite2D` real | PASS |
| 2 | Un asset ausente no genera textura de color | PASS |
| 3 | Un asset ausente muestra `FALTA ASSET - NO INVENTAR` | PASS |
| 4 | Un `Texture2D` real se muestra en `HeldItem` | PASS |
| 5 | El marcador se oculta cuando existe sprite real | PASS |
| 6 | `Inventory` resuelve la ruta data-driven sin inventar arte | PASS |

## Estado del contenido

La integración runtime está completa y verificada, pero el **pack visual sigue
pendiente del autor**: no existe ningún PNG oficial bajo
`game/assets/items/`. Hasta que se aporten, el juego es explícito sobre el
hueco en vez de fingir que un rectángulo coloreado es el sprite del objeto.
