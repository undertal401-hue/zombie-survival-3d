extends TileMap
class_name GroundTileMapV2

## =============================================================================
## GROUND TILEMAP V2 — base de terreno continua + detalle con arte de Lumina
## =============================================================================
## `ground_tiles.png` NO es una hoja de tiles sellados: son 100 trozos de
## terreno redondeados, separados por huecos transparentes y con diez tonos
## distintos por fila. Muestrear ese PNG con una rejilla (16x16 de 32 px o
## 10x10 de 48 px) cae siempre a medias sobre los huecos y produce el bug
## visual reportado: el suelo se ve como bloques y motas sobre negro.
##
## Estrategia:
##   1. El TileMap cubre el mundo con celdas opacas. El color lo pinta un shader
##      de base continua en espacio de mundo: mezcla los tonos medios reales del
##      atlas con ruido suave, sin rejilla ni parches por celda.
##   2. GroundDetailLayer reparte trozos reales del atlas (con su borde
##      redondeado) en manchas dispersas, de modo que aportan la textura pixel
##      art sin formar rejilla.
##
## El PNG original nunca se modifica.
## =============================================================================

const ATLAS_PATH: String = "res://assets/lumina_textures/ground_tiles.png"
const DETAIL_LAYER_SCRIPT: Script = preload("res://05_house/GroundDetailLayer.gd")
const BIOME_SHADER: Shader = preload("res://05_house/ground_biome.gdshader")
const CELL_SIZE: Vector2i = Vector2i(32, 32)

## Mitad del mundo jugable. Main.gd fija la cámara en +-6300.
const WORLD_HALF: int = 6300

## Bandas verticales medidas sobre el PNG original (asset congelado).
const SOURCE_BANDS: Array[Vector2i] = [
	Vector2i(19, 52),    # 0 pasto liso
	Vector2i(63, 98),    # 1 pasto con matas
	Vector2i(118, 145),  # 2 tierra con piedritas
	Vector2i(166, 193),  # 3 arena lisa
	Vector2i(214, 241),  # 4 losa clara
	Vector2i(260, 292),  # 5 piedra con musgo
	Vector2i(304, 339),  # 6 suelo de bosque con ramitas
]

## Índice de material = fila del atlas derivado.
const MATERIAL_GRASS: int = 0
const MATERIAL_GRASS_TUFT: int = 1
const MATERIAL_DIRT: int = 2
const MATERIAL_SAND: int = 3
const MATERIAL_STONE: int = 4
const MATERIAL_STONE_MOSS: int = 5
const MATERIAL_FOREST_FLOOR: int = 6
const MATERIAL_COUNT: int = 7

## Origen del color plano de cada material: (banda del atlas, columna).
## La banda elige la familia de terreno; la columna, el tono. GRASS_TUFT toma
## el color del pasto liso (banda 0) pero sus trozos de detalle salen de la
## banda 1, que es la que tiene matas.
const BASE_SOURCE: Array[Vector2i] = [
	Vector2i(0, 4),  # GRASS
	Vector2i(0, 4),  # GRASS_TUFT (color de pasto liso; detalle de banda 1)
	Vector2i(2, 4),  # DIRT
	Vector2i(3, 4),  # SAND
	Vector2i(4, 4),  # STONE
	Vector2i(5, 4),  # STONE_MOSS
	Vector2i(6, 4),  # FOREST_FLOOR
]

## Columnas del atlas cuyo color medio define los tonos claro y oscuro de la
## base continua. Se calculan en runtime sobre el PNG original.
const TONE_LIGHT_COLUMN: int = 3
const TONE_DARK_COLUMN: int = 7

## Capas del TileMap
const LAYER_GROUND: int = 0
const LAYER_OVERLAY: int = 1     # Reservada (compatibilidad)
const LAYER_DECORATION: int = 2  # Reservada (compatibilidad)

