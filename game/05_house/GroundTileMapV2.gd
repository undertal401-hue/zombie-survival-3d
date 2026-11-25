extends TileMap
class_name GroundTileMapV2

## =============================================================================
## GROUND TILEMAP V2 - Sistema de tiles explícito tipo Minecraft/Terraria
## =============================================================================
## Basado en GroundTileMap original (funciona) + API V2 con nombres de tile.
## Usa ground_tiles.png (512x512) como atlas 10x10 de 48x48.
## Crea la cuadrícula completa 10x10 (100 tiles) como el original.
## Tipos: ROAD, DIRT, GRASS, DIRT_GRASS, STONE, FOREST_FLOOR, WATER, SAND
## =============================================================================

const ATLAS_PATH: String = "res://assets/lumina_textures/ground_tiles.png"
const ATLAS_CELL_SIZE: Vector2i = Vector2i(48, 48)
const ATLAS_COLUMNS: int = 10
const ATLAS_ROWS: int = 10

## Capas del TileMap
const LAYER_GROUND: int = 0      # Suelo base
const LAYER_OVERLAY: int = 1     # Transiciones (hierba sobre tierra, etc.)
const LAYER_DECORATION: int = 2  # Decoración (flores, rocas, etc.)

## Tipos de tile explícitos con sus coordenadas en el atlas 10x10
## Formato: { "nombre": { "atlas_coords": Vector2i(col, row), "nombre_visible": String, "transitable": bool, "variants": Array[Vector2i] } }
const TILE_TYPES: Dictionary = {
	# Suelos base
	"DIRT": {
		"atlas_coords": Vector2i(0, 2),
		"nombre_visible": "Tierra",
		"transitable": true,
		"variants": [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
	},
	"GRASS": {
		"atlas_coords": Vector2i(0, 0),
		"nombre_visible": "Pasto",
		"transitable": true,
		"variants": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	},
	"DIRT_GRASS": {
		"atlas_coords": Vector2i(4, 0),
		"nombre_visible": "Tierra con pasto",
		"transitable": true,
		"variants": [Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1)]
	},
	"STONE": {
		"atlas_coords": Vector2i(0, 4),
		"nombre_visible": "Piedra",
		"transitable": true,
		"variants": [Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5)]
	},
	"FOREST_FLOOR": {
		"atlas_coords": Vector2i(0, 8),
		"nombre_visible": "Suelo de bosque",
		"transitable": true,
		"variants": [Vector2i(1, 8), Vector2i(2, 8), Vector2i(3, 8), Vector2i(0, 9), Vector2i(1, 9), Vector2i(2, 9), Vector2i(3, 9)]
	},
	
	# Carretera / caminos
	"ROAD_H": {
		"atlas_coords": Vector2i(8, 2),
		"nombre_visible": "Carretera horizontal",
		"transitable": true
	},
	"ROAD_V": {
		"atlas_coords": Vector2i(9, 2),
		"nombre_visible": "Carretera vertical",
		"transitable": true
	},
	"ROAD_CORNER_TL": {
		"atlas_coords": Vector2i(8, 3),
		"nombre_visible": "Esquina carretera TL",
		"transitable": true
	},
	"ROAD_CORNER_TR": {
		"atlas_coords": Vector2i(9, 3),
		"nombre_visible": "Esquina carretera TR",
		"transitable": true
	},
	"ROAD_CORNER_BL": {
		"atlas_coords": Vector2i(8, 4),
		"nombre_visible": "Esquina carretera BL",
		"transitable": true
	},
	"ROAD_CORNER_BR": {
		"atlas_coords": Vector2i(9, 4),
		"nombre_visible": "Esquina carretera BR",
		"transitable": true
	},
	"ROAD_T_UP": {
		"atlas_coords": Vector2i(8, 5),
		"nombre_visible": "Carretera T arriba",
		"transitable": true
	},
	"ROAD_T_DOWN": {
		"atlas_coords": Vector2i(9, 5),
		"nombre_visible": "Carretera T abajo",
		"transitable": true
	},
	"ROAD_T_LEFT": {
		"atlas_coords": Vector2i(8, 6),
		"nombre_visible": "Carretera T izquierda",
		"transitable": true
	},
	"ROAD_T_RIGHT": {
		"atlas_coords": Vector2i(9, 6),
		"nombre_visible": "Carretera T derecha",
		"transitable": true
	},
	"ROAD_CROSS": {
		"atlas_coords": Vector2i(8, 7),
		"nombre_visible": "Cruce carretera",
		"transitable": true
	},
	
	# Transiciones (overlay layer)
	"GRASS_TO_DIRT": {
		"atlas_coords": Vector2i(4, 2),
		"nombre_visible": "Pasto a tierra",
		"transitable": true
	},
	"DIRT_TO_STONE": {
		"atlas_coords": Vector2i(5, 2),
		"nombre_visible": "Tierra a piedra",
		"transitable": true
	},
	"GRASS_TO_STONE": {
		"atlas_coords": Vector2i(6, 2),
		"nombre_visible": "Pasto a piedra",
		"transitable": true
	},
	
	# Agua
	"WATER": {
		"atlas_coords": Vector2i(4, 8),
		"nombre_visible": "Agua",
		"transitable": false
	},
	"WATER_SHORE": {
		"atlas_coords": Vector2i(5, 8),
		"nombre_visible": "Orilla",
		"transitable": true
	},
	
	# Arena
	"SAND": {
		"atlas_coords": Vector2i(6, 8),
		"nombre_visible": "Arena",
		"transitable": true
	},
}

