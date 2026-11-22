# TDD evidence — FASE 1, punto 10: talar árboles con hacha

## Source plan

No external plan file was supplied. The acceptance criteria were derived from
roadmap point 10: an axe must fell a tree, the tree must fall visibly, and the
felled tree must yield collectible wood. The implementation also preserves the
existing procedural-forest batching/chunking and the established six-slot
loadout contract.

## User journeys

1. As a player, I can equip an axe and fell a physical tree by striking it.
2. As a player, I can see the struck tree rotate around its base and fall over.
3. As a player, I can collect the wood released by the felled tree.
4. As a player, I keep the existing weapons, the axe, and the meta-progression
   weapon reward in six distinct quick-select slots.
5. As a maintainer, missing item artwork is reported honestly rather than
   replaced by fabricated placeholder art.

## RED evidence

Initial RED checkpoint: `027cc63` (`test: exigir talado de arboles con hacha`).

The corrected RED checkpoint is `204a984` (`test: exigir seis ranuras y
colision por forma`). It restores the established six-slot contract and
requires tree identity to be the exact `(body RID, shape index)` pair.

Command:

```bash
cd /home/unde/zombie-survival-3d
godot --headless --path game res://10_review/TreeFellingTest.tscn --quit-after 900
godot --headless --path game res://10_review/ArsenalTest.tscn --quit-after 900
```

Observed result against the corrected RED commit:

```text
IMPORT_RC=0 TREE_RC=1 ARSENAL_RC=1
TREE_FELLING_TEST failures=8
ARSENAL_TEST failures=3
POINT10_EXACT_RED_CONFIRMED
```

The eight tree failures proved that there was no real axe resource, no six-slot
loadout, no direct key for slot 6, no axe slot, no wood/axe inventory entries,
and no honest missing-art presentation for those entries. The arsenal failures
proved the loadout and axe slot contracts were absent.

### Review RED evidence

Specialist review reproduced a high-severity resource-loss defect and several
coverage gaps. The regression contract was hardened in checkpoint `1ed7967`
(`test: endurecer tala y recogidas parciales`).

Observed result against the pre-fix implementation:

```text
TREE_FELLING_TEST failures=5
ARSENAL_TEST failures=1
```

The tree failures proved that the test could not observe the real tree height,
the base pivot or the canopy transform, and that a partially accepted three-unit
wood pickup was destroyed with two units still pending. The arsenal failure
proved that a legacy five-slot save left the mandatory axe slot empty.

A second specialist review then exercised the real legacy v1 layout: five
entries with the old meta shotgun in slot 4. Checkpoint `0bd1329`
(`test: cubrir migracion de recompensa meta`) added that exact fixture.

Observed result before the v1 migration fix:

```text
ARSENAL_TEST failures=4
```

The failures proved that the save format was not versioned, the old slot-4
reward blocked the axe migration, the reward was not moved to slot 5, and the
selected slot was not remapped.

## Implementation

- `game/02_player/weapons/Hacha.tres` defines a real `TOOL` weapon with 30
  damage, 100-tree-HP-compatible chopping, and `can_chop_trees = true`.
- `game/02_player/weapons/Weapon.gd` adds `Weapon.Category.TOOL` without
  changing the existing enum values.
- `game/02_player/weapons/WeaponController.gd` keeps six loadout slots:
  machete/pistola/escopeta/fusil in 0..3, axe in 4, and the meta reward in 5.
  It resolves the axe template during save/load and versions the six-slot
  format. Legacy v1 five-slot saves move their old slot-4 meta reward to slot
  5, restore the mandatory axe in slot 4, and remap a selected old slot 4 to
  the new slot 5 without duplicating or losing either weapon.
- `game/02_player/Player.gd` raycasts the axe hit and emits the exact body RID
  and shape index; `game/07_house/Main.gd` forwards that identity to the forest.
- `game/11_forest/Forest.gd` keeps one logical record per procedural tree,
  rotates the existing MultiMesh instances around the tree base over 0.8 s,
  disables only the felled chunk shape with
  `PhysicsServer2D.body_set_shape_disabled`, and spawns one physical wood
  pickup worth 3 units. Its observable snapshot includes tree height and the
  live trunk/canopy transforms so tests verify the actual pivot, not only an
  internal animation flag.
- `game/04_items/Pickup.gd` and `Pickup.tscn` use only official inventory
  textures and display `FALTA ASSET - NO INVENTAR` when the PNG is absent.
  Partial inventory acceptance subtracts only the amount actually collected;
  the pickup remains in the world until its pending amount reaches zero.
