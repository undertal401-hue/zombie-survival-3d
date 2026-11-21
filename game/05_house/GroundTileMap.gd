extends TileMap
class_name GroundTileMap

## =============================================================================
## GROUND TILEMAP - Suelo pixel art con texturas de Lumina
## =============================================================================

@export var tile_size: Vector2i = Vector2i(32, 32)
@export var world_width: int = 4800
@export var world_height: int = 3000
@export var decoration_density: float = 0.05  # 0.0 a 1.0

func _ready() -> void:
	var tileset: TileSet = load("res://assets/lumina_textures/lumina_ground_tileset.tres")
	if tileset == null:
		push_error("GroundTileMap: no se pudo cargar el tileset de Lumina")
		return
	set_tileset(tileset)
	set_cell(0, Vector2i(0, 0), 0, Vector2i())
	set_cell(0, Vector2i(1, 0), 1, Vector2i())
	set_cell(0, Vector2i(0, 1), 2, Vector2i())
	set_cell(0, Vector2i(1, 1), 3, Vector2i())

func generate_ground(bounds: Rect2, biome: String = "forest") -> void:
	# Se usa el TileSet de Lumina; se mantiene para compatibilidad
	_ready()

func set_biome_at(position: Vector2, biome: String) -> void:
	pass