## Tipos de tile explícitos. `row` es la fila del atlas derivado.
const TILE_TYPES: Dictionary = {
	"GRASS": {"row": MATERIAL_GRASS, "nombre_visible": "Pasto", "transitable": true},
	"GRASS_TUFT": {"row": MATERIAL_GRASS_TUFT, "nombre_visible": "Pasto alto", "transitable": true},
	"DIRT": {"row": MATERIAL_DIRT, "nombre_visible": "Tierra", "transitable": true},
	"SAND": {"row": MATERIAL_SAND, "nombre_visible": "Arena", "transitable": true},
	"STONE": {"row": MATERIAL_STONE, "nombre_visible": "Losa", "transitable": true},
	"STONE_MOSS": {"row": MATERIAL_STONE_MOSS, "nombre_visible": "Piedra con musgo", "transitable": true},
	"FOREST_FLOOR": {"row": MATERIAL_FOREST_FLOOR, "nombre_visible": "Suelo de bosque", "transitable": true},
	# Alias de compatibilidad: los caminos ya los pinta el barrio/asfalto por
	# encima del suelo, pero la API histórica sigue aceptando estos nombres.
	"DIRT_GRASS": {"row": MATERIAL_GRASS_TUFT, "nombre_visible": "Pasto con tierra", "transitable": true},
	"ROAD_H": {"row": MATERIAL_STONE, "nombre_visible": "Camino horizontal", "transitable": true},
	"ROAD_V": {"row": MATERIAL_STONE, "nombre_visible": "Camino vertical", "transitable": true},
	"ROAD_CORNER_TL": {"row": MATERIAL_STONE, "nombre_visible": "Esquina TL", "transitable": true},
	"ROAD_CORNER_TR": {"row": MATERIAL_STONE, "nombre_visible": "Esquina TR", "transitable": true},
	"ROAD_CORNER_BL": {"row": MATERIAL_STONE, "nombre_visible": "Esquina BL", "transitable": true},
	"ROAD_CORNER_BR": {"row": MATERIAL_STONE, "nombre_visible": "Esquina BR", "transitable": true},
	"ROAD_T_UP": {"row": MATERIAL_STONE, "nombre_visible": "Cruce T arriba", "transitable": true},
	"ROAD_T_DOWN": {"row": MATERIAL_STONE, "nombre_visible": "Cruce T abajo", "transitable": true},
	"ROAD_T_LEFT": {"row": MATERIAL_STONE, "nombre_visible": "Cruce T izquierda", "transitable": true},
	"ROAD_T_RIGHT": {"row": MATERIAL_STONE, "nombre_visible": "Cruce T derecha", "transitable": true},
	"ROAD_CROSS": {"row": MATERIAL_STONE, "nombre_visible": "Cruce", "transitable": true},
	"GRASS_TO_DIRT": {"row": MATERIAL_GRASS_TUFT, "nombre_visible": "Transición pasto/tierra", "transitable": true},
	"DIRT_TO_STONE": {"row": MATERIAL_STONE_MOSS, "nombre_visible": "Transición tierra/losa", "transitable": true},
	"GRASS_TO_STONE": {"row": MATERIAL_STONE_MOSS, "nombre_visible": "Transición pasto/losa", "transitable": true},
}

## Material base por bioma. La base continua la pinta el shader; estas filas
## deciden los trozos de detalle y la API pública.
const BIOME_MATERIAL: Dictionary = {
	"forest": MATERIAL_FOREST_FLOOR,
	"urban": MATERIAL_STONE,
	"plains": MATERIAL_GRASS_TUFT,
	"mixed": MATERIAL_GRASS_TUFT,
}

## Mitades de los biomas (píxeles de mundo), iguales que en Forest.gd.
const URBAN_HALF: Vector2 = Vector2(2400.0, 1500.0)
const PLAINS_HALF: Vector2 = Vector2(3000.0, 2000.0)
## Jitter del borde de bioma para que no sea una línea recta.
const BIOME_EDGE_JITTER: float = 48.0

## Textura original (solo lectura) usada por la capa de detalle.
var atlas_texture: Texture2D = null
## Textura derivada plana que usa el TileSet (32 x MATERIAL_COUNT*32).
var derived_texture: ImageTexture = null
## Material del shader que pinta la base continua por bioma.
var biome_material: ShaderMaterial = null
## Regiones (bbox) de los diez trozos de cada material en el PNG original.
var chunk_regions: Array = []
## Último rectángulo de celdas pintado.
var painted_bounds: Rect2i = Rect2i()
## Capa de detalle con los trozos del atlas.
var detail_layer: Node2D = null

@onready var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	z_index = -8
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	_setup_tileset()
	_spawn_detail_layer()


# --- Construcción del tileset ------------------------------------------------

