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

### RED 2 — revisión specialist

Checkpoint commit: `b8bc818` (`test: endurecer el contrato visual del proyectil`).

La primera puerta comprobaba que `texture` no fuera `null`, pero una celda
totalmente transparente o un proyectil que se ocultara después del primer
frame también pasaban. Tampoco exigía terminar exactamente en el impacto.

Resultado: exit code `1`, `PROJECTILE_VISUAL_TEST failures=3`:

1. el proyectil nacía en el centro del cuerpo, no en la boca del arma;
2. terminaba antes del punto de impacto por el redondeo del paso;
3. una instancia sin textura quedaba oculta e immortal.

## GREEN

La GREEN usa exclusivamente el efecto existente `bullet_sparks` (tercera celda
de 32×32 de `effects.png`) mediante un `AtlasTexture`:

- `Projectile.tscn` asigna la textura real, el centro del sprite y el filtro
  nearest; ya no existe un `Sprite2D` vacío.
- `Projectile.launch()` configura destino, alcance, daño y shooter en una sola
  transición, conserva `start_pos` y activa la visibilidad.
- `Projectile._ready()` libera una instancia sin textura en vez de dejarla
  oculta e immortal dentro de la escena.
- `Projectile._process()` limita cada paso al tramo restante y al rango
  disponible: el proyectil termina exactamente en el impacto, sin sobrepasarlo.
- `Player._fire_hitscan()` conserva el raycast y el daño desde el centro del
  jugador, pero presenta el proyectil desde la boca del arma. El offset se
  recorta para impactos cercanos y se compensa en el rango visual.
- La puerta valida la celda `bullet_sparks`, sus píxeles visibles, el vuelo
  completo, los ocho perdigones de la escopeta y el daño hitscan una sola vez.

Resultado:

```text
PROJECTILE_VISUAL_TEST failures=0
```

## Garantías de la puerta

| # | Garantía | Resultado |
|---|---|---|
| 1 | El disparo crea un proyectil | PASS |
| 2 | El proyectil nace con textura real | PASS |
| 3 | La textura usa la celda canónica y contiene alpha visible | PASS |
| 4 | Permanece visible durante todo el vuelo | PASS |
| 5 | Emerge de la boca y conserva el punto de impacto | PASS |
| 6 | Termina exactamente en el impacto y se libera | PASS |
| 7 | La escopeta crea un proyectil por perdigón | PASS |
| 8 | El daño hitscan se aplica una sola vez | PASS |
| 9 | Un proyectil sin textura se libera | PASS |
