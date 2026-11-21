extends Node
## ============================================================================
## LUMINA GROUND TEST — contrato visual del suelo pixel art suministrado.
## ============================================================================
## El atlas ground_tiles.png contiene 10x10 piezas con paso de 48 px. Este
## arnés comprueba que el juego usa ese paso real, que existe una sola capa
## global de suelo, que queda por encima de las bases planas que la ocultaban
## y que decoration_tiles.png se pinta como decoracion visible.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")
const GROUND_SCRIPT: GDScript = preload("res://05_house/GroundTileMap.gd")
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

	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var ground: TileMap = main.get_node_or_null("Ground") as TileMap
	_check(ground != null, "Main contiene un nodo Ground de tipo TileMap")
	if ground != null:
		_check(ground.tile_size == Vector2i(48, 48),
			"Ground usa el paso real de 48 px del atlas (obtenido=%s)" % str(ground.tile_size))
		_check(ground.get_tileset() != null, "Ground tiene un TileSet asignado")
		_check(ground.get_used_cells(0).size() > 0, "Ground tiene celdas pintadas")
		_check(ground.z_index > -10.0,
			"Ground queda por encima de las bases planas z=-10 (z=%s)" % str(ground.z_index))
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
			_check(ground_source.texture_region_size == Vector2i(48, 48),
				"La fuente de ground_tiles usa regiones 48x48 (obtenido=%s)" %
				str(ground_source.texture_region_size))

	var forest: Node = main.get_node_or_null("Level/Forest")
	var forest_floor: CanvasItem = forest.get_node_or_null("ForestFloor") as CanvasItem if forest != null else null
	var urban_base: CanvasItem = forest.get_node_or_null("UrbanBase") as CanvasItem if forest != null else null
	if ground != null:
		_check(forest_floor == null or ground.z_index > forest_floor.z_index,
			"Ground queda por encima de ForestFloor")
		_check(urban_base == null or ground.z_index > urban_base.z_index,
			"Ground queda por encima de UrbanBase")

	var ground_instances: int = _count_ground_instances(main)
	_check(ground_instances == 1,
		"El mundo contiene una sola instancia global de GroundTileMap (encontradas=%d)" %
		ground_instances)

	var decorations: Node = _find_named(main, "LuminaDecorations")
	_check(decorations != null, "Existe la capa LuminaDecorations")
	if decorations != null:
		var visible_sprites: int = 0
		for child in decorations.get_children():
			var sprite := child as Sprite2D
			if sprite != null and sprite.visible and sprite.texture is AtlasTexture:
				var atlas := (sprite.texture as AtlasTexture).atlas
				if atlas != null and atlas.resource_path.contains("decoration_tiles"):
					visible_sprites += 1
		_check(visible_sprites >= 3,
			"Se muestran al menos 3 sprites de decoration_tiles.png (mostrados=%d)" % visible_sprites)

	print("LUMINA_GROUND_TEST failures=%d" % _failures.size())
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _count_ground_instances(node: Node) -> int:
	var count: int = 0
	if node.get_script() == GROUND_SCRIPT:
		count += 1
	for child in node.get_children():
		count += _count_ground_instances(child)
	return count


func _find_named(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_named(child, target_name)
		if found != null:
			return found
	return null
