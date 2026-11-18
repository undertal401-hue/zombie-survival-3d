extends TileMap
class_name GroundTileMap

## =============================================================================
## GROUND TILEMAP - Suelo procedural simple (fallback para compatibilidad)
## =============================================================================

@export var biome_noise: FastNoiseLite

var _biomes: Dictionary = {
	"forest": { "tiles": [0, 1, 2], "weights": [0.5, 0.3, 0.2] },
	"urban": { "tiles": [3, 4, 5], "weights": [0.4, 0.4, 0.2] },
	"industrial": { "tiles": [6, 7], "weights": [0.6, 0.4] },
	"park": { "tiles": [8, 9], "weights": [0.7, 0.3] }
}

func _ready() -> void:
	# No inicializar TileSet complejo por ahora - usar ColorRect del Main
	# Este nodo existe para API futura
	pass

func generate_ground(bounds: Rect2, biome: String = "forest") -> void:
	# Placeholder - el suelo real se renderiza via ColorRect en Main.tscn
	pass

func _pick_weighted_tile(tiles: Array, weights: Array, noise: float) -> int:
	var total: float = 0.0
	for w in weights:
		total += w
	var r: float = (noise + 1.0) * 0.5 * total
	var acc: float = 0.0
	for i in range(tiles.size()):
		acc += weights[i]
		if r <= acc:
			return tiles[i]
	return tiles[0]

func _add_street_details(bounds: Rect2) -> void:
	pass

func set_biome_at(position: Vector2, biome: String) -> void:
	pass

func _blend_biome(center: Vector2i, biome: String) -> void:
	pass