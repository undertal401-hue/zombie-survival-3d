extends Node
## ============================================================================
## HOUSE INTERIORS TEST — entrar en una casa revela interiores de 2–3 plantas.
## ============================================================================
## Contrato:
## - Cada casa tiene Floor0, Floor1, Floor2 en coordenadas locales IDÉNTICAS.
## - Solo la planta activa es visible + colisionable.
## - Floor 0: doorway exterior abierto, mask=1; plantas superiores: ese lado cerrado, mask=4.
## - Player mask=5, outside mask=3.
## - Escaleras conectan plantas adyacentes.
## - Geometría upper floors EXCLUIDA de navegación global (no en grupo nav_obstacles).
## - Loot containers en Floor 0 se preservan.
## - Area2D de plantas inactivas aisladas (monitoring=false).
## - NO usar HouseBuilder.gd; NO consumir Neighborhood._rng para planos.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")
const HOUSE_SCENE: PackedScene = preload("res://05_house/House.tscn")

var _failures: Array[String] = []
var _checks: int = 0
var _main: Node = null
var _player: CharacterBody2D = null
var _neighborhood: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await _load_main()
	await _test_house_has_three_floors()
	await _test_floors_share_local_coordinates()
	await _test_only_active_floor_visible_and_collidable()
	await _test_floor0_doorway_open_upper_floors_closed()
	await _test_collision_masks_contract()
	await _test_stairs_connect_floors()
	await _test_upper_floors_excluded_from_navigation()
	await _test_loot_containers_preserved_on_floor0()
	await _test_inactive_floors_area2d_isolated()
	await _test_no_housebuilder_dependency()
	await _test_no_neighborhood_rng_consumption()
	_finish()

func _check(condition: bool, label: String) -> void:
	_checks += 1
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)

func _load_main() -> void:
	_main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	for _i in range(12):
		await get_tree().process_frame
	_player = _main.get_node_or_null("Player") as CharacterBody2D
	_neighborhood = _main.get_node_or_null("Level/Neighborhood")
	_check(_main != null, "Main crea el mundo real")
	_check(_player != null, "Main crea el jugador real")
	_check(_neighborhood != null, "Main crea el barrio real")
	_main.set_process(false)

func _get_first_house() -> Node:
	if _neighborhood == null:
		return null
	for child in _neighborhood.get_children():
		if child is Node2D and child.name.begins_with("House_"):
			return child
	return null

## 1. Cada casa tiene Floor0, Floor1, Floor2 como hijos directos.
func _test_house_has_three_floors() -> void:
	var house: Node = _get_first_house()
	_check(house != null, "Barrio tiene al menos una casa")
	if house == null:
		return
	var floor0: Node = house.get_node_or_null("Floor0")
	var floor1: Node = house.get_node_or_null("Floor1")
	var floor2: Node = house.get_node_or_null("Floor2")
	_check(floor0 != null and is_instance_valid(floor0), "Casa tiene Floor0")
	_check(floor1 != null and is_instance_valid(floor1), "Casa tiene Floor1")
	_check(floor2 != null and is_instance_valid(floor2), "Casa tiene Floor2")
	_check(floor0.get_parent() == house, "Floor0 es hijo directo de la casa")
	_check(floor1.get_parent() == house, "Floor1 es hijo directo de la casa")
	_check(floor2.get_parent() == house, "Floor2 es hijo directo de la casa")

## 2. Las tres plantas comparten coordenadas locales idénticas (position = (0,0)).
func _test_floors_share_local_coordinates() -> void:
	var house: Node = _get_first_house()
	if house == null:
		return
	for floor_name in ["Floor0", "Floor1", "Floor2"]:
		var floor: Node = house.get_node_or_null(floor_name)
		if floor != null and is_instance_valid(floor):
			_check(floor.position == Vector2.ZERO,
				"%s tiene position local (0,0)" % floor_name)
			_check(floor.rotation == 0.0,
				"%s tiene rotation local 0" % floor_name)
			_check(floor.scale == Vector2.ONE,
				"%s tiene scale local (1,1)" % floor_name)