## Mapa de bioma a tile base
const BIOME_BASE_TILE: Dictionary = {
	"forest": "FOREST_FLOOR",
	"urban": "DIRT",
	"plains": "GRASS",
	"roads": "DIRT",
	"mixed": "DIRT_GRASS"
}

## Vecindad para autotiling (4 direcciones)
const NEIGHBORS_4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const NEIGHBORS_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
]

@onready var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	z_index = -8
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_setup_tileset()
	_rng.randomize()

func _setup_tileset() -> void:
	var texture: Texture2D = load(ATLAS_PATH)
	if texture == null:
		push_error("GroundTileMapV2: no se pudo cargar " + ATLAS_PATH)
		return
	
	var tileset: TileSet = TileSet.new()
	tileset.tile_size = ATLAS_CELL_SIZE
	
	var source_id: int = tileset.add_source(TileSetAtlasSource.new())
	var source: TileSetAtlasSource = tileset.get_source(source_id) as TileSetAtlasSource
	source.texture = load(ATLAS_PATH)
	source.texture_region_size = ATLAS_CELL_SIZE
	source.margins = Vector2i(0, 0)
	source.separation = Vector2i(0, 0)
	
	# Crear todos los tiles del atlas 10x10 (igual que el original)
	for row in range(ATLAS_ROWS):
		for column in range(ATLAS_COLUMNS):
			source.create_tile(Vector2i(column, row))
	
	set_tileset(tileset)

## Compatibilidad con API original: generate_ground
func generate_ground(bounds: Rect2, biome: String = "mixed") -> void:
	generate_world_map(Rect2i(bounds.position, bounds.size))


## API pública ---------------------------------------------------------------

## Coloca un tile por nombre en la capa especificada
func set_tile_by_name(position: Vector2i, tile_name: String, layer: int = LAYER_GROUND) -> void:
	if not TILE_TYPES.has(tile_name):
		push_error("Tile type '%s' no existe" % tile_name)
		return
	
	var tile_data: Dictionary = TILE_TYPES[tile_name]
	var coords: Vector2i = tile_data["atlas_coords"]
	var source_id: int = 0
	
	set_cell(layer, position, source_id, coords)

