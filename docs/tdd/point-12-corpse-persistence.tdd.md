# TDD evidence — FASE 1, punto 12: cadáveres persistentes

## Source plan

No external plan file was supplied. The acceptance criteria were derived from
roadmap point 12: a killed zombie must remain in the world as a bloody corpse
for exactly two in-game days, while normal pause freezes world time and the
main menu remains active world time.

The project contract defines one complete `WorldDirector` cycle as one
in-game day. The production cycle is 300 seconds, so the required lifetime is:

```text
expiry_epoch = death_epoch + 2 × cycle_seconds
             = death_epoch + 600 seconds
```

## User journeys

1. As a player, I can see a zombie fall and leave a bloody corpse instead of
   disappearing after less than one second.
2. As a player, the corpse remains in the world for exactly two complete
   in-game days and is then removed at the absolute expiry boundary.
3. As a player, time spent in the main menu still consumes the corpse's
   remaining lifetime.
4. As a player, pausing the game freezes the corpse's remaining lifetime.
5. As a player, a corpse does not act as a live zombie: it cannot collide,
   navigate, separate from other actors, damage the player, or count as a
   living enemy.
6. As a player, forest and horde cleanup release living zombies without
   deleting corpses that belong to those groups.
7. As a maintainer, one lethal hit emits `EventBus.zombie_died` exactly once,
   even if the death path is invoked again.
8. As a maintainer, distance culling can hide and reveal a corpse without
   reactivating its simulation.

## RED evidence

RED checkpoint: `e451627` (`test: exigir corpses persistentes durante dos dias`).

Commands:

```bash
cd /home/unde/zombie-survival-3d
godot --headless --path game res://10_review/CorpsePersistenceTest.tscn --quit-after 1200
godot --headless --path game res://10_review/ZombieDropTest.tscn --quit-after 1200
godot --headless --path game res://10_review/ZombieRenderCullingTest.tscn --quit-after 1200
```

Observed result against the pre-fix implementation:

```text
CORPSE_PERSISTENCE_TEST failures=15
CORPSE_PERSISTENCE_CHECKS checks=33
ZOMBIE_DROP_TEST failures=2
ZOMBIE_RENDER_CULLING_TEST failures=0
```

The corpse suite failed for the intended missing behaviors: there was no
absolute world clock, no persistent corpse root, no corpse state API, no
idempotent death path, no disabled collision shape, no persistent blood, no
600-second expiry, and the horde still counted and deleted dead members.
`ZombieDropTest` independently failed because the old contract required the
boss corpse to disappear. The existing reversible-culling suite remained
green.

One earlier test-only draft attempted to read a nonexistent
`NavigationAgent2D.enabled` property in Godot 4.7.2 and produced a runtime
error. That assertion was removed before the checkpoint because the game's
actual AI-disabled contract is the zomby's physics process, velocity,
separation monitoring, and collision state. The valid RED above contains no
parse, setup, or runtime error.

## Implementation

- `game/01_core/GameState.gd` now owns an absolute, session-scoped
  `world_epoch()`. It advances during the main menu, freezes whenever the
  scene tree is paused, and remains separate from the HUD's `run_clock`.
- `GameState.world_cycle_seconds()` is the canonical cycle duration. `Main`
  publishes `WorldDirector.cycle_duration_seconds()` after session reset, so
  the corpse formula follows the director's real configuration rather than a
  duplicated literal.
- `GameState.corpse_expiry_epoch(death_epoch)` implements the single formula
  `death_epoch + 2 × cycle_seconds`. The deterministic
  `advance_world_epoch()` seam is test-only in practice and refuses to move a
  paused world.
- `game/03_zombies/Zombie.gd` preserves the original zombie node as the
  corpse. Death is idempotent, captures the absolute death/expiry epochs,
  removes the node from the live `zombies` group, adds it to `corpses`, and
  unregisters it from the central live-actor registry.
- A dead zombie now has zero collision layers/mask, an explicitly disabled
  `CollisionShape2D`, no velocity, no physics processing, and no separation
  monitoring. It keeps only the visual process needed for reversible distance
  culling.
- The death animation no longer fades to alpha zero or queues the node for
  deletion. The node remains in its final death frame and expires only when
  `world_epoch >= expiry_epoch`.
- `Main/Corpses` is the direct, persistent root for corpses in the production
  scene. The same `Zombie` node is reparented there with its global transform
  preserved. Root lookup prioritizes the current scene and rejects stale or
  foreign roots.
- `game/03_zombies/Zombie.tscn` adds `CorpseBlood` using frame 0 of the
  existing supplied `effects.png` blood-splat sheet. It is hidden while the
  zombie lives and becomes visible on death. No new artwork was generated.
- `ForestZombies._spawned` and `WorldDirector._horde_zombies` are live-only.
  Forest cleanup already removed dead nodes; `WorldDirector` now does the
  same through the existing `zombie_died` signal without re-emitting it.
- `WorldDirector` explicitly uses `PROCESS_MODE_PAUSABLE`. A normal tree pause
  freezes both its cycle progress and `GameState.world_epoch()`.

## GREEN evidence

Focused commands:

```bash
godot --headless --path game res://10_review/CorpsePersistenceTest.tscn --quit-after 1200
godot --headless --path game res://10_review/ZombieDropTest.tscn --quit-after 1200
godot --headless --path game res://10_review/ZombieRenderCullingTest.tscn --quit-after 1200
godot --headless --path game res://10_review/AiWaveTest.tscn --quit-after 1200
godot --headless --path game res://10_review/ZombieEventPayloadTest.tscn --quit-after 1200
```

Observed result:

```text
CORPSE_PERSISTENCE_TEST failures=0
CORPSE_PERSISTENCE_CHECKS checks=61
ZOMBIE_DROP_TEST failures=0
ZOMBIE_RENDER_CULLING_TEST failures=0
AI_WAVE_TEST failures=0
ZOMBIE_EVENT_PAYLOAD_TEST failures=0
```

Import and full local regression commands:

```bash
godot --headless --path game --import
bash /tmp/opencode/run_backfill_ci.sh
```

Observed result: import `rc=0`; all 36 regression suites pass, including
`PLAY_SMOKE_COMPLETE` and `MECHANICS_READY 5/5`. The project scan covers 86
versioned Godot scripts. The canonical summary was:

```text
BACKFILL_CI_PASS suites=36 scripts=86
```

## Test specification

| # | Guarantee | Test | Type | Result |
|---|---|---|---|---|
| 1 | The production scene owns a persistent corpse root | `CorpsePersistenceTest.gd` | integration | PASS |
| 2 | GameState exposes an absolute world clock independent of `run_clock` | `CorpsePersistenceTest.gd` | integration | PASS |
| 3 | Menu time advances the world epoch without advancing the run clock | `CorpsePersistenceTest.gd` | integration | PASS |
| 4 | A normal tree pause freezes both the epoch and WorldDirector cycle | `CorpsePersistenceTest.gd` | integration | PASS |
| 5 | The QA epoch seam cannot skip a paused world | `CorpsePersistenceTest.gd` | regression | PASS |
| 6 | A lethal hit emits `zombie_died` exactly once | `CorpsePersistenceTest.gd` | integration | PASS |
| 7 | The same node changes from live actor to corpse without duplication | `CorpsePersistenceTest.gd` | integration | PASS |
| 8 | Corpse physics, velocity, separation, and all collision layers are disabled | `CorpsePersistenceTest.gd` | integration | PASS |
| 9 | The corpse survives beyond the old 0.86-second death animation | `CorpsePersistenceTest.gd` | integration | PASS |
| 10 | The corpse retains its final visible frame and persistent pixel-art blood | `CorpsePersistenceTest.gd` | integration | PASS |
| 11 | Death and expiry epochs are captured at the real lethal hit | `CorpsePersistenceTest.gd` | integration | PASS |
| 12 | Expiry is exactly `death_epoch + 2 × cycle_seconds` | `CorpsePersistenceTest.gd` | boundary | PASS |
| 13 | The 300-second production cycle yields an exact 600-second corpse | `CorpsePersistenceTest.gd` | boundary | PASS |
| 14 | The corpse survives immediately before expiry and is removed at expiry | `CorpsePersistenceTest.gd` | boundary | PASS |
| 15 | Menu time can consume the full remaining corpse lifetime | `CorpsePersistenceTest.gd` | integration | PASS |
| 16 | A paused corpse cannot expire | `CorpsePersistenceTest.gd` | integration | PASS |
| 17 | A configurable 12.5-second cycle yields a 25-second corpse | `CorpsePersistenceTest.gd` | boundary | PASS |
| 18 | Forest ownership contains live zombies only | `CorpsePersistenceTest.gd` | integration | PASS |
| 19 | Leaving the forest releases live zombies but preserves the corpse | `CorpsePersistenceTest.gd` | integration | PASS |
| 20 | Horde ownership and `horde_size()` contain live zombies only | `CorpsePersistenceTest.gd` | integration | PASS |
| 21 | Dispersing the horde releases live zombies but preserves the corpse | `CorpsePersistenceTest.gd` | integration | PASS |
| 22 | Distance culling hides and reveals the corpse without reactivating AI | `CorpsePersistenceTest.gd` | integration | PASS |
| 23 | Point-11 physical drops survive the new persistent corpse lifecycle | `ZombieDropTest.gd` | regression | PASS |
| 24 | Existing reversible culling behavior remains intact | `ZombieRenderCullingTest.gd` | regression | PASS |

## Coverage and known gaps

The dedicated suite exercises the real `Main`, `Player`, `GameState`,
`WorldDirector`, `ForestZombies`, `Zombie`, lethal-damage path, corpse root,
blood sprite, collision state, and the actual forest-entry/exit and
horde-trigger/dispersion lifecycles. Boundary coverage uses deterministic
epoch advancement rather than waiting ten real minutes.

Corpses intentionally remain until their absolute expiry or the current scene
is reloaded. No unapproved corpse cap or pooling was introduced, because the
roadmap explicitly requires the original body to persist for two days. The
existing deterministic art pipeline remains unchanged: the corpse blood reuses
the supplied `effects.png` sheet and no substitute or fabricated item artwork
was added.

## Merge evidence

The preserved RED checkpoint is `e451627`. The GREEN checkpoint is the commit
containing this report and the production change. The remote CI run and final
specialist verdict are recorded in the project vault bitácora after the push.