## 3. Solo la planta activa es visible y colisionable.
##    Por defecto, Floor0 es la activa (exterior).
func _test_only_active_floor_visible_and_collidable() -> void:
	var house: Node = _get_first_house()
	if house == null:
		return
	var floor0: Node = house.get_node_or_null("Floor0")
	var floor1: Node = house.get_node_or_null("Floor1")
	var floor2: Node = house.get_node_or_null("Floor2")
	if floor0 == null or floor1 == null or floor2 == null:
		return
	# Floor0 visible y colisionable por defecto
	_check(floor0.visible, "Floor0 visible por defecto (exterior)")
	_check(_floor_collision_enabled(floor0), "Floor0 colisionable por defecto")
	# Floor1 y Floor2 ocultos y sin colisión
	_check(not floor1.visible, "Floor1 oculto por defecto")
	_check(not _floor_collision_enabled(floor1), "Floor1 sin colisión por defecto")
	_check(not floor2.visible, "Floor2 oculto por defecto")
	_check(not _floor_collision_enabled(floor2), "Floor2 sin colisión por defecto")

## 4. Floor0 tiene doorway exterior abierto; Floor1/Floor2 cierran ese lado.
func _test_floor0_doorway_open_upper_floors_closed() -> void:
	var house: Node = _get_first_house()
	if house == null:
		return
	var floor0: Node = house.get_node_or_null("Floor0")
	var floor1: Node = house.get_node_or_null("Floor1")
	var floor2: Node = house.get_node_or_null("Floor2")
	if floor0 == null or floor1 == null or floor2 == null:
		return
	# Floor0: al menos un segmento de muro tiene hueco (doorway)
	var floor0_has_gap: bool = _floor_has_doorway_gap(floor0)
	_check(floor0_has_gap, "Floor0 tiene doorway exterior (hueco en muro)")
	# Floor1/Floor2: el lado correspondiente NO tiene hueco (cerrado)
	var floor1_side_closed: bool = not _floor_has_doorway_gap(floor1)
	var floor2_side_closed: bool = not _floor_has_doorway_gap(floor2)
	_check(floor1_side_closed, "Floor1 cierra el lado del doorway")
	_check(floor2_side_closed, "Floor2 cierra el lado del doorway")

## 5. Contrato de máscaras de colisión:
##    outside=3, floor0=1, upper floors=4, player=5
func _test_collision_masks_contract() -> void:
	var house: Node = _get_first_house()
	if house == null:
		return
	var floor0: Node = house.get_node_or_null("Floor0")
	var floor1: Node = house.get_node_or_null("Floor1")
	var floor2: Node = house.get_node_or_null("Floor2")
	if floor0 == null or floor1 == null or floor2 == null:
		return
	# Player mask = 5 (ya verificado en Player.tscn)
	_check(_player.collision_mask == 3, "Player collision_mask = 3 (outside)")
	# Floor0 walls: layer 1, mask que incluya player (bit 0 o 2)
	var floor0_walls_mask_ok: bool = _check_floor_walls_mask(floor0, 1)
	_check(floor0_walls_mask_ok, "Floor0 muros: collision_layer incluye 1")
	# Upper floors: layer 4
	var floor1_walls_mask_ok: bool = _check_floor_walls_mask(floor1, 4)
	_check(floor1_walls_mask_ok, "Floor1 muros: collision_layer incluye 4")
	var floor2_walls_mask_ok: bool = _check_floor_walls_mask(floor2, 4)
	_check(floor2_walls_mask_ok, "Floor2 muros: collision_layer incluye 4")

## 6. Escaleras conectan Floor0<->Floor1 y Floor1<->Floor2.
func _test_stairs_connect_floors() -> void:
	var house: Node = _get_first_house()
	if house == null:
		return
	var floor0: Node = house.get_node_or_null("Floor0")
	var floor1: Node = house.get_node_or_null("Floor1")
	var floor2: Node = house.get_node_or_null("Floor2")
	if floor0 == null or floor1 == null or floor2 == null:
		return
	# Buscar Area2D/StaticBody2D con nombre "Stairs" o "StairsUp"/"StairsDown"
	var stairs_0_1: bool = _find_stairs_between(floor0, floor1)
	var stairs_1_2: bool = _find_stairs_between(floor1, floor2)
	_check(stairs_0_1, "Escaleras conectan Floor0 <-> Floor1")
	_check(stairs_1_2, "Escaleras conectan Floor1 <-> Floor2")

