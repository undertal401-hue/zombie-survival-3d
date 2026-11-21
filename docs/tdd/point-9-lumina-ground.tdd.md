# TDD evidence — FASE 1, punto 9: suelo Lumina visible

## Source plan

No external plan file was supplied. The acceptance criteria were derived from the
roadmap requirement: the user-supplied `ground_tiles.png` and
`decoration_tiles.png` must visibly render as pixel art in the game, without
replacing or modifying the original artwork.

## User journeys

1. As a player, I can see the supplied Lumina ground artwork over the procedural
   ground from the first playable frame.
2. As a player, I can see the supplied Lumina tree/bush decoration artwork in the
   starting area and elsewhere in the world.
3. As a maintainer, the game contains one authoritative ground layer that cannot
   be hidden by the legacy flat forest/town base rectangles.

## RED evidence

Checkpoint commit: `a1e960a` (`test: reproducir suelo Lumina invisible`).

Command:

```bash
cd /home/unde/zombie-survival-3d/game
godot --headless --path . res://10_review/LuminaGroundTest.tscn --quit-after 700
```

Observed result: exit code `1`, `LUMINA_GROUND_TEST failures=7`. The intended
failures proved that the atlas was parsed as 32 px instead of its real 48 px
pitch, the ground was still at `z=-10` beneath the flat bases, two
`GroundTileMap` instances existed, and no visible decoration layer existed.

A second RED gate was added after an independent read-only review found that
the first candidate could still select nonexistent atlas rows. The strengthened
test reported `invalidas=5599` and exit code `1`; the production fix restricted
every selection to the real 10×10 atlas and the same test then reported
`invalidas=0`.

## Implementation

- `game/05_house/GroundTileMap.gd` builds a runtime `TileSet` with a 48×48
  atlas region and paints deterministic mixed-biome ground patches.
- `game/05_house/GroundTileMap.gd` creates `LuminaDecorations` and uses
  `AtlasTexture` regions for the five real sprites in `decoration_tiles.png`.
- `game/05_house/Neighborhood.gd` no longer creates a second ground atlas.
- `game/07_house/Main.gd` and `Main.tscn` configure the single global layer over
  the full 12,600×12,600 world and place it above the legacy bases but below
  roads, clearings, and houses.
- `game/10_review/LuminaGroundTest.gd` is a real headless regression gate and
  is included in `.github/workflows/ci.yml`.

The authoritative PNGs remain unchanged. Their SHA-256 values are:

- `ground_tiles.png`: `10b6e81c16f0091f61172497cc191b8cfa8d581ceff92529c851594e6c8ebfd2`
- `decoration_tiles.png`: `0a1452693abc5b11152620fd7adb8a418dcbf08a6f9978fa480ea7b09e5325c4`

## GREEN evidence

Command:

```bash
cd /home/unde/zombie-survival-3d/game
godot --headless --path . res://10_review/LuminaGroundTest.tscn --quit-after 700
```

Observed result: exit code `0`, `LUMINA_GROUND_TEST failures=0`, 33 visible
decoration sprites covering all five supplied regions, one ground instance and
one atlas source, 47,680 valid painted cells across the full ±6,300 world,
48×48 atlas regions, and ground layer `z=-8` above both flat bases but below
forest clearings and paths. A second generation produced the same 47,680 cells
and 33 sprites, proving idempotence.

Additional verification:

```text
godot --headless --path . --quit-after 1200                 # exit 0
VisualStyleTest                                               # failures=0
CodeIntegrityTest                                             # failures=0 checked=79
TestFixes                                                    # HARD_GATE failures=0
QA_MODE=mechanics                                            # MECHANICS_READY 5/5
QA_MODE=smoke                                                # PLAY_SMOKE_COMPLETE
29/29 local CI regression suites                            # all pass
```

A real Vulkan render was captured with Godot Movie Maker after calling
`Main.skip_menu()`. The resulting gameplay frame visibly contains the Lumina
grass/dirt patches and a tall tree sprite near the starting area.

## Test specification

| # | Guarantee | Test | Type | Result |
|---|---|---|---|---|
| 1 | Both mandatory PNGs exist and load as 512×512 textures | `LuminaGroundTest.gd` | integration | PASS |
| 2 | The ground uses the real 48×48 atlas pitch and all 100 pieces exist | `LuminaGroundTest.gd` | integration | PASS |
| 3 | Every painted cell uses an existing 10×10 atlas coordinate | `LuminaGroundTest.gd` | integration | PASS |
| 4 | The ground spans the full ±6,300 world | `LuminaGroundTest.gd` | integration | PASS |
| 5 | The ground is above legacy flat bases and below clearings/paths | `LuminaGroundTest.gd` | integration | PASS |
| 6 | Exactly one authoritative `GroundTileMap` and atlas source exist | `LuminaGroundTest.gd` | integration | PASS |
| 7 | All five supplied decoration regions are visible | `LuminaGroundTest.gd` | integration | PASS |
| 8 | Regeneration is idempotent for cells and decorations | `LuminaGroundTest.gd` | integration | PASS |
| 9 | The artwork is visible in an actual rendered frame | Godot Movie Maker capture | visual | PASS |

## Coverage and known gaps

The dedicated headless suite covers the runtime loading, atlas geometry, layer
ordering, uniqueness, painting, and decoration visibility. It does not compare
the viewport against a golden image; the visual proof is the real Vulkan frame
described above. The supplied PNG hashes remain the source-level art-integrity
check.