- `game/16_meta/MetaProgress.gd` equips the extra shotgun only in slot 5 and
  announces it only after successful equipment.
- `game/08_ui/HUD.gd` and `InventoryMenu.gd` treat `TOOL` as melee, expose six
  slots, and no longer fabricate a generic weapon icon.
- `game/project.godot` maps the sixth quick-select slot to physical key 6.

## GREEN evidence

Focused commands:

```bash
godot --headless --path game res://10_review/TreeFellingTest.tscn --quit-after 1200
godot --headless --path game res://10_review/ArsenalTest.tscn --quit-after 1200
godot --headless --path game res://10_review/HeldItemVisualTest.tscn --quit-after 1200
godot --headless --path game res://10_review/TestFixes.tscn --quit-after 1200
```

Observed result before and after the review fixes:

```text
TREE_FELLING_TEST failures=0
ARSENAL_TEST failures=0
HELD_ITEM_VISUAL_TEST failures=0
HARD_GATE failures=0
```

Import and full local regression commands:

```bash
godot --headless --path game --import
bash /tmp/opencode/run_backfill_ci.sh
```

Observed result: import `rc=0`; `BACKFILL_CI_PASS suites=34 scripts=84`,
including `PLAY_SMOKE_COMPLETE` and `MECHANICS_READY 5/5`.

Specialist re-review after the partial-pickup and v1 migration fixes:
**APPROVE**, with no critical, high, or warning findings. The independent
`MIGRATION_AUDIT failures=0` confirmed exactly one axe in slot 4, exactly one
meta reward in slot 5, preserved reward state, and a lossless v2 round-trip.

## Test specification

| # | Guarantee | Test | Type | Result |
|---|---|---|---|---|
| 1 | The axe is a real TOOL resource that can chop trees | `TreeFellingTest.gd` | integration | PASS |
| 2 | A physical tree hit reaches the forest through the real player raycast | `TreeFellingTest.gd` | integration | PASS |
| 3 | Tree identity is exact `(body RID, shape index)` | `TreeFellingTest.gd` | integration | PASS |
| 4 | The felled tree rotates around its base to horizontal | `TreeFellingTest.gd` | integration | PASS |
| 5 | Only the felled shape stops blocking; another tree in the same chunk remains solid | `TreeFellingTest.gd` | integration | PASS |
| 6 | MultiMesh node/instance counts and chunk-body counts remain stable | `TreeFellingTest.gd` | regression | PASS |
| 7 | One physical wood pickup worth 3 units is created and collected | `TreeFellingTest.gd` | integration | PASS |
| 8 | Missing axe/wood artwork is labelled, never fabricated | `TreeFellingTest.gd`, `HeldItemVisualTest.gd` | regression | PASS |
| 9 | The machete cannot fell trees | `TreeFellingTest.gd` | regression | PASS |
| 10 | Six slots preserve base weapons, axe, and meta reward without replacement | `TreeFellingTest.gd`, `ArsenalTest.gd`, `TestFixes.gd` | regression | PASS |
| 11 | The axe follows the controller-level TOOL melee route | `TreeFellingTest.gd` | integration | PASS |
| 12 | The live trunk and canopy transforms prove a 90-degree rotation around the base | `TreeFellingTest.gd` | integration | PASS |
| 13 | A partially accepted pickup retains every uncollected unit | `TreeFellingTest.gd` | regression | PASS |
| 14 | Legacy v1 saves move the old slot-4 reward to slot 5, restore the axe in slot 4, and remap the selected slot | `ArsenalTest.gd` | regression | PASS |
| 15 | A populated meta slot survives a six-slot save/load round-trip | `ArsenalTest.gd` | regression | PASS |

## Coverage and known gaps

The dedicated headless suite exercises the real `Main`, `Player`,
`WeaponController`, `Forest`, MultiMesh, chunked physics bodies, inventory, UI,
and pickup path. It does not compare the fallen-tree frame against a golden
image. The pixel-art icon pack for `hacha.png` and `wood.png` is still absent;
the runtime therefore exercises the explicit missing-asset path rather than
claiming that final artwork exists.

## Merge evidence

RED checkpoints: `027cc63`, `204a984`, `1ed7967`, `0bd1329`. The GREEN checkpoint is the
point 10 implementation commit containing this report; it is reachable from
`main` immediately after the RED checkpoints and preserves all contracts above.