func _setup_tileset() -> void:
	atlas_texture = load(ATLAS_PATH) as Texture2D
	if atlas_texture == null:
		push_error("GroundTileMapV2: no se pudo cargar " + ATLAS_PATH)
		return
	var image: Image = atlas_texture.get_image()
	if image == null:
		push_error("GroundTileMapV2: " + ATLAS_PATH + " no tiene imagen")
		return
	image.convert(Image.FORMAT_RGBA8)

	var width: int = image.get_width()
	var height: int = image.get_height()
	var stride: int = width * 4
	var data: PackedByteArray = image.get_data()

	var bands: Array[Vector2i] = _measure_bands(data, width, height)
	if bands.size() < SOURCE_BANDS.size():
		bands = SOURCE_BANDS.duplicate()

	# La textura derivada solo lleva un color plano por material: el arte real
	# lo aportan los trozos de GroundDetailLayer. Así la base no tiene rejilla.
	derived_texture = _build_flat_texture(image, data, stride, bands)
	chunk_regions.clear()
	for material in range(MATERIAL_COUNT):
		var band: Vector2i = bands[material]
		var runs: Array[Vector2i] = _measure_runs(data, band, width)
		var regions: Array[Rect2] = []
		for run in runs:
			regions.append(Rect2(run.x, band.x, run.y - run.x + 1, band.y - band.x + 1))
		chunk_regions.append(regions)

	var tileset: TileSet = TileSet.new()
	tileset.tile_size = CELL_SIZE
	var source_id: int = tileset.add_source(TileSetAtlasSource.new())
	var source: TileSetAtlasSource = tileset.get_source(source_id) as TileSetAtlasSource
	source.texture = derived_texture
	source.texture_region_size = CELL_SIZE
	source.margins = Vector2i.ZERO
	source.separation = Vector2i.ZERO
	for row in range(MATERIAL_COUNT):
		source.create_tile(Vector2i(0, row))
	set_tileset(tileset)

	biome_material = _build_biome_material(image, data, stride, bands)
	material = biome_material


## Shader de base continua con los tonos medios reales del atlas.
func _build_biome_material(image: Image, data: PackedByteArray, stride: int,
		bands: Array[Vector2i]) -> ShaderMaterial:
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = BIOME_SHADER
	shader_material.set_shader_parameter("plains_light",
		_mean_of(bands, image, data, stride, 0, TONE_LIGHT_COLUMN))
	shader_material.set_shader_parameter("plains_dark",
		_mean_of(bands, image, data, stride, 0, TONE_DARK_COLUMN))
	shader_material.set_shader_parameter("urban_light",
		_mean_of(bands, image, data, stride, 4, TONE_LIGHT_COLUMN))
	shader_material.set_shader_parameter("urban_dark",
		_mean_of(bands, image, data, stride, 4, TONE_DARK_COLUMN))
	shader_material.set_shader_parameter("forest_light",
		_mean_of(bands, image, data, stride, 6, TONE_LIGHT_COLUMN))
	shader_material.set_shader_parameter("forest_dark",
		_mean_of(bands, image, data, stride, 6, TONE_DARK_COLUMN))
	shader_material.set_shader_parameter("urban_half", URBAN_HALF)
	shader_material.set_shader_parameter("plains_half", PLAINS_HALF)
	return shader_material


## Color medio opaco de una banda del atlas en la columna pedida.
func _mean_of(bands: Array[Vector2i], image: Image, data: PackedByteArray,
		stride: int, band_index: int, column: int) -> Color:
	var band: Vector2i = bands[clampi(band_index, 0, bands.size() - 1)]
	var runs: Array[Vector2i] = _measure_runs(data, band, image.get_width())
	var run: Vector2i = runs[clampi(column, 0, runs.size() - 1)]
	return _opaque_mean(image, data, stride, band, run)


## Base plana: un tile 32x32 por material con el color medio de su trozo
## central. Un solo color por material evita dameros y costuras.
func _build_flat_texture(image: Image, data: PackedByteArray, stride: int,
		bands: Array[Vector2i]) -> ImageTexture:
	var derived: Image = Image.create_empty(
		CELL_SIZE.x, MATERIAL_COUNT * CELL_SIZE.y, false, Image.FORMAT_RGBA8)
	derived.fill(Color(0, 0, 0, 0))

	for material in range(MATERIAL_COUNT):
		var source: Vector2i = BASE_SOURCE[material]
		var band: Vector2i = bands[source.x]
		var runs: Array[Vector2i] = _measure_runs(data, band, image.get_width())
		var run: Vector2i = runs[mini(source.y, runs.size() - 1)]
		var color: Color = _opaque_mean(image, data, stride, band, run)
		derived.fill_rect(
			Rect2i(0, material * CELL_SIZE.y, CELL_SIZE.x, CELL_SIZE.y), color)

	return ImageTexture.create_from_image(derived)


