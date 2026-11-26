extends Node
## ============================================================================
## LUMINA GROUND TEST V2 — contrato del suelo continuo con arte de Lumina.
## ============================================================================
## ground_tiles.png son 100 trozos redondeados con huecos transparentes, no una
## hoja de tiles sellados. Por eso el juego NO muestrea el PNG en rejilla:
##   - el TileMap cubre el mundo con celdas opacas y un shader pinta la base
##     continua por bioma (colores medios del atlas, borde ondulado);
##   - GroundDetailLayer reparte trozos reales del atlas en manchas dispersas.
## Este arnés comprueba ese contrato y que el PNG original queda intacto.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")
const GROUND_SCRIPT: GDScript = preload("res://05_house/GroundTileMapV2.gd")
const GROUND_TEXTURE: String = "res://assets/lumina_textures/ground_tiles.png"
const DECORATION_TEXTURE: String = "res://assets/lumina_textures/decoration_tiles.png"
## SHA-256 del asset congelado: si cambia, hay que revisar las bandas medidas.
const GROUND_SHA256: String = "10b6e81c16f0091f61172497cc191b8cfa8d581ceff92529c851594e6c8ebfd2"

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _sha256(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


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
	_check(_sha256(GROUND_TEXTURE) == GROUND_SHA256,
		"ground_tiles.png conserva su SHA-256 original")

	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var ground: TileMap = main.get_node_or_null("Ground") as TileMap
	_check(ground != null, "Main contiene un nodo Ground de tipo TileMap")
	if ground == null:
		_finish()
		return

	_check(ground.get_tileset() != null, "Ground tiene un TileSet asignado")
	if ground.get_tileset() != null:
		_check(ground.get_tileset().tile_size == Vector2i(32, 32),
			"Ground usa celdas de 32 px (obtenido=%s)" %
			str(ground.get_tileset().tile_size))
		_check(ground.get_tileset().get_source_count() == 1,
			"El TileSet tiene una unica fuente de atlas (encontradas=%d)" %
			ground.get_tileset().get_source_count())

	# --- Textura derivada: el TileSet no muestrea el PNG original -------------
	var derived: Texture2D = ground.get("derived_texture") as Texture2D
	_check(derived != null, "Ground construye una textura derivada en memoria")
	var source: TileSetAtlasSource = null
	if ground.get_tileset() != null and ground.get_tileset().get_source_count() > 0:
		source = ground.get_tileset().get_source(0) as TileSetAtlasSource
	_check(source != null, "La fuente 0 es un TileSetAtlasSource")
	if source != null:
		_check(source.texture == derived,
			"El TileSet usa la textura derivada, no el PNG original")
		_check(source.texture != ground_texture,
			"El PNG original queda fuera del muestreo por rejilla")
		_check(source.texture_region_size == Vector2i(32, 32),
			"La fuente usa regiones de 32x32 (obtenido=%s)" %
			str(source.texture_region_size))
		if derived != null:
			_check(derived.get_size() == Vector2(32, 32 * 7),
				"La textura derivada tiene una fila de 32 px por material (obtenido=%s)" %
				str(derived.get_size()))

	# --- Cobertura total del mundo y celdas coherentes ------------------------
	var used_cells := ground.get_used_cells(0)
	_check(used_cells.size() > 0, "Ground tiene celdas pintadas")
	var min_x: int = 999999
	var min_y: int = 999999
	var max_x: int = -999999
	var max_y: int = -999999
	var invalid_cells: int = 0
	for cell in used_cells:
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
		var coords := ground.get_cell_atlas_coords(0, cell)
		if coords.x != 0 or coords.y < 0 or coords.y >= 7:
			invalid_cells += 1
	_check(min_x <= -196 and max_x >= 196 and min_y <= -196 and max_y >= 196,
		"El suelo cubre el mundo completo +-6300 (celdas=%s..%s, %s..%s)" %
		[str(min_x), str(max_x), str(min_y), str(max_y)])
	_check(invalid_cells == 0,
		"Todas las celdas usan una fila de material valida (invalidas=%d)" %
		invalid_cells)
	_check(ground.z_index > -10.0,
		"Ground queda por encima de las bases planas z=-10 (z=%s)" % str(ground.z_index))

	# --- Shader de base continua ---------------------------------------------
	var biome_material := ground.material as ShaderMaterial
	_check(biome_material != null and biome_material.shader != null,
		"El suelo usa un ShaderMaterial para la base continua")
	if biome_material != null:
		var required_params: Array[String] = [
			"plains_light", "plains_dark", "urban_light", "urban_dark",
			"forest_light", "forest_dark", "urban_half", "plains_half"]
		var missing_params: Array[String] = []
		for param in required_params:
			if biome_material.get_shader_parameter(param) == null:
				missing_params.append(param)
		_check(missing_params.is_empty(),
			"El shader recibe los tonos del atlas y los limites de bioma (faltan=%s)" %
			str(missing_params))

	# --- Capa de detalle con trozos reales ------------------------------------
	var detail: Node = ground.get_node_or_null("GroundDetail")
	_check(detail != null, "Ground tiene capa de detalle GroundDetail")
	if detail != null:
		var regions_ok: bool = true
		for material in range(7):
			var regions: Array = ground.call("chunk_regions_for", material)
			if regions.size() != 10:
				regions_ok = false
		_check(regions_ok,
			"Cada material tiene los 10 trozos del atlas como regiones de detalle")
		var detail_item := detail as CanvasItem
		if detail_item != null:
			_check(detail_item.z_index > ground.z_index,
				"El detalle queda por encima de la base")

	# --- Tipo de tile por bioma ----------------------------------------------
	_check(int(ground.call("material_at_world", Vector2(0, 0))) == 4,
		"El centro urbano usa losa (material 4)")
	_check(int(ground.call("material_at_world", Vector2(0, 1800))) == 1,
		"Las llanuras usan pasto con matas (material 1)")
	_check(int(ground.call("material_at_world", Vector2(0, 9000))) == 6,
		"El bosque usa suelo de bosque (material 6)")

	# --- Tiles explicitos y API publica --------------------------------------
	var required_tiles: Array[String] = [
		"GRASS", "GRASS_TUFT", "DIRT", "SAND", "STONE", "STONE_MOSS",
		"FOREST_FLOOR", "DIRT_GRASS", "ROAD_H", "ROAD_V", "ROAD_CORNER_TL",
		"ROAD_CORNER_TR", "ROAD_CORNER_BL", "ROAD_CORNER_BR", "ROAD_T_UP",
		"ROAD_T_DOWN", "ROAD_T_LEFT", "ROAD_T_RIGHT", "ROAD_CROSS",
		"GRASS_TO_DIRT", "DIRT_TO_STONE", "GRASS_TO_STONE"]
	var missing_tiles: Array[String] = []
	for tile_name in required_tiles:
		var coords: Vector2i = ground.call("get_tile_atlas_coords", tile_name)
		if coords.x != 0 or coords.y < 0 or coords.y >= 7:
			missing_tiles.append(tile_name)
	_check(missing_tiles.is_empty(),
		"Todos los tiles explícitos apuntan a una fila valida (faltantes=%s)" %
		str(missing_tiles))

	var probe := Vector2i(40, 40)
	ground.call("set_tile_by_name", probe, "STONE")
	var probe_info: Dictionary = ground.call("get_tile_at", probe)
	_check(not probe_info.is_empty() and int(probe_info.get("row", -1)) == 4,
		"set_tile_by_name coloca el material pedido (fila=%s)" %
		str(probe_info.get("row", null)))
	_check(bool(ground.call("is_walkable_at", probe)),
		"El suelo es transitable")

	# --- Orden respecto a las capas del bosque -------------------------------
	var forest: Node = main.get_node_or_null("Level/Forest")
	var forest_floor: CanvasItem = forest.get_node_or_null("ForestFloor") as CanvasItem if forest != null else null
	var urban_base: CanvasItem = forest.get_node_or_null("UrbanBase") as CanvasItem if forest != null else null
	var clearings: CanvasItem = forest.get_node_or_null("Clearings") as CanvasItem if forest != null else null
	var forest_paths: CanvasItem = forest.get_node_or_null("Paths") as CanvasItem if forest != null else null
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

	var cells_before: int = ground.get_used_cells(0).size()
	ground.call("generate_world_map", Rect2i(-Vector2i(6300, 6300), Vector2i(12600, 12600)))
	var cells_after: int = ground.get_used_cells(0).size()
	_check(cells_after == cells_before,
		"Regenerar el suelo es idempotente (celdas=%d->%d)" %
		[cells_before, cells_after])

	_finish()


func _finish() -> void:
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
