# TDD evidence — FASE 1, punto 11: botín físico de zombis

## Source plan

No external plan file was supplied. The acceptance criteria were derived from
roadmap point 11: a killed zombie must leave collectible physical objects in
the world instead of granting its reward directly to the player's inventory.

## User journeys

1. As a player, killing a zombie does not silently mutate my inventory.
2. As a player, I can see and walk over the reward the zombie left behind.
3. As a player, a boss leaves the same scrap, medkit, and conditional ammo
   rewards it dropped under the previous direct-grant implementation.
4. As a player, if my inventory can accept only part of a stack, the remaining
   units stay in the world and can be collected later without duplication.
5. As a maintainer, zombie drops survive corpse, forest, and horde cleanup and
   are removed only when collected or when the current scene is reloaded.
6. As a maintainer, a missing official item icon is reported honestly instead
   of being replaced by fabricated artwork.

## RED evidence

### Initial RED checkpoint

RED checkpoint: `f5cc67a` (`test: exigir botin fisico de zombis`).

Commands:

```bash
cd /home/unde/zombie-survival-3d
godot --headless --path game res://10_review/ZombieDropTest.tscn --quit-after 1200
godot --headless --path game res://10_review/AiWaveTest.tscn --quit-after 1200
```

Observed result against the pre-fix implementation:

```text
ZOMBIE_DROP_TEST failures=10
AI_WAVE_TEST failures=4
```

The ten failures proved that zombie death still granted scrap, medkit, and
ammo directly to `Inventory`; that no physical pickups were created; and that
no persistent world-owned drop root existed. The four AI-wave failures proved
that the stale suite still encoded the old direct-grant contract.

The RED run was preceded by one test-only parse correction (the scrap amount
had been declared inside a branch). The valid RED above was compiled and
executed; its failures were caused by the missing point-11 behavior, not by a
setup, syntax, or dependency error.

### Hardened RED checkpoint

Independent review found that the initial gate left the conditional-ammo
policy partly vacuous and did not exercise forest/horde cleanup. A second
test-only checkpoint was therefore created before production was restored:

`09016c7` (`test: endurecer contrato de botin fisico`).

The production candidate was temporarily removed, the strengthened suite was
compiled and executed against the original implementation, and the result was:

```text
ZOMBIE_DROP_TEST failures=25
AI_WAVE_TEST failures=4
```

This run also had no parse or setup failure. The additional failures came from
the absent physical rewards, absent deterministic boss branch matrix, absent
world-scene root priority, and absent cleanup persistence. The collection
arithmetic correction was included in this checkpoint and is regression
coverage of the existing `Pickup` partial-collection contract, not a new
production behavior.

### Boundary and lifecycle RED checkpoint

A second independent review found that four representative seeds did not pin
all three shared-ammo thresholds and that calling private cleanup methods did
not prove the real event wiring. A third test-only checkpoint was created
before production was restored again:

`22d3937` (`test: fijar umbrales y ciclos de botin`).

The original implementation was replayed with six seeds immediately below and
above each threshold and with the real `forest_entered`/`forest_exited` and
`trigger_horde`/horde-dispersion lifecycle. The result was:

```text
ZOMBIE_DROP_TEST failures=56
AI_WAVE_TEST failures=4
```

The final valid RED run had no parse, setup, or runtime errors. Its failures
were caused by the still-direct inventory grants and absent physical rewards.
The six boundary seeds lock the exact branch selected immediately below and
above 0.30, 0.50, and 0.70, while the lifecycle cases prove that the actual
forest and horde actors are spawned and cleaned through their public signals
and lifecycle paths.

### Walker policy RED checkpoint

Final specialist review found that the boss matrix was exhaustive but the
walker's conditional policy could still pass while dropping nothing. A fourth
test-only checkpoint was therefore created before production was restored again:

`60b2ce8` (`test: fijar politica rng del caminante`).

The original implementation was replayed with 14 deterministic walker cases.
The matrix fixes both sides of the 0.18 material threshold, the 0.60 scrap/tela
split, and the 0.08/0.12/0.15 cumulative ammunition thresholds. It also checks
the exact draw order, exact reward IDs and amounts, the valid no-reward branch,
and combinations of material plus ammunition. The result was:

```text
ZOMBIE_DROP_TEST failures=108
AI_WAVE_TEST failures=4
```

The final valid RED run had no parse or setup failure. The additional failures
were caused by the still-direct inventory grants, absent physical rewards, and
the walker policy constants not yet being exposed as an exact test contract.
The same checkpoint adds direct regression coverage for a group root already
pending `queue_free()`.

## Implementation

- `game/03_zombies/Zombie.gd` preserves the existing `GameState.rng(&"loot")`
  call order and thresholds. The boss still rolls 5–8 scrap, uses one shared
  ammo roll with the same 0.70/0.50/0.30 thresholds, and rolls 1–2 medkits.
  The walker still has an 18% material chance, split 60/40 between scrap and
  cloth, and cumulative ammunition thresholds of 0.08/0.12/0.15. These are
  marginal 8% pistol, 4% shotgun, 3% rifle, and 85% no-ammunition branches.
  The exact thresholds are named constants so the test gate can detect any
  policy drift without duplicating implementation literals in the test.
- Every rolled reward is now one `Pickup.tscn` instance containing the rolled
  stack amount. No zombie reward calls `Inventory.add_item()`.