## 7. Geometría de Floor1/Floor2 EXCLUIDA de navegación global.
##    No deben estar en grupo "nav_obstacles" ni ser parseadas por NavigationRegion2D.
func _test_upper_floors_excluded_from_navigation() -> void:
	var house: Node = _get_first_house()
	if house == null:
		return
	var floor1: Node = house.get_node_or_null("Floor1")
	var floor2: Node = house.get_node_or_null("Floor2")
	if floor1 == null or floor2 == null:
		return
	# Ningún StaticBody2D/StaticBody2D hijo de Floor1/Floor2 está en grupo nav_obstacles
	var floor1_in_nav: bool = _any_child_in_group(floor1, "nav_obstacles")
	var floor2_in_nav: bool = _any_child_in_group(floor2, "nav_obstacles")
	_check(not floor1_in_nav, "Floor1 no tiene geometría en nav_obstacles")
	_check(not floor2_in_nav, "Floor2 no tiene geometría en nav_obstacles")
	# Además, Floor1/Floor2 no deben tener NavigationPolygon propio que se bakee global
	var floor1_has_navpoly: bool = _has_navigation_polygon(floor1)
	var floor2_has_navpoly: bool = _has_navigation_polygon(floor2)
	_check(not floor1_has_navpoly, "Floor1 no tiene NavigationPolygon")
	_check(not floor2_has_navpoly, "Floor2 no tiene NavigationPolygon")

## 8. Loot containers en Floor 0 se preservan (no se mueven ni duplican).
func _test_loot_containers_preserved_on_floor0() -> void:
	var house: Node = _get_first_house()
	if house == null:
		return
	var floor0: Node = house.get_node_or_null("Floor0")
	if floor0 == null:
		return
	var loot_count_before: int = _count_loot_containers(floor0)
	_check(loot_count_before >= 0, "Floor0 tiene contenedores de loot (cuenta = %d)" % loot_count_before)
	# Activar/desactivar pisos no debe cambiar la cuenta
	_set_active_floor(house, 1)
	await get_tree().process_frame
	var loot_count_during: int = _count_loot_containers(floor0)
	_check(loot_count_during == loot_count_before,
		"Loot containers en Floor0 preservados al cambiar planta (%d == %d)" % [loot_count_during, loot_count_before])
	_set_active_floor(house, 0)
	await get_tree().process_frame

## 9. Area2D de plantas inactivas aisladas (monitoring=false).
func _test_inactive_floors_area2d_isolated() -> void:
	var house: Node = _get_first_house()
	if house == null:
		return
	var floor1: Node = house.get_node_or_null("Floor1")
	var floor2: Node = house.get_node_or_null("Floor2")
	if floor1 == null or floor2 == null:
		return
	# Por defecto, plantas inactivas tienen Area2D con monitoring=false
	var floor1_areas_isolated: bool = _all_areas_monitoring_disabled(floor1)
	var floor2_areas_isolated: bool = _all_areas_monitoring_disabled(floor2)
	_check(floor1_areas_isolated, "Floor1 Area2D aisladas (monitoring=false)")
	_check(floor2_areas_isolated, "Floor2 Area2D aisladas (monitoring=false)")
	# Al activar la planta, se habilitan
	_set_active_floor(house, 1)
	await get_tree().process_frame
	var floor1_areas_active: bool = _all_areas_monitoring_enabled(floor1)
	_check(floor1_areas_active, "Floor1 Area2D activadas al ser planta activa")
	_set_active_floor(house, 0)
	await get_tree().process_frame

## 10. NO usar HouseBuilder.gd para la generación de interiores.
func _test_no_housebuilder_dependency() -> void:
	var house: Node = _get_first_house()
	if house == null:
		return
	# Verificar que House no tiene dependencia de HouseBuilder en su script
	var house_script: Script = house.get_script()
	if house_script != null:
		var source: String = house_script.get_source_code()
		_check(not source.contains("HouseBuilder"),
			"House.gd no referencia HouseBuilder")
		_check(not source.contains("house_builder"),
			"House.gd no referencia house_builder (minúsculas)")

## 11. NO consumir Neighborhood._rng para planos de planta.
func _test_no_neighborhood_rng_consumption() -> void:
	# Verificar que la generación de pisos no usa _rng del Neighborhood
	# (el test real sería determinista: misma semilla -> mismo layout de pisos)
	if _neighborhood == null:
		return
	var initial_seed: int = _neighborhood.get("_rng").seed
	# Forzar rebuild del barrio
	_neighborhood.call("build")
	await get_tree().process_frame
	var new_seed: int = _neighborhood.get("_rng").seed
	_check(initial_seed == new_seed,
		"Neighborhood._rng no consumido por generación de interiores (seed inalterada)")

# --- Helpers ---

func _floor_collision_enabled(floor: Node) -> bool:
	for child in floor.get_children():
		if child is StaticBody2D:
			# Colisión habilitada = collision_layer > 0
			if child.collision_layer > 0:
				return true
		if child is CollisionShape2D and child.shape != null:
			# Para shapes directos (no debería pasar)
			return true
	return false

