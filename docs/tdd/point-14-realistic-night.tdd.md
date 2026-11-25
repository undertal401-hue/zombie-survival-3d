# TDD evidence — FASE 1, punto 14: noche realista con oscuridad continua y luces dinámicas

## Source plan
Roadmap point 14: noche realista con oscuridad continua y luces dinámicas interactuando con el entorno.

## User journeys

1. As a player, I experience continuous night darkness that transitions smoothly through dawn/day/dusk/night.
2. As a player, street lights in the town turn on/off automatically based on the time of day.
3. As a player, the night is "medium light" legible without flashlight; the flashlight cone stands out.
4. As a maintainer, WorldDirector is the single source of truth for ambient/sun energy via `apply_state()`.
5. As a maintainer, MetaProgress uses continuous `night_factor()` only when no binary `current_phase()` exists.

## RED evidence

RED checkpoint: test file `game/10_review/RealisticNightTest.gd` created and executed against pre-implementation code.

Commands:
```bash
godot --headless --path game res://10_review/RealisticNightTest.tscn --quit-after 1200
```

Observed result against pre-implementation:
```text
REALISTIC_NIGHT_TEST failures=2
REALISTIC_NIGHT_CHECKS checks=12
  - WorldDirector expone night_factor()
  - Barrio tiene farolas PointLight2D (count=0)
```

Pre-implementation: WorldDirector had no `night_factor()`, no street lights existed, Main wrote `ambient_energy` directly in forest handler.

## Implementation

### `game/01_core/WorldDirector.gd` — Continuous night factor
- Added `night_factor()` returning float [0,1] based on `_phase` and `_phase_t`:
  - dawn (0): 0.0 → 0.35
  - day (1): 0.0
  - dusk (2): 0.35 → 0.85
  - night (3): 0.85 → 1.0
- Used by DriveableVehicle, MetaProgress, StreetLight for smooth transitions.

### `game/07_house/StreetLight.gd` + `.tscn` — Real street lights
- `PointLight2D` with cone texture (`assets/art/lights/light_cone.png`), `omni_max_distance=180`, `shadow_enabled=false`.
- Auto-controls energy based on `WorldDirector.night_factor()`: off < 0.3, smooth ramp to max 1.8 at 1.0.
- `auto_control` export for manual override.

### `game/05_house/Neighborhood.gd` — Street light placement
- `_build_streetlights()` instantiates `StreetLight.tscn` at fixed positions along roads (15 lights).
- Lights added as children of Neighborhood, NOT in `nav_obstacles` group.

### `game/07_house/Main.gd` — Remove competing ambient writes
- Removed `solar_lighting.set_ambient_energy(0.62)` / `set_sun_energy(0.08)` in forest handler.
- Forest entry/exit now only emits EventBus; WorldDirector handles lighting via `apply_state()`.
- `reset_to_defaults()` on forest exit kept as legacy compatibility.

### `game/08_ui/SolarLighting.gd` — `apply_state()` intact
- Signature and behavior preserved; WorldDirector calls it with ambient, sun, angle, tint, duration.

### `game/16_meta/MetaProgress.gd` — Uses `night_factor()` correctly
- Checks `director.has_method("current_phase")` first; only uses `night_factor()` when binary phase unavailable.

## GREEN evidence

Focused commands:
```bash
godot --headless --path game res://10_review/RealisticNightTest.tscn --quit-after 1200
```

Observed result:
```text
REALISTIC_NIGHT_TEST failures=0
REALISTIC_NIGHT_CHECKS checks=55
```

Import and full local regression:
```bash
godot --headless --path game --import
bash /tmp/opencode/run_backfill_ci.sh
```

Observed result:
```text
BACKFILL_CI_PASS suites=36 scripts=89
PLAY_SMOKE_COMPLETE reached=true moved=122
MECHANICS_READY 5/5
CODE_INTEGRITY_TEST checked=89
```

Remote CI: GitHub Actions run **45582335032**, workflow `ci`, commit `596c2cb`, conclusion **success**.

## Test specification

| # | Guarantee | Test | Type | Result |
|---|-----------|------|------|--------|
| 1 | WorldDirector expone `night_factor()` continua [0,1] | `RealisticNightTest:_test_night_factor_exists_and_continuous` | unit | PASS |
| 2 | `night_factor()` varía por fase (dawn/day/dusk/night) | `_test_night_factor_values_by_phase` | integration | PASS |
| 3 | Main NO escribe `ambient_energy`/`sun_energy` directamente | `_test_no_competing_ambient_writes_in_main` | unit | PASS |
| 4 | Barrio tiene farolas PointLight2D reales (15) | `_test_street_lights_exist_and_bounded` | integration | PASS |
| 5 | Farolas son acotadas (textura cono + shadows off) | `_test_street_lights_exist_and_bounded` | integration | PASS |
| 6 | Farolas NO en `nav_obstacles` | `_test_street_lights_exist_and_bounded` | integration | PASS |
| 7 | `SolarLighting.apply_state()` intacto | `_test_solar_apply_state_intact` | unit | PASS |
| 8 | MetaProgress usa `night_factor()` solo sin `current_phase()` | `_test_meta_progress_uses_night_factor` | unit | PASS |
| 9 | Noche = media luz legible (luma ~0.68) | `_test_night_darkness_is_medium_light` | integration | PASS |
| 10 | Faro jugador energy > 0.5 de noche | `_test_night_darkness_is_medium_light` | integration | PASS |

## Coverage and known gaps

- Street lights use fixed positions along main roads; not procedurally placed per house.
- `night_factor()` is linear within each phase; could use smoother curves but current is sufficient.
- Flashlight energy smoothing uses fixed `FLASHLIGHT_SMOOTH_TAU=0.35`; not configurable.
- No dynamic shadows from street lights (shadow_enabled=false for performance).

## Merge evidence

RED checkpoint: test file created and validated failing.
GREEN commit: `596c2cb` (`feat: noche realista con oscuridad continua y luces dinámicas (punto 14)`).
Push: `9a54df6..596c2cb main -> main`; `HEAD = origin/main = 596c2cb`.
GitHub Actions run **45582335032**, workflow `ci`, commit `596c2cb66ba24e0b0a7b7e51f82335fe1410f2f7`, status `completed`, conclusion **success**.

---

**Estado tras el punto 14:** punto 14 cerrado, verificado, revisado y pusheado. Continúa el punto 15 con un ciclo RED→GREEN separado: Multiplayer (solo tras completar y verificar puntos 1–14).

#videojuego #arquitectura #devlog