## Obtiene las coordenadas del atlas para un nombre de tile
func _get_tile_atlas_coords(tile_name: String) -> Vector2i:
	if not TILE_TYPES.has(tile_name):
		return Vector2i(-1, -1)
	
	return TILE_TYPES[tile_name]["atlas_coords"]

## Rellena un rectángulo con un tile base
func fill_rect(rect: Rect2i, tile_name: String, layer: int = LAYER_GROUND) -> void:
	if not TILE_TYPES.has(tile_name):
		return
	
	var min_x: int = rect.position.x
	var max_x: int = rect.position.x + rect.size.x - 1
	var min_y: int = rect.position.y
	var max_y: int = rect.position.y + rect.size.y - 1
	
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			set_tile_by_name(Vector2i(x, y), tile_name, layer)

## Dibuja una línea (carretera) entre dos puntos
func draw_road(start: Vector2i, end: Vector2i, layer: int = LAYER_GROUND) -> void:
	var x0: int = start.x
	var y0: int = start.y
	var x1: int = end.x
	var y1: int = end.y
	
	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	
	while true:
		var tile_name: String = _get_road_tile(x0, y0, x1, y1, x0, y0, err, dx, dy, sx, sy)
		set_tile_by_name(Vector2i(x0, y0), tile_name, layer)
		
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy

func _get_road_tile(x: int, y: int, x1: int, y1: int, x0: int, y0: int, err: int, dx: int, dy: int, sx: int, sy: int) -> String:
	var next_x: int = x + sx
	var next_y: int = y + sy
	var prev_x: int = x - sx
	var prev_y: int = y - sy
	
	var has_next: bool = (next_x != x1 + sx) or (next_y != y1 + sy)
	var has_prev: bool = (prev_x != x0 - sx) or (prev_y != y0 - sy)
	
	var horizontal: bool = (next_y == y) or (prev_y == y)
	var vertical: bool = (next_x == x) or (prev_x == x)
	
	if horizontal and vertical:
		return "ROAD_CROSS"
	elif horizontal:
		return "ROAD_H"
	elif vertical:
		return "ROAD_V"
	else:
		return "ROAD_H"

## Genera el suelo para un bioma en un área
func generate_biome_area(bounds: Rect2i, biome: String) -> void:
	var base_tile: String = BIOME_BASE_TILE.get(biome, "DIRT")
	fill_rect(bounds, base_tile, LAYER_GROUND)
	
	# Añadir variación aleatoria
	_add_variation(bounds, biome)

## Añade variación aleatoria (tiles variantes)
func _add_variation(bounds: Rect2i, biome: String) -> void:
	var base_tile: String = BIOME_BASE_TILE.get(biome, "DIRT")
	var tile_data: Dictionary = TILE_TYPES[base_tile]
	
	if not tile_data.has("variants") or tile_data["variants"].size() == 0:
		return
	
	var variants: Array = tile_data["variants"]
	
	for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			if _rng.randf() < 0.3:
				var variant_coords: Vector2i = variants[_rng.randi_range(0, variants.size() - 1)]
				set_cell(LAYER_GROUND, Vector2i(x, y), 0, variant_coords)

## Autotiling simple: pone transiciones entre dos tipos de tile
func auto_tile_transition(pos_a: Vector2i, type_a: String, pos_b: Vector2i, type_b: String) -> void:
	var transition_key: String = "%s_TO_%s" % [type_a, type_b]
	if not TILE_TYPES.has(transition_key):
		transition_key = "%s_TO_%s" % [type_b, type_a]
	
	if TILE_TYPES.has(transition_key):
		var mid_x: int = int((pos_a.x + pos_b.x) / 2)
		var mid_y: int = int((pos_a.y + pos_b.y) / 2)
		set_tile_by_name(Vector2i(mid_x, mid_y), transition_key, LAYER_OVERLAY)

