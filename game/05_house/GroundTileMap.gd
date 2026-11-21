extends TileMap
class_name GroundTileMap

## =============================================================================
## GROUND TILEMAP - suelo pixel art con los atlas originales de Lumina
## =============================================================================
## ground_tiles.png no es una rejilla 16x16 de 32 px: contiene 10x10 piezas
## con paso de 48 px. La imagen de 512 px incluye margen y el arte no ocupa
## todo el PNG. Este nodo conserva los PNG sin modificarlos y los proyecta
## como una capa de parches sobre las bases planas ya existentes.
##
## decoration_tiles.png contiene cinco sprites individuales (dos arboles y tres
## arbustos), no una rejilla 16x16. Se recorta mediante AtlasTexture para no
## inventar arte ni alterar los originales.

const GROUND_TEXTURE_PATH: String = "res://assets/lumina_textures/ground_tiles.png"
const DECORATION_TEXTURE_PATH: String = "res://assets/lumina_textures/decoration_tiles.png"
const ATLAS_CELL_SIZE: Vector2i = Vector2i(48, 48)
const ATLAS_COLUMNS: int = 10
const ATLAS_ROWS: int = 10

## Frecuencia de parches de suelo sobre la base procedural. La base sigue
## garantizando que el mundo no tenga huecos negros entre las piezas irregulares.
@export_range(0.05, 1.0, 0.05) var ground_patch_density: float = 0.68
## Cantidad de sprites decorativos adicionales colocados sobre el mundo.
@export_range(0, 64, 1) var decoration_count: int = 28

const GRASS_ROWS: Array[int] = [0, 1, 6, 7, 8]
const EARTH_ROWS: Array[int] = [2, 3]
const STONE_ROWS: Array[int] = [4, 5]
const FOREST_ROWS: Array[int] = [8, 9]

## Regiones exactas de los cinco sprites reales de decoration_tiles.png.
## Los rectangulos incluyen solo los pixeles opacos de cada componente.
const DECORATION_REGIONS: Array[Rect2] = [
	Rect2(28, 42, 65, 77),    # arbol bajo
	Rect2(111, 41, 84, 150),  # arbol alto
	Rect2(238, 47, 81, 52),   # arbusto oscuro grande
	Rect2(337, 41, 73, 60),   # arbusto oscuro pequeno
	Rect2(422, 39, 53, 60),   # arbusto redondeado
]

var _tile_set: TileSet
var _ground_source_id: int = -1
var _decoration_layer: Node2D


func _ready() -> void:
	# El plano base del bosque/pueblo sigue en z=-10 y los parches urbanos en
	# z=-9. Esta capa queda en z=-8: encima de esas bases, pero debajo de
	# caminos, calzadas, claros y casas, que conservan su geometria original.
	z_index = -8
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_tile_set()


func generate_ground(bounds: Rect2, biome: String = "mixed") -> void:
	_ensure_tile_set()
	if _tile_set == null or _ground_source_id < 0:
		return

	clear()
	_paint_ground_patches(bounds, biome)
	_rebuild_decorations(bounds)


func set_biome_at(position: Vector2, biome: String) -> void:
	# API historica: una bioma concreta puede recolocar solo esa celda.
	if _ground_source_id < 0:
		_ensure_tile_set()
	if _ground_source_id < 0:
		return
	var cell := Vector2i(
		int(floor(position.x / float(ATLAS_CELL_SIZE.x))),
		int(floor(position.y / float(ATLAS_CELL_SIZE.y)))
	)
	set_cell(0, cell, _ground_source_id, _pick_atlas_coords(cell, biome, _rng_for(cell)))


## Crea el TileSet en runtime porque las hojas originales se deben conservar
## intactas. La region 48x48 corresponde al paso real de los 10x10 sprites.
func _ensure_tile_set() -> void:
	if _tile_set != null:
		return

	var ground_texture := load(GROUND_TEXTURE_PATH) as Texture2D
	if ground_texture == null:
		push_error("GroundTileMap: no se pudo cargar ground_tiles.png")
		return

	_tile_set = TileSet.new()
	_tile_set.tile_size = ATLAS_CELL_SIZE
	_ground_source_id = _tile_set.add_source(TileSetAtlasSource.new())
	var ground_source := _tile_set.get_source(_ground_source_id) as TileSetAtlasSource
	ground_source.texture = ground_texture
	ground_source.texture_region_size = ATLAS_CELL_SIZE
	for row in range(ATLAS_ROWS):
		for column in range(ATLAS_COLUMNS):
			ground_source.create_tile(Vector2i(column, row))
	set_tileset(_tile_set)


