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
	_paint_ground()

func _paint_ground() -> void:
	var start_x: int = -world_width / 2
	var start_y: int = -world_height / 2
	var end_x: int = world_width / 2
	var end_y: int = world_height / 2

	# IDs de textura en el tileset: 0 = ground_tiles, 1 = decoration_tiles
	var ground_atlas_id: int = 0
	var decoration_atlas_id: int = 1

	# Pintar el suelo base con tile (0,0) de ground_tiles en cada celda
	for y in range(start_y, end_y, tile_size.y):
		for x in range(start_x, end_x, tile_size.x):
			var cell: Vector2i = Vector2i(x / tile_size.x, y / tile_size.y)
			set_cell(0, cell, 0, Vector2i(ground_atlas_id, 0))

	# Agregar decoración aleatoriamente sobre el suelo
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var cols: int = 16  # 512 / 32
	var rows: int = 16  # 512 / 32
	var cell_count: int = ((world_width / tile_size.x) * (world_height / tile_size.y))
	var decoration_count: int = cell_count * decoration_density
	for i in range(decoration_count):
		var dx: int = rng.randi_range(start_x, end_x - tile_size.x)
		var dy: int = rng.randi_range(start_y, end_y - tile_size.y)
		var cell: Vector2i = Vector2i(dx / tile_size.x, dy / tile_size.y)
		var tx: int = rng.randi_range(0, cols - 1)
		var ty: int = rng.randi_range(0, rows - 1)
		set_cell(0, cell, ty * cols + tx, Vector2i(decoration_atlas_id, 0))

func generate_ground(bounds: Rect2, biome: String = "forest") -> void:
	# Se usa el TileSet de Lumina; se mantiene para compatibilidad
	_ready()

func set_biome_at(position: Vector2, biome: String) -> void:
	pass