## Genera carretera entre dos puntos con autotiling completo
func generate_road_network(points: Array[Vector2i], layer: int = LAYER_GROUND) -> void:
	for i in range(points.size() - 1):
		var start: Vector2i = points[i]
		var end: Vector2i = points[i + 1]
		
		_draw_road_segment(start, end, layer)
		
		if i == 0:
			set_tile_by_name(start, "ROAD_T_DOWN", layer)
		if i == points.size() - 2:
			set_tile_by_name(end, "ROAD_T_UP", layer)

func _draw_road_segment(start: Vector2i, end: Vector2i, layer: int) -> void:
	var x0: int = start.x
	var y0: int = start.y
	var x1: int = end.x
	var y1: int = end.y
	
	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	
	var path: Array[Vector2i] = []
	
	while true:
		path.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	
	for i in range(path.size()):
		var pos: Vector2i = path[i]
		var prev: Vector2i = path[max(0, i - 1)]
		var next: Vector2i = path[min(path.size() - 1, i + 1)]
		
		var tile_name: String = _determine_road_tile(pos, prev, next)
		set_tile_by_name(pos, tile_name, layer)

func _determine_road_tile(current: Vector2i, prev: Vector2i, next: Vector2i) -> String:
	var from_prev: Vector2i = current - prev
	var to_next: Vector2i = next - current
	
	var dir_in: Vector2i = Vector2i(
		clamp(from_prev.x, -1, 1),
		clamp(from_prev.y, -1, 1)
	)
	var dir_out: Vector2i = Vector2i(
		clamp(to_next.x, -1, 1),
		clamp(to_next.y, -1, 1)
	)
	
	if dir_in == dir_out:
		if dir_in.x != 0:
			return "ROAD_H"
		else:
			return "ROAD_V"
	
	var turn: String = "%s,%s->%s,%s" % [dir_in.x, dir_in.y, dir_out.x, dir_out.y]
	
	match turn:
		"1,0->0,1": return "ROAD_CORNER_BR"
		"1,0->0,-1": return "ROAD_CORNER_TR"
		"-1,0->0,1": return "ROAD_CORNER_BL"
		"-1,0->0,-1": return "ROAD_CORNER_TL"
		"0,1->1,0": return "ROAD_CORNER_TR"
		"0,1->-1,0": return "ROAD_CORNER_TL"
		"0,-1->1,0": return "ROAD_CORNER_BR"
		"0,-1->-1,0": return "ROAD_CORNER_BL"
	
	return "ROAD_H"

# Genera el mapa completo del mundo
func generate_world_map(b: Rect2i) -> void:
	clear()
	
	# For testing, limit to a reasonable area around origin
	var test_bounds: Rect2i = Rect2i(-130, -130, 260, 260)
	var wb: Rect2i = _rect2i_intersection(b, test_bounds)
	
	var biome_areas: Array[Dictionary] = [
		{"bounds": Rect2i(-6300, -6300, 12600, 12600), "biome": "forest"},
		{"bounds": Rect2i(-2400, -1500, 4800, 3000), "biome": "urban"},
		{"bounds": Rect2i(-3000, -2000, 6000, 4000), "biome": "plains"},
	]
	
	for area in biome_areas:
		var intersection: Rect2i = _rect2i_intersection(area["bounds"], wb)
		if intersection.size.x > 0 and intersection.size.y > 0:
			generate_biome_area(intersection, area["biome"])
	
	var road_points: Array[Vector2i] = [
		Vector2i(-2160, 0), Vector2i(0, 0), Vector2i(2160, 0),
		Vector2i(0, -1350), Vector2i(0, 0), Vector2i(0, 1350),
	]
	generate_road_network(road_points, LAYER_GROUND)
	
	_apply_all_transitions(wb)