func _paint_ground_patches(bounds: Rect2, biome: String) -> void:
	var min_cell := Vector2i(
		int(floor(bounds.position.x / float(ATLAS_CELL_SIZE.x))),
		int(floor(bounds.position.y / float(ATLAS_CELL_SIZE.y)))
	)
	var max_cell := Vector2i(
		int(floor(bounds.end.x / float(ATLAS_CELL_SIZE.x))),
		int(floor(bounds.end.y / float(ATLAS_CELL_SIZE.y)))
	)

	for cell_y in range(min_cell.y, max_cell.y + 1):
		for cell_x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(cell_x, cell_y)
			var rng := _rng_for(cell)
			if rng.randf() > ground_patch_density:
				continue
			set_cell(0, cell, _ground_source_id, _pick_atlas_coords(cell, biome, rng))


func _pick_atlas_coords(cell: Vector2i, biome: String, rng: RandomNumberGenerator) -> Vector2i:
	var column := rng.randi_range(0, ATLAS_COLUMNS - 1)
	var row: int

	if biome == "forest":
		row = _pick_weighted_row(rng, GRASS_ROWS, EARTH_ROWS, STONE_ROWS)
	elif biome == "urban":
		row = _pick_weighted_row(rng, EARTH_ROWS, STONE_ROWS, GRASS_ROWS)
	else:
		# El atlas mezcla zonas. Fuera del pueblo predomina la vegetacion;
		# dentro se alternan tierra, piedra y algo de vegetacion.
		var world_x := float(cell.x * ATLAS_CELL_SIZE.x)
		var world_y := float(cell.y * ATLAS_CELL_SIZE.y)
		var in_town: bool = absf(world_x) <= 2400.0 and absf(world_y) <= 1500.0
		if in_town:
			row = _pick_weighted_row(rng, EARTH_ROWS, STONE_ROWS, GRASS_ROWS)
		else:
			row = _pick_weighted_row(rng, GRASS_ROWS, EARTH_ROWS, FOREST_ROWS)
	return Vector2i(column, row)


func _pick_weighted_row(rng: RandomNumberGenerator, primary: Array[int],
		secondary: Array[int], tertiary: Array[int]) -> int:
	var roll := rng.randf()
	var pool: Array[int]
	if roll < 0.58:
		pool = primary
	elif roll < 0.86:
		pool = secondary
	else:
		pool = tertiary
	return pool[rng.randi_range(0, pool.size() - 1)]


func _rng_for(cell: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (cell.x * 73856093) ^ (cell.y * 19349663) ^ 0x4C554D49
	return rng


func _rebuild_decorations(bounds: Rect2) -> void:
	if _decoration_layer == null:
		_decoration_layer = Node2D.new()
		_decoration_layer.name = "LuminaDecorations"
		_decoration_layer.z_index = 0
		_decoration_layer.z_as_relative = true
		add_child(_decoration_layer)
	else:
		for child in _decoration_layer.get_children():
			_decoration_layer.remove_child(child)
			child.free()

	var decoration_texture := load(DECORATION_TEXTURE_PATH) as Texture2D
	if decoration_texture == null:
		push_error("GroundTileMap: no se pudo cargar decoration_tiles.png")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x4C554D494E413129

	# Un grupo pequeno y fijo cerca del inicio hace que la decoracion sea
	# visible desde el primer frame, sin esperar a explorar el bosque.
	var start_anchors: Array[Vector2] = [
		Vector2(-2260, 1130),
		Vector2(-2010, 1360),
		Vector2(-1850, 1120),
		Vector2(-2420, 760),
		Vector2(-1700, 1320),
	]
	for index in range(start_anchors.size()):
		_add_decoration_sprite(decoration_texture, index % DECORATION_REGIONS.size(),
			start_anchors[index], rng)

	# El resto se distribuye por el mapa visible, no solo por el pueblo.
	for index in range(decoration_count):
		var position := Vector2(
			rng.randf_range(bounds.position.x + 120.0, bounds.end.x - 120.0),
			rng.randf_range(bounds.position.y + 120.0, bounds.end.y - 120.0)
		)
		_add_decoration_sprite(decoration_texture, rng.randi_range(0, DECORATION_REGIONS.size() - 1),
			position, rng)


func _add_decoration_sprite(atlas_texture: Texture2D, region_index: int,
		position: Vector2, rng: RandomNumberGenerator) -> void:
	var region: Rect2 = DECORATION_REGIONS[region_index]
	var atlas := AtlasTexture.new()
	atlas.atlas = atlas_texture
	atlas.region = region

	var sprite := Sprite2D.new()
	sprite.name = "LuminaDecoration%d" % _decoration_layer.get_child_count()
	sprite.texture = atlas
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = position
	sprite.offset = Vector2(0.0, -region.size.y * 0.5)
	sprite.flip_h = rng.randf() < 0.5
	_decoration_layer.add_child(sprite)