## Color medio de un cuadrado totalmente opaco centrado en el trozo.
func _opaque_mean(image: Image, data: PackedByteArray, stride: int,
		band: Vector2i, run: Vector2i) -> Color:
	var center := Vector2i((run.x + run.y) / 2, (band.x + band.y) / 2)
	var sizes: Array[int] = [16, 14, 12, 10, 8]
	for size in sizes:
		var rect := Rect2i(center - Vector2i(size / 2, size / 2), Vector2i(size, size))
		if rect.position.x < 0 or rect.position.y < 0:
			continue
		if rect.position.x + size > image.get_width() or rect.position.y + size > image.get_height():
			continue
		if not _region_opaque(data, stride, rect):
			continue
		var total := Color(0, 0, 0, 0)
		for y in range(rect.position.y, rect.position.y + size):
			for x in range(rect.position.x, rect.position.x + size):
				total += image.get_pixel(x, y)
		var count: float = float(size * size)
		return Color(total.r / count, total.g / count, total.b / count, 1.0)

	var fallback: Color = image.get_pixel(center.x, center.y)
	fallback.a = 1.0
	return fallback


func _row_occupied(data: PackedByteArray, width: int, y: int) -> bool:
	var base: int = y * width * 4
	for x in range(width):
		if data[base + x * 4 + 3] >= 16:
			return true
	return false


func _measure_bands(data: PackedByteArray, width: int, height: int) -> Array[Vector2i]:
	var bands: Array[Vector2i] = []
	var y: int = 0
	while y < height:
		if not _row_occupied(data, width, y):
			y += 1
			continue
		var start: int = y
		while y < height and _row_occupied(data, width, y):
			y += 1
		if y - start >= 8:
			bands.append(Vector2i(start, y - 1))
	return bands


func _column_occupied(data: PackedByteArray, width: int, band: Vector2i, x: int) -> bool:
	for y in range(band.x, band.y + 1):
		if data[(y * width + x) * 4 + 3] >= 16:
			return true
	return false


func _measure_runs(data: PackedByteArray, band: Vector2i, width: int) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	var x: int = 0
	while x < width:
		if not _column_occupied(data, width, band, x):
			x += 1
			continue
		var start: int = x
		while x < width and _column_occupied(data, width, band, x):
			x += 1
		runs.append(Vector2i(start, x - 1))
	if runs.is_empty():
		runs.append(Vector2i(0, width - 1))
	return runs


func _region_opaque(data: PackedByteArray, stride: int, rect: Rect2i) -> bool:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if data[y * stride + x * 4 + 3] < 250:
				return false
	return true


# --- Capa de detalle ---------------------------------------------------------

func _spawn_detail_layer() -> void:
	if detail_layer != null and is_instance_valid(detail_layer):
		return
	detail_layer = DETAIL_LAYER_SCRIPT.new() as Node2D
	detail_layer.name = "GroundDetail"
	detail_layer.ground = self
	add_child(detail_layer)


## Material de bioma en una posición de mundo (px).
func material_at_world(position: Vector2) -> int:
	return _material_for_cell(Vector2i(
		floori(position.x / float(CELL_SIZE.x)),
		floori(position.y / float(CELL_SIZE.y))))


## Regiones del atlas para un material (diez trozos).
func chunk_regions_for(material: int) -> Array:
	if material < 0 or material >= chunk_regions.size():
		return []
	return chunk_regions[material]


# --- Utilidades de muestreo --------------------------------------------------

func _cell_hash(x: int, y: int) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ 0x4C554D49
	h = h ^ (h >> 13)
	return h & 0x7FFFFFFF


## Material de una celda. El borde ondulado y la mezcla de tonos los resuelve el
## shader; aqui solo se decide a que bioma pertenece la celda para el detalle.
func _material_for_cell(cell: Vector2i) -> int:
	var world: Vector2 = Vector2(cell) * Vector2(CELL_SIZE)
	var jitter: float = float(_cell_hash(cell.x, cell.y) % 5 - 2) * (BIOME_EDGE_JITTER / 2.0)

	if absf(world.x) <= URBAN_HALF.x + jitter and absf(world.y) <= URBAN_HALF.y + jitter:
		return MATERIAL_STONE
	if absf(world.x) <= PLAINS_HALF.x + jitter and absf(world.y) <= PLAINS_HALF.y + jitter:
		return MATERIAL_GRASS_TUFT
	return MATERIAL_FOREST_FLOOR


func _coords_for_material(material: int) -> Vector2i:
	return Vector2i(0, material)


# --- API pública -------------------------------------------------------------

## Coloca un tile por nombre en la capa especificada.
func set_tile_by_name(cell: Vector2i, tile_name: String, layer: int = LAYER_GROUND) -> void:
	if not TILE_TYPES.has(tile_name):
		push_error("Tile type '%s' no existe" % tile_name)
		return
	set_cell(layer, cell, 0, _coords_for_material(int(TILE_TYPES[tile_name]["row"])))


