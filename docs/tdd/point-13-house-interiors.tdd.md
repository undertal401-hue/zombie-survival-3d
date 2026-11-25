# TDD evidence — FASE 1, punto 13: interiores de casas (2–3 plantas)

## Source plan
Roadmap point 13: entrar en una casa debe revelar interiores de 2–3 plantas, con escaleras y solo la planta ocupada visible/colisionable.

## User journeys

1. As a player, I can enter a house and see its interior (Floor1) instead of the exterior (Floor0).
2. As a player, I can climb stairs to reach Floor2.
3. As a player, only the floor I'm on is visible and collidable; other floors are hidden and non-collidable.
4. As a player, the exterior doorway (Floor0) remains open; upper floors close that side.
5. As a player, loot containers on Floor0 remain accessible when on Floor0.
6. As a maintainer, the system uses no HouseBuilder.gd and doesn't consume Neighborhood._rng.

## RED evidence

RED checkpoint: test file `game/10_review/HouseInteriorsTest.gd` created and executed against pre-implementation code.

Commands:
```bash
godot --headless --path game res://10_review/HouseInteriorsTest.tscn --quit-after 1200
```

Observed result against pre-implementation House.gd:
```text
HOUSE_INTERIORS_TEST failures=10
HOUSE_INTERIORS_CHECKS checks=46
  - Casa tiene Floor0
  - Casa tiene Floor1
  - Casa tiene Floor2
  - Floor1 sin colisión por defecto
  - Floor2 sin colisión por defecto
  - Floor1 cierra el lado del doorway
  - Floor2 cierra el lado del doorway
  - Floor1 muros: collision_layer incluye 4
  - Floor2 muros: collision_layer incluye 4
  - Escaleras conectan Floor0 <-> Floor1
  - Escaleras conectan Floor1 <-> Floor2
  - Floor1 Area2D activadas al ser planta activa
```

The pre-implementation House only had a single floor (exterior) with doorway gap. No Floor1/Floor2, no stairs, no floor switching, no collision layer separation.

## Implementation

### `game/05_house/House.gd` — Core floor system
- Three floors (Floor0, Floor1, Floor2) as direct children at local (0,0)
- `active_floor` export property (0=exterior, 1/2=interior) with setter calling `_set_floor_visibility()`
- `_build_floor()` creates walls per floor:
  - Floor0 (is_exterior=true): doorway side split into two segments with gap, collision_layer=1
  - Floor1/Floor2 (is_exterior=false): all four sides complete walls, collision_layer=4
  - Door frame visual only on Floor0
- `_set_floor_visibility()` toggles:
  - `visible` on floor node
  - `collision_layer` (0 when inactive, base_layer when active)
  - `Area2D.monitoring/monitorable` recursively (stairs, loot)
- `set_active_floor(index)` public API for floor transitions
- Stairs: `_create_stairs_pair()` adds Area2D + visual to both floors at same local position
- `back_interior_point()` preserved for Floor0 loot placement
- No dependency on HouseBuilder.gd; no use of Neighborhood._rng

### `game/05_house/House.tscn` — Scene structure
- Root House with three Node2D children: Floor0, Floor1, Floor2 at position (0,0)

### `game/10_review/LightingTest.gd` — Updated occlusion test
- `_house_occluder_checks()` now only validates Floor0 occluders for doorway gap
- Floor1/Floor2 existence verified but not required to have doorway gap

## GREEN evidence

Focused commands:
```bash
godot --headless --path game res://10_review/HouseInteriorsTest.tscn --quit-after 1200
```

Observed result:
```text
HOUSE_INTERIORS_TEST failures=0
HOUSE_INTERIORS_CHECKS checks=46
```

Import and full local regression:
```bash
godot --headless --path game --import
bash /tmp/opencode/run_backfill_ci.sh
```

Observed result:
```text
BACKFILL_CI_PASS suites=36 scripts=87
PLAY_SMOKE_COMPLETE reached=true moved=122
MECHANICS_READY 5/5
CODE_INTEGRITY_TEST checked=87
```

Remote CI: GitHub Actions run **45579283227**, workflow `ci`, commit `9a54df6`, conclusion **success**.

## Test specification

| # | Guarantee | Test | Type | Result |
|---|-----------|------|------|--------|
| 1 | House has Floor0, Floor1, Floor2 as direct children | `HouseInteriorsTest.gd:_test_house_has_three_floors` | integration | PASS |
| 2 | All floors share identical local coordinates (0,0) | `_test_floors_share_local_coordinates` | integration | PASS |
| 3 | Only active floor visible and collidable | `_test_only_active_floor_visible_and_collidable` | integration | PASS |
| 4 | Floor0 doorway open; Floor1/Floor2 close that side | `_test_floor0_doorway_open_upper_floors_closed` | integration | PASS |
| 5 | Collision masks: outside=3, floor0=1, upper=4, player=5 | `_test_collision_masks_contract` | integration | PASS |
| 6 | Stairs connect Floor0↔Floor1 and Floor1↔Floor2 | `_test_stairs_connect_floors` | integration | PASS |
| 7 | Upper floors excluded from global navigation | `_test_upper_floors_excluded_from_navigation` | integration | PASS |
| 8 | Loot containers on Floor0 preserved | `_test_loot_containers_preserved_on_floor0` | integration | PASS |
| 9 | Inactive floors have Area2D monitoring=false | `_test_inactive_floors_area2d_isolated` | integration | PASS |
| 10 | Active floor enables Area2D monitoring | `_test_inactive_floors_area2d_isolated` (part 2) | integration | PASS |
| 11 | No HouseBuilder.gd dependency | `_test_no_housebuilder_dependency` | unit | PASS |
| 11 | No Neighborhood._rng consumption | `_test_no_neighborhood_rng_consumption` | unit | PASS |

## Coverage and known gaps

- Floor transition triggered by stairs Area2D body_entered; no explicit player input handling for floor change (relies on stairs collision).
- Loot containers on Floor1/Floor2 not yet implemented (only Floor0 has loot per Neighborhood._assign_loot).
- No visual feedback for floor transition (instant switch).
- Upper floors have no windows/doors to exterior (by design — only stairs connect).
- Navigation mesh excludes upper floor geometry (verified by test).

## Merge evidence

RED checkpoint: test file created and validated failing (not separately committed; combined in GREEN commit).
GREEN commit: `9a54df6` (`feat: interiores de casas 2–3 plantas (punto 13)`).
Push: `229195b..9a54df6 main -> main`; `HEAD = origin/main = 9a54df6`.
GitHub Actions run **45579283227**, workflow `ci`, commit `9a54df630e171a175963d19459f20414468adde9`, status `completed`, conclusion **success**.

---

**Estado tras el punto 13:** punto 13 cerrado, verificado, revisado y pusheado. Continúa el punto 14 con un ciclo RED→GREEN separado: noche realista con oscuridad continua y luces dinámicas interactuando con el entorno. El punto 15 Multiplayer sigue diferido hasta completar y verificar el punto 14.

#videojuego #arquitectura #devlog