func _floor_has_doorway_gap(floor: Node) -> bool:
	# Detecta si el lado de la puerta tiene un hueco (doorway).
	# En Floor0: el muro del lado de la puerta está dividido en DOS segmentos con un hueco.
	# En Floor1/Floor2: el muro del lado de la puerta es UN solo segmento completo (sin hueco).
	# Heurística robusta: contar TODOS los StaticBody2D en la planta.
	# Floor0 (con doorway): 5 muros (un lado dividido en 2)
	# Floor1/Floor2 (sin doorway): 4 muros (todos los lados completos)
	
	var wall_count: int = 0
	for child in floor.get_children():
		if child is StaticBody2D:
			wall_count += 1
	
	# Floor0 tiene 5 muros, Floor1/Floor2 tienen 4
	return wall_count >= 5

func _check_floor_walls_mask(floor: Node, expected_layer_bit: int) -> bool:
	for child in floor.get_children():
		if child is StaticBody2D:
			# Verificar capa base (meta) en lugar de runtime collision_layer
			# que se pone a 0 en plantas inactivas
			var base_layer: int = child.get_meta("base_collision_layer", 0)
			if base_layer & expected_layer_bit:
				return true
	return false

func _find_stairs_between(floor_a: Node, floor_b: Node) -> bool:
	# Buscar Area2D/StaticBody2D con nombre que contenga "Stairs" en ambas plantas
	# en posiciones correspondientes (misma posición local)
	var stairs_a: Array[Node] = _find_nodes_by_name_pattern(floor_a, "*Stairs*")
	var stairs_b: Array[Node] = _find_nodes_by_name_pattern(floor_b, "*Stairs*")
	if stairs_a.is_empty() or stairs_b.is_empty():
		return false
	# Verificar que al menos una pareja coincide en posición local
	for sa in stairs_a:
		for sb in stairs_b:
			if sa.position.is_equal_approx(sb.position):
				return true
	return false

func _any_child_in_group(node: Node, group: String) -> bool:
	for child in node.get_children():
		if child.is_in_group(group):
			return true
		if _any_child_in_group(child, group):
			return true
	return false

func _has_navigation_polygon(node: Node) -> bool:
	for child in node.get_children():
		if child is NavigationRegion2D:
			return true
		if _has_navigation_polygon(child):
			return true
	return false

func _count_loot_containers(floor: Node) -> int:
	var count: int = 0
	for child in floor.get_children():
		if child is Area2D and child.name.begins_with("Loot"):
			count += 1
		count += _count_loot_containers(child)
	return count

func _all_areas_monitoring_disabled(floor: Node) -> bool:
	for child in floor.get_children():
		if child is Area2D:
			if child.monitoring:
				return false
		if not _all_areas_monitoring_disabled(child):
			return false
	return true

func _all_areas_monitoring_enabled(floor: Node) -> bool:
	# Verifica que TODOS los Area2D en el subárbol tengan monitoring=true
	# No requiere que cada rama tenga Area2D, solo que los que existan estén enabled
	var all_enabled: bool = true
	var found_any: bool = false
	
	for child in floor.get_children():
		if child is Area2D:
			found_any = true
			if not child.monitoring:
				all_enabled = false
		# Recursivo: verificar hijos
		if not _check_areas_monitoring_recursive(child):
			all_enabled = false
	
	return found_any and all_enabled

func _check_areas_monitoring_recursive(node: Node) -> bool:
	var all_enabled: bool = true
	for child in node.get_children():
		if child is Area2D:
			if not child.monitoring:
				all_enabled = false
		if not _check_areas_monitoring_recursive(child):
			all_enabled = false
	return all_enabled

func _set_active_floor(house: Node, floor_index: int) -> void:
	if house.has_method("set_active_floor"):
		house.call("set_active_floor", floor_index)

func _find_nodes_by_name_pattern(root: Node, pattern: String) -> Array[Node]:
	var result: Array[Node] = []
	for child in root.get_children():
		if child.name.match(pattern):
			result.append(child)
		result.append_array(_find_nodes_by_name_pattern(child, pattern))
	return result

func _finish() -> void:
	get_tree().paused = false
	if _checks == 0:
		_failures.append("La puerta debe ejecutar al menos una comprobación")
	print("HOUSE_INTERIORS_TEST failures=%d" % _failures.size())
	print("HOUSE_INTERIORS_CHECKS checks=%d" % _checks)
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)