## Coordenadas de atlas para un nombre de tile.
func get_tile_atlas_coords(tile_name: String) -> Vector2i:
	if not TILE_TYPES.has(tile_name):
		return Vector2i(-1, -1)
	return _coords_for_material(int(TILE_TYPES[tile_name]["row"]))


## Rellena un rectángulo con un material base.
func fill_rect(rect: Rect2i, tile_name: String, layer: int = LAYER_GROUND) -> void:
	if not TILE_TYPES.has(tile_name):
		return
	var coords: Vector2i = _coords_for_material(int(TILE_TYPES[tile_name]["row"]))
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			set_cell(layer, Vector2i(x, y), 0, coords)


## Dibuja una línea de camino entre dos puntos.
func draw_road(start: Vector2i, end: Vector2i, layer: int = LAYER_GROUND) -> void:
	var x0: int = start.x
	var y0: int = start.y
	var x1: int = end.x
	var y1: int = end.y
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy

	while true:
		set_tile_by_name(Vector2i(x0, y0), "ROAD_H", layer)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy


func generate_biome_area(bounds: Rect2i, biome: String) -> void:
	var material: int = int(BIOME_MATERIAL.get(biome, MATERIAL_GRASS))
	var coords: Vector2i = _coords_for_material(material)
	for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			set_cell(LAYER_GROUND, Vector2i(x, y), 0, coords)


## Compatibilidad con la API original.
func generate_ground(bounds: Rect2, biome: String = "mixed") -> void:
	generate_world_map(Rect2i(bounds.position, bounds.size))


## Genera el suelo de todo el mundo (o del rectángulo pedido, recortado).
func generate_world_map(bounds: Rect2i = Rect2i()) -> void:
	var world: Rect2i = _world_cell_bounds()
	var target: Rect2i = world
	if bounds.size.x > 0 and bounds.size.y > 0:
		target = _rect2i_intersection(world, bounds)
	painted_bounds = target
	clear()
	if get_tileset() == null:
		return

	for y in range(target.position.y, target.position.y + target.size.y):
		for x in range(target.position.x, target.position.x + target.size.x):
			var cell := Vector2i(x, y)
			set_cell(LAYER_GROUND, cell, 0, _coords_for_material(_material_for_cell(cell)))
	if detail_layer != null and is_instance_valid(detail_layer):
		detail_layer.call("queue_redraw")


func _world_cell_bounds() -> Rect2i:
	var min_cell := Vector2i(
		floori(-WORLD_HALF / float(CELL_SIZE.x)),
		floori(-WORLD_HALF / float(CELL_SIZE.y)))
	var max_cell := Vector2i(
		ceili(WORLD_HALF / float(CELL_SIZE.x)),
		ceili(WORLD_HALF / float(CELL_SIZE.y)))
	return Rect2i(min_cell, max_cell - min_cell)


func _rect2i_intersection(a: Rect2i, b: Rect2i) -> Rect2i:
	var min_x: int = maxi(a.position.x, b.position.x)
	var min_y: int = maxi(a.position.y, b.position.y)
	var max_x: int = mini(a.position.x + a.size.x, b.position.x + b.size.x)
	var max_y: int = mini(a.position.y + a.size.y, b.position.y + b.size.y)
	if min_x >= max_x or min_y >= max_y:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)


## Utilidades -----------------------------------------------------------------

func get_tile_at(cell: Vector2i, layer: int = LAYER_GROUND) -> Dictionary:
	var source_id: int = get_cell_source_id(layer, cell)
	if source_id == -1:
		return {}
	var coords: Vector2i = get_cell_atlas_coords(layer, cell)
	return {
		"source_id": source_id,
		"atlas_coords": coords,
		"row": coords.y,
	}


func is_walkable_at(cell: Vector2i, layer: int = LAYER_GROUND) -> bool:
	var tile_info: Dictionary = get_tile_at(cell, layer)
	if tile_info.is_empty():
		return false
	for tile_name in TILE_TYPES:
		if int(TILE_TYPES[tile_name]["row"]) == tile_info["row"]:
			return bool(TILE_TYPES[tile_name]["transitable"])
	return true


func get_random_variant(tile_name: String) -> Vector2i:
	if not TILE_TYPES.has(tile_name):
		return Vector2i(0, 0)
	return _coords_for_material(int(TILE_TYPES[tile_name]["row"]))


## Nombre legible del material de una fila (para QA/diagnóstico).
func material_name(material: int) -> String:
	for tile_name in TILE_TYPES:
		if int(TILE_TYPES[tile_name]["row"]) == material:
			return String(TILE_TYPES[tile_name]["nombre_visible"])
	return "material_%d" % material