- `game/07_house/Main.tscn` owns a direct `Main/ZombieDrops` root in the
  `zombie_drop_root` group. Pickups are not children of the dying zombie,
  `ForestZombies`, or `WorldDirector`, so corpse, forest, and horde cleanup
  cannot delete them early. A full scene reload still resets the world.
- Root resolution prioritizes the current scene's direct `ZombieDrops` child.
  Group lookup is restricted to descendants of that scene, and a root that is
  invalid, outside the tree, or pending deletion is rejected. This prevents a
  stale root from another scene or transition from receiving the reward.
- Failure to resolve a valid root or instantiate a physical pickup is reported
  explicitly with `push_error()` instead of silently discarding the reward.
- `Pickup.gd` and `Pickup.tscn` are reused unchanged. The existing partial
  collection contract remains authoritative: only accepted units enter the
  inventory, the pending amount stays on the pickup, and the pickup is freed
  only when its pending amount reaches zero.
- Fixed non-random offsets prevent a boss's multiple rewards from occupying
  exactly the same point. They do not consume or alter the loot RNG stream.
- The official item PNG pack remains absent. Zombie rewards therefore show
  exactly `FALTA ASSET - NO INVENTAR`; no substitute art is generated.

## GREEN evidence

Focused commands:

```bash
godot --headless --path game res://10_review/ZombieDropTest.tscn --quit-after 1200
godot --headless --path game res://10_review/AiWaveTest.tscn --quit-after 1200
```

Observed result:

```text
ZOMBIE_DROP_TEST failures=0
AI_WAVE_TEST failures=0
```

Import and full local regression commands:

```bash
godot --headless --path game --import
bash /tmp/opencode/run_backfill_ci.sh
```

Observed result: import `rc=0`; all 35 regression suites pass, including
`PLAY_SMOKE_COMPLETE` and `MECHANICS_READY 5/5`. The project scan covers 85
versioned Godot scripts. The canonical summary was:

```text
BACKFILL_CI_PASS suites=35 scripts=85
```

## Test specification

| # | Guarantee | Test | Type | Result |
|---|---|---|---|---|
| 1 | Zombie death does not immediately mutate the inventory | `ZombieDropTest.gd` | integration | PASS |
| 2 | A boss creates 2–5 physical reward pickups | `ZombieDropTest.gd` | integration | PASS |
| 3 | Every reward ID belongs to the allowed set and every amount is positive | `ZombieDropTest.gd` | regression | PASS |
| 4 | Scrap and medkit remain one stack with their original ranges | `ZombieDropTest.gd` | integration | PASS |
| 5 | Conditional boss ammo follows one shared roll and the original thresholds | `ZombieDropTest.gd` | deterministic matrix | PASS |
| 6 | The boss matrix locks exact IDs and amounts immediately below and above every ammo threshold | `ZombieDropTest.gd` | deterministic matrix | PASS |
| 7 | The walker cannot directly grant material or any ammo type | `AiWaveTest.gd` | regression | PASS |
| 8 | Every reward belongs to the current scene's persistent `Main/ZombieDrops` root | `ZombieDropTest.gd` | integration | PASS |
| 9 | A foreign root in the same group cannot steal the reward | `ZombieDropTest.gd` | regression | PASS |
| 10 | A reward survives the corpse's visual teardown | `ZombieDropTest.gd` | integration | PASS |
| 11 | A reward survives the real forest-entry/exit cleanup lifecycle | `ZombieDropTest.gd` | integration | PASS |
| 12 | A reward survives the real horde-trigger/dispersion cleanup lifecycle | `ZombieDropTest.gd` | integration | PASS |
| 13 | Missing official artwork uses the exact missing-asset label and hides substitute art | `ZombieDropTest.gd` | regression | PASS |
| 14 | Partial acceptance retains every uncollected unit | `ZombieDropTest.gd` | regression | PASS |
| 15 | Accepted units are never granted twice, including after capacity is reopened | `ZombieDropTest.gd` | regression | PASS |
| 16 | Walker material, split, and cumulative ammunition thresholds are exact on both sides of every boundary | `ZombieDropTest.gd` | deterministic matrix | PASS |
| 17 | Walker draw order, exact IDs and quantities, no-reward branch, and material-plus-ammo combinations are preserved | `ZombieDropTest.gd` | deterministic matrix | PASS |
| 18 | A group root already pending deletion cannot own a reward | `ZombieDropTest.gd` | regression | PASS |

## Coverage and known gaps

The dedicated suite exercises the real `Main`, `Player`, `Inventory`, `Zombie`,
lethal damage path, `Pickup` area, `ForestZombies`, `WorldDirector`, and
persistent world hierarchy. The boss branch matrix uses six deterministic
master seeds immediately below and above every shared-ammo threshold and locks
the resulting IDs and quantities. The walker matrix uses 14 deterministic cases
to lock both sides of every material, split, and cumulative-ammo threshold,
the exact draw order, exact quantities, valid no-reward outcomes, and combined
material/ammo rewards. The forest and horde cases exercise their real spawn
and cleanup lifecycles rather than mutating private lists. The AI-wave gate
keeps an independent full-inventory anti-direct-grant smoke check.

Drops intentionally remain until collected or the scene reloads; no unapproved
TTL or per-map cap was introduced. The official PNG pack is still absent, so
the rendered reward uses the honest missing-asset path rather than claiming
that final item artwork exists.

## Merge evidence

The preserved RED checkpoints are `f5cc67a`, `09016c7`, `22d3937`, and
`60b2ce8`.
The GREEN checkpoint is the commit containing this report and the production change.
The remote CI run and final specialist verdicts are recorded in the project
vault bitácora after the push.
