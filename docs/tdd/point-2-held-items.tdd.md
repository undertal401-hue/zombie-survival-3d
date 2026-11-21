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

### RED 2 — revisión de las rutas reales de señal

Checkpoint commit: `2f6e76e` (`test: cubrir el arma inicial y el seed de arranque`).

La primera GREEN demostraba el nodo aislado, pero no cubría el arranque real.
El reviewer specialist detectó que `WeaponController` equipa la pistola y emite
`weapon_changed` antes de que `Player` conecte la señal; además, el seed de
`Main` usaba `Inventory.add_item()` no silencioso y el último item —el fusil—
sustituía visualmente la pistola. El marcador también heredaba la rotación del
jugador.

Resultado: exit code `1`, `HELD_ITEM_VISUAL_TEST failures=3`:

1. el aviso inicial identificaba `Fusil 5.56mm`, no el arma equipada;
2. el marcador no compensaba la rotación;
3. el marcador no permanecía alineado con la pantalla.

## GREEN

La GREEN reemplaza los bloques de color por una ruta data-driven:

- `Inventory.ITEM_DEFS` declara la ruta oficial de cada icono.
- `Inventory.get_item_texture(id)` carga y cachea solo los assets existentes;
  si falta, devuelve `null` sin crear arte sustituto ni cachear el fallo.
- `PlayerVisual.set_held_item(id, texture)` resuelve centralmente la textura
  oficial cuando el llamador no aporta una; si falta, muestra
  `FALTA ASSET - NO INVENTAR`.
- `Player` sincroniza el arma que `WeaponController` ya tiene equipada al
  conectarse y entrega `Weapon.icon`/la ruta oficial al cambiar de arma.
- `Main` usa altas silenciosas para el seed inicial: no simula una recogida y
  no reemplaza el arma equipada en la mano.
- `PlayerVisual` compensa la rotación y el desplazamiento del marcador para
  que siga legible mientras el jugador apunta.
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
| 7 | El arma inicial real se muestra al arrancar | PASS |
| 8 | El seed inicial no sustituye el arma equipada | PASS |
| 9 | `item_picked_up` y `weapon_changed` actualizan la mano | PASS |
| 10 | El marcador permanece legible con cualquier rotación | PASS |

## Estado del contenido

La integración runtime está completa y verificada, pero el **pack visual sigue
pendiente del autor**: no existe ningún PNG oficial bajo
`game/assets/items/`. Hasta que se aporten, el juego es explícito sobre el
hueco en vez de fingir que un rectángulo coloreado es el sprite del objeto.