func _rect2i_intersection(a: Rect2i, b: Rect2i) -> Rect2i:
	var min_x: int = max(a.position.x, b.position.x)
	var min_y: int = max(a.position.y, b.position.y)
	var max_x: int = min(a.position.x + a.size.x, b.position.x + b.size.x)
	var max_y: int = min(a.position.y + a.size.y, b.position.y + b.size.y)
	
	if min_x >= max_x or min_y >= max_y:
		return Rect2i(0, 0, 0, 0)
	
	return Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)
	
	var road_points: Array[Vector2i] = [
		Vector2i(-2160, 0), Vector2i(0, 0), Vector2i(2160, 0),
		Vector2i(0, -1350), Vector2i(0, 0), Vector2i(0, 1350),
	]
	generate_road_network(road_points, LAYER_GROUND)
	
	_apply_all_transitions(b)

func _apply_all_transitions(bounds: Rect2i) -> void:
	for y in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			var current_pos: Vector2i = Vector2i(x, y)
			var current_tile: String = _get_tile_name_at(current_pos, LAYER_GROUND)
			
			if current_tile == "":
				continue
			
			for neighbor_dir in NEIGHBORS_4:
				var neighbor_pos: Vector2i = current_pos + neighbor_dir
				var neighbor_tile: String = _get_tile_name_at(neighbor_pos, LAYER_GROUND)
				
				if neighbor_tile != "" and neighbor_tile != current_tile:
					auto_tile_transition(current_pos, current_tile, neighbor_pos, neighbor_tile)

func _get_tile_name_at(pos: Vector2i, layer: int) -> String:
	var cell_data: TileData = get_cell_tile_data(layer, pos)
	if cell_data == null:
		return ""
	
	# Safely extract source_id and atlas_coords from TileData
	# In Godot 4.7, TileData might not have these as direct properties
	var source_id: int = -1
	var atlas_coords: Vector2i = Vector2i(-1, -1)
	
	# Try to get source_id
	var source_id_val: Variant = cell_data.get("source_id")
	if typeof(source_id_val) == TYPE_INT:
		source_id = source_id_val
	
	# Get atlas_coords
	var atlas_coords_val: Variant = cell_data.get("atlas_coords")
	if typeof(atlas_coords_val) == TYPE_VECTOR2I:
		atlas_coords = atlas_coords_val
	
	if source_id >= 0 and atlas_coords != Vector2i(-1, -1):
		var tileset: TileSet = get_tileset()
		if tileset:
			var source: TileSetAtlasSource = tileset.get_source(source_id) as TileSetAtlasSource
			if source:
				return source.get_tile_name(atlas_coords)
	
	return ""

## Utilidades ----------------------------------------------------------------

func get_tile_at(position: Vector2i, layer: int = LAYER_GROUND) -> Dictionary:
	var cell_data: TileData = get_cell_tile_data(layer, position)
	if cell_data == null:
		return {}
	
	return {
		"source_id": cell_data.source_id,
		"atlas_coords": cell_data.atlas_coords,
		"name": _get_tile_name_at(position, layer)
	}

func is_walkable_at(position: Vector2i, layer: int = LAYER_GROUND) -> bool:
	var tile_info: Dictionary = get_tile_at(position, layer)
	if tile_info.is_empty():
		return false
	
	var source: TileSetAtlasSource = _get_ground_source()
	if source == null:
		return true
	
	var transitable: Variant = source.get_tile_property(tile_info["atlas_coords"], "transitable")
	if typeof(transitable) == TYPE_BOOL:
		return bool(transitable)
	return true

func get_random_variant(tile_name: String) -> Vector2i:
	if not TILE_TYPES.has(tile_name):
		return Vector2i(0, 0)
	
	var tile_data: Dictionary = TILE_TYPES[tile_name]
	if not tile_data.has("variants") or tile_data["variants"].size() == 0:
		return TILE_TYPES[tile_name]["atlas_coords"]
	
	var variants: Array[Vector2i] = tile_data["variants"]
	return variants[_rng.randi_range(0, variants.size() - 1)]

func _get_ground_source() -> TileSetAtlasSource:
	var tileset: TileSet = get_tileset()
	if tileset == null:
		return null
	return tileset.get_source(0) as TileSetAtlasSource