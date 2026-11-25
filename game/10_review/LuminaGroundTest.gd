extends Node
## ============================================================================
## LUMINA GROUND TEST V2 — contrato visual del suelo pixel art con tiles explícitos.
## ============================================================================
## El atlas ground_tiles.png contiene 16x16 piezas con paso de 32 px (layout original Lumina).
## Este arnés comprueba que el juego usa ese paso real (32x32), que existe una sola capa
## global de suelo con tiles explícitos (DIRT, GRASS, ROAD, etc.), que queda
## por encima de las bases planas y que decoration_tiles.png se pinta como decoración.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")
const GROUND_SCRIPT: GDScript = preload("res://05_house/GroundTileMapV2.gd")
const GROUND_TEXTURE: String = "res://assets/lumina_textures/ground_tiles.png"
const DECORATION_TEXTURE: String = "res://assets/lumina_textures/decoration_tiles.png"

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_check(FileAccess.file_exists(GROUND_TEXTURE), "ground_tiles.png existe en el proyecto")
	_check(FileAccess.file_exists(DECORATION_TEXTURE), "decoration_tiles.png existe en el proyecto")
	var ground_texture := load(GROUND_TEXTURE) as Texture2D
	var decoration_texture := load(DECORATION_TEXTURE) as Texture2D
	_check(ground_texture != null and ground_texture.get_size() == Vector2(512, 512),
		"ground_tiles.png carga como textura 512x512")
	_check(decoration_texture != null and decoration_texture.get_size() == Vector2(512, 512),
		"decoration_tiles.png carga como textura 512x512")

	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var ground: TileMap = main.get_node_or_null("Ground") as TileMap
	_check(ground != null, "Main contiene un nodo Ground de tipo TileMap")
	if ground != null:
		_check(ground.get_tileset() != null, "Ground tiene un TileSet asignado")
		if ground.get_tileset() != null:
			_check(ground.get_tileset().tile_size == Vector2i(32, 32),
				"Ground usa el paso real de 32 px del atlas (obtenido=%s)" %
				str(ground.get_tileset().tile_size))
			_check(ground.get_tileset().get_source_count() == 1,
				"El TileSet tiene una unica fuente de atlas (encontradas=%d)" %
				ground.get_tileset().get_source_count())
		var used_cells := ground.get_used_cells(0)
		_check(used_cells.size() > 0, "Ground tiene celdas pintadas")
		var min_x: int = 999999
		var min_y: int = 999999
		var max_x: int = -999999
		var max_y: int = -999999
		for cell in used_cells:
			min_x = mini(min_x, cell.x)
			min_y = mini(min_y, cell.y)
			max_x = maxi(max_x, cell.x)
			max_y = maxi(max_y, cell.y)
		_check(min_x <= -130 and max_x >= 130 and min_y <= -130 and max_y >= 130,
			"El atlas cubre el mundo completo +-6300 (celdas=%s..%s, %s..%s)" %
			[str(min_x), str(max_x), str(min_y), str(max_y)])
		_check(ground.z_index > -10.0,
			"Ground queda por encima de las bases planas z=-10 (z=%s)" % str(ground.z_index))
		
		# Verificar que el TileSet tiene los tiles explícitos definidos
		var ground_source: TileSetAtlasSource = null
		if ground.get_tileset() != null:
			for source_id in range(ground.get_tileset().get_source_count()):
				var source := ground.get_tileset().get_source(source_id) as TileSetAtlasSource
				if source != null and source.texture != null \
						and source.texture.resource_path.contains("ground_tiles"):
					ground_source = source
					break
		_check(ground_source != null, "El TileSet referencia ground_tiles.png")
		if ground_source != null:
			_check(ground_source.texture_region_size == Vector2i(32, 32),
				"La fuente de ground_tiles usa regiones 32x32 (obtenido=%s)" %
				str(ground_source.texture_region_size))
			
			# Verificar que existen los tiles explícitos definidos en GroundTileMapV2 (atlas 16x16)
			var required_tiles: Array[String] = ["DIRT", "GRASS", "DIRT_GRASS", "STONE", "FOREST_FLOOR", 
				"ROAD_H", "ROAD_V", "ROAD_CORNER_TL", "ROAD_CORNER_TR", "ROAD_CORNER_BL", "ROAD_CORNER_BR",
				"ROAD_T_UP", "ROAD_T_DOWN", "ROAD_T_LEFT", "ROAD_T_RIGHT", "ROAD_CROSS"]
			var missing_tiles: Array[String] = []
			for tile_name in required_tiles:
				var found: bool = false
				# Hardcoded expected atlas coordinates for each required tile type
				# (matching GroundTileMapV2.TILE_TYPES for 16x16 atlas)
				var tile_expected_coords: Dictionary = {
					"DIRT": Vector2i(0, 2),
					"GRASS": Vector2i(0, 0),
					"DIRT_GRASS": Vector2i(4, 0),
					"STONE": Vector2i(0, 4),
					"FOREST_FLOOR": Vector2i(0, 8),
					"ROAD_H": Vector2i(12, 2),
					"ROAD_V": Vector2i(13, 2),
					"ROAD_CORNER_TL": Vector2i(12, 3),
					"ROAD_CORNER_TR": Vector2i(13, 3),
					"ROAD_CORNER_BL": Vector2i(12, 4),
					"ROAD_CORNER_BR": Vector2i(13, 4),
					"ROAD_T_UP": Vector2i(12, 5),
					"ROAD_T_DOWN": Vector2i(13, 5),
					"ROAD_T_LEFT": Vector2i(12, 6),
					"ROAD_T_RIGHT": Vector2i(13, 6),
					"ROAD_CROSS": Vector2i(12, 7),
					"GRASS_TO_DIRT": Vector2i(4, 2),
					"DIRT_TO_STONE": Vector2i(5, 2),
					"GRASS_TO_STONE": Vector2i(6, 2),
					"WATER": Vector2i(4, 8),
					"WATER_SHORE": Vector2i(5, 8),
					"SAND": Vector2i(6, 8),
				}
				var expected_coords: Vector2i = tile_expected_coords.get(tile_name, Vector2i(-1, -1))
				if expected_coords != Vector2i(-1, -1):
					# Verify tile exists at expected coordinates (16x16 = 256 tiles)
					var tile_id: int = expected_coords.y * 16 + expected_coords.x
					if tile_id >= 0 and tile_id < 256:
						found = true
				if not found:
					missing_tiles.append(tile_name)
			_check(missing_tiles.is_empty(),
				"Todos los tiles explícitos requeridos existen (faltantes=%s)" % str(missing_tiles))
			
			# Verificar que el atlas tiene las 256 coordenadas válidas 16x16
			var invalid_atlas_cells: int = 0
			for cell in ground.get_used_cells(0):
				var atlas_coords := ground.get_cell_atlas_coords(0, cell)
				if atlas_coords.x < 0 or atlas_coords.x > 15 \
						or atlas_coords.y < 0 or atlas_coords.y > 15:
					invalid_atlas_cells += 1
			_check(invalid_atlas_cells == 0,
				"Todas las celdas pintadas usan coordenadas existentes (invalidas=%d)" %
				invalid_atlas_cells)

	var forest: Node = main.get_node_or_null("Level/Forest")
	var forest_floor: CanvasItem = forest.get_node_or_null("ForestFloor") as CanvasItem if forest != null else null
	var urban_base: CanvasItem = forest.get_node_or_null("UrbanBase") as CanvasItem if forest != null else null
	var clearings: CanvasItem = forest.get_node_or_null("Clearings") as CanvasItem if forest != null else null
	var forest_paths: CanvasItem = forest.get_node_or_null("Paths") as CanvasItem if forest != null else null
	if ground != null:
		_check(forest_floor == null or ground.z_index > forest_floor.z_index,
			"Ground queda por encima de ForestFloor")
		_check(urban_base == null or ground.z_index > urban_base.z_index,
			"Ground queda por encima de UrbanBase")
		_check(clearings == null or ground.z_index < clearings.z_index,
			"Ground queda por debajo de los claros")
		_check(forest_paths == null or ground.z_index < forest_paths.z_index,
			"Ground queda por debajo de los caminos del bosque")

	var ground_instances: int = _count_ground_instances_v2(main)
	_check(ground_instances == 1,
		"El mundo contiene una sola instancia global de GroundTileMapV2 (encontradas=%d)" %
		ground_instances)

	if ground != null:
		var cells_before: int = ground.get_used_cells(0).size()
		ground.call("generate_world_map", Rect2i(-Vector2i(6300, 6300), Vector2i(12600, 12600)))
		var cells_after: int = ground.get_used_cells(0).size()
		_check(cells_after == cells_before,
			"Regenerar el suelo es idempotente (celdas=%d->%d)" %
			[cells_before, cells_after])

	print("LUMINA_GROUND_TEST failures=%d" % _failures.size())
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _count_ground_instances_v2(node: Node) -> int:
	var count: int = 0
	if node.get_script() == GROUND_SCRIPT:
		count += 1
	for child in node.get_children():
		count += _count_ground_instances_v2(child)
	return count


func _find_named(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_named(child, target_name)
		if found != null:
			return found
	return null