# TDD evidence — FASE 1, punto 3: disparos visibles

## Requisito

Cada disparo debe producir un proyectil visible durante su trayecto. La bala
no puede quedar oculta ni ser un `Sprite2D` sin imagen. El proyecto ya
incluye el efecto pixel-art canónico `bullet_sparks` en
`assets/art/sprites/effects.png`; no se genera ni modifica arte nuevo.

## RED

Checkpoint commit: `41c68b3` (`test: exigir proyectiles visibles en vuelo`).

```bash
cd /home/unde/zombie-survival-3d/game
godot --headless --path . res://10_review/ProjectileVisualTest.tscn --quit-after 700
```

Resultado: exit code `1`, `PROJECTILE_VISUAL_TEST failures=5`.

El arnés reprodujo el camino real `Player._fire_hitscan()` y demonstro que el
proyectil anterior:

1. nacía sin textura;
2. no tenía dimensiones visuales;
3. permanecía oculto;
4. no conservaba el origen real del disparo;
5. no avanzaba durante el vuelo.

## GREEN

La GREEN usa exclusivamente el efecto existente `bullet_sparks` (tercera celda
de 32×32 de `effects.png`) mediante un `AtlasTexture`:

- `Projectile.tscn` asigna la textura real, el centro del sprite y el filtro
  nearest; ya no existe un `Sprite2D` vacío.
- `Projectile.launch()` configura destino, alcance, daño y shooter en una sola
  transición, conserva `start_pos` y activa la visibilidad.
- `Projectile._ready()` solo oculta el objeto si su textura no pudo cargarse.
- `Player._fire_hitscan()` añade el proyectil a la escena y ejecuta `launch()`.
  Esto corrige además el fallo previo de comparar la posición contra `(0,0)`,
  que hacía que la bala desapareciera antes de viajar en el mapa real.

Resultado:

```text
PROJECTILE_VISUAL_TEST failures=0
```

## Garantías de la puerta

| # | Garantía | Resultado |
|---|---|---|
| 1 | El disparo crea un proyectil | PASS |
| 2 | El proyectil nace con textura real | PASS |
| 3 | La textura tiene dimensiones utilizables | PASS |
| 4 | Permanece visible durante el vuelo | PASS |
| 5 | Conserva el origen real del disparo | PASS |
| 6 | Avanza hacia el objetivo | PASS |
