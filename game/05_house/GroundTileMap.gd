extends TileMap
class_name GroundTileMap

## =============================================================================
## GROUND TILEMAP - Suelo pixel art con texturas de Lumina
## =============================================================================

@export var tile_size: Vector2i = Vector2i(32, 32)
@export var world_width: int = 4800
@export var world_height: int = 3000
@export var decoration_density: float = 0.05

var tileset: TileSet

func _ready() -> void:
	tileset = TileSet.new()
	
	# Crear fuente 0: ground_tiles
	var source_ground: TileSetAtlasSource = TileSetAtlasSource.new()
	var ground_tex: Texture2D = load("res://assets/lumina_textures/ground_tiles.png")
	if ground_tex == null:
		push_error("GroundTileMap: no se pudo cargar ground_tiles.png")
		return
	source_ground.texture = ground_tex
	source_ground.texture_region_size = tile_size
	var ground_id: int = tileset.add_source(source_ground)
	
	# Crear fuente 1: decoration_tiles
	var source_decoration: TileSetAtlasSource = TileSetAtlasSource.new()
	var dec_tex: Texture2D = load("res://assets/lumina_textures/decoration_tiles.png")
	if dec_tex == null:
		push_error("GroundTileMap: no se pudo cargar decoration_tiles.png")
		return
	source_decoration.texture = dec_tex
	source_decoration.texture_region_size = tile_size
	var decoration_id: int = tileset.add_source(source_decoration)
	
	if ground_id < 0 or decoration_id < 0:
		push_error("GroundTileMap: no se pudieron crear las fuentes de tiles")
		return
	
	set_tileset(tileset)
	# Configurar tile_size en el TileMap para que sepa el tamaño de cada celda
	tile_size = tileset.get_source(ground_id).texture_region_size
	_paint_ground(ground_id, decoration_id)
	
	# Depuración
	var ts: TileSet = get_tileset()
	print("GroundTileMap: ground_id=", ground_id, "decoration_id=", decoration_id)
	print("GroundTileMap: ground_tex=", ground_tex, "dec_tex=", dec_tex)

func _paint_ground(ground_source_id: int, decoration_source_id: int) -> void:
	var ts: TileSet = get_tileset()
	var cols: int = 16
	var rows: int = 16
	for y in range(rows):
		for x in range(cols):
			ts.get_source(ground_source_id).create_tile(Vector2i(x, y))

	# Crear todos los tiles de decoration_tiles en la fuente 1
	for y in range(rows):
		for x in range(cols):
			ts.get_source(decoration_source_id).create_tile(Vector2i(x, y))

	# Pintar el suelo base con tile (0,0) de ground en cada celda
	var start_x: int = -world_width / 2
	var start_y: int = -world_height / 2
	var end_x: int = world_width / 2
	var end_y: int = world_height / 2

	for y in range(start_y, end_y, tile_size.y):
		for x in range(start_x, end_x, tile_size.x):
			var cell: Vector2i = Vector2i(x / tile_size.x, y / tile_size.y)
			set_cell(0, cell, ground_source_id, Vector2i(0, 0))

	# Agregar decoración aleatoriamente
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var cell_count: int = ((world_width / tile_size.x) * (world_height / tile_size.y))
	var decoration_count: int = cell_count * decoration_density
	for i in range(decoration_count):
		var dx: int = rng.randi_range(start_x, end_x - tile_size.x)
		var dy: int = rng.randi_range(start_y, end_y - tile_size.y)
		var cell: Vector2i = Vector2i(dx / tile_size.x, dy / tile_size.y)
		var tx: int = rng.randi_range(0, cols - 1)
		var ty: int = rng.randi_range(0, rows - 1)
		set_cell(0, cell, decoration_source_id, Vector2i(tx, ty))

func generate_ground(bounds: Rect2, biome: String = "forest") -> void:
	_ready()

func set_biome_at(position: Vector2, biome: String) -> void:
	pass
