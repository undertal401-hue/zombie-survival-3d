extends Node
## ============================================================================
## OPEN SETTLEMENT TEST — pueblos transitables a pie.
## ============================================================================
## El punto 8 exige entrar caminando a los pueblos, sin barricada fisica, sin
## cartel CERRADO y sin teletransporte. Esta puerta construye la escena real
## Main.tscn, verifica los tres huecos perimetrales mediante el navmesh y
## comprueba que cada pueblo secundario conserva casas y un camino que lo
## une a una carretera principal.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")
const WALL_GAP_X: float = 1200.0
const WALL_GAP_WEST_Y: float = -600.0
const WALL_GAP_WIDTH: float = 200.0
const EXPECTED_TOWNS: Array[String] = [
	"Pueblo Norte",
	"Pueblo Sur",
	"Pueblo Oeste",
]
const MAIN_ROAD_TOLERANCE: float = 48.0
const NAV_ENDPOINT_TOLERANCE: float = 3.0
const TOWN_NAV_TOLERANCE: float = 220.0

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	var main: Node2D = MAIN_SCENE.instantiate() as Node2D
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	var neighborhood: Neighborhood = main.get_node("Level/Neighborhood") as Neighborhood
	var player: CharacterBody2D = main.get_node("Player") as CharacterBody2D
	var map_rid: RID = player.get_world_2d().navigation_map
	var town_half: Vector2 = neighborhood.map_size() * 0.5

	var closed_labels: Array[Label] = []
	var town_labels: Dictionary = {}
	var town_houses: Array[Node] = []
	var town_paths: Dictionary = {}
	_collect_access_nodes(neighborhood, closed_labels, town_labels, town_houses, town_paths)

	_check(closed_labels.is_empty(),
		"Ningun pueblo muestra un cartel CERRADO")

	# El punto de entrada norte, oeste y sur debe cruzar su propio hueco y
	# terminar en la plaza. Un muro sin abertura, una barricada con otro
	# nombre o un gate fisico que corte el paso hacen fallar esta ruta.
	var plaza: Vector2 = neighborhood.plaza_position()
	_check(_path_crosses_wall_gap(
			map_rid,
			Vector2(WALL_GAP_X, -town_half.y - 220.0),
			plaza,
			true,
			-town_half.y + 20.0,
			WALL_GAP_X,
			WALL_GAP_WIDTH),
		"El asentamiento principal se entra caminando por el hueco norte")
	_check(_path_crosses_wall_gap(
			map_rid,
			Vector2(-town_half.x - 220.0, WALL_GAP_WEST_Y),
			plaza,
			false,
			-town_half.x + 20.0,
			WALL_GAP_WEST_Y,
			WALL_GAP_WIDTH),
		"El asentamiento principal se entra caminando por el hueco oeste")
	_check(_path_crosses_wall_gap(
			map_rid,
			Vector2(WALL_GAP_X, town_half.y + 220.0),
			plaza,
			true,
			town_half.y - 20.0,
			WALL_GAP_X,
			WALL_GAP_WIDTH),
		"El asentamiento principal se entra caminando por el hueco sur")

	for town_name in EXPECTED_TOWNS:
		var label: Label = town_labels.get(town_name) as Label
		_check(label != null,
			"%s conserva su identificador de pueblo" % town_name)
		if label == null:
			continue

		var has_center: bool = label.has_meta("town_center")
		var town_center: Variant = label.get_meta("town_center", null) if has_center else null
		_check(has_center and town_center is Vector2,
			"%s conserva una posicion central semantica" % town_name)
		if not (has_center and town_center is Vector2):
			continue

		var house_count: int = _count_town_houses(town_houses, town_name)
		_check(house_count >= 1,
			"%s conserva al menos una casa propia" % town_name)

		var connector: ColorRect = town_paths.get(town_name) as ColorRect
		_check(connector != null,
			"%s conserva un camino propio hacia la red principal" % town_name)
		if connector != null:
			var connector_rect := Rect2(connector.position, connector.size)
			_check(connector_rect.has_point(town_center),
				"El camino de %s alcanza el centro del pueblo" % town_name)
			_check(_connector_reaches_main_road(connector_rect, neighborhood._road_rects),
				"El camino de %s toca una carretera principal" % town_name)

		var nav_target: Vector2 = NavigationServer2D.map_get_closest_point(
			map_rid, town_center)
		_check(town_center.distance_to(nav_target) <= TOWN_NAV_TOLERANCE,
			"El centro de %s pertenece a una zona navegable" % town_name)
		var town_path: PackedVector2Array = NavigationServer2D.map_get_path(
			map_rid, plaza, nav_target, true)
		_check(town_path.size() > 1
				and town_path[town_path.size() - 1].distance_to(nav_target)
					<= NAV_ENDPOINT_TOLERANCE,
			"%s es alcanzable caminando desde el pueblo principal" % town_name)

	await _finish()


func _collect_access_nodes(node: Node, closed_labels: Array[Label],
		town_labels: Dictionary, town_houses: Array[Node],
		town_paths: Dictionary) -> void:
	if node is Label:
		var label := node as Label
		if label.text.to_upper().contains("CERRADO"):
			closed_labels.append(label)
		if EXPECTED_TOWNS.has(label.text):
			town_labels[label.text] = label
	if String(node.name).begins_with("Town_"):
		town_houses.append(node)
	if String(node.name).begins_with("TownPath_") and node is ColorRect:
		var town_name: String = String(node.name).trim_prefix("TownPath_")
		town_paths[town_name] = node as ColorRect
	for child in node.get_children():
		_collect_access_nodes(child, closed_labels, town_labels, town_houses, town_paths)


func _count_town_houses(town_houses: Array[Node], town_name: String) -> int:
	var count: int = 0
	var prefix: String = "Town_" + town_name + "_"
	for node in town_houses:
		if String(node.name).begins_with(prefix):
			count += 1
	return count


func _connector_reaches_main_road(connector: Rect2, roads: Array[Rect2]) -> bool:
	for road in roads:
		if connector.intersects(road):
			return true
	return false


func _path_crosses_wall_gap(map_rid: RID, outside: Vector2, target: Vector2,
		horizontal_wall: bool, wall_axis: float, gap_center: float,
		gap_width: float) -> bool:
	var nav_target: Vector2 = NavigationServer2D.map_get_closest_point(map_rid, target)
	if nav_target.distance_to(target) > MAIN_ROAD_TOLERANCE:
		return false
	var path: PackedVector2Array = NavigationServer2D.map_get_path(
		map_rid, outside, nav_target, true)
	if path.size() < 2:
		return false
	if path[path.size() - 1].distance_to(nav_target) > NAV_ENDPOINT_TOLERANCE:
		return false

	for i in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		if horizontal_wall:
			if (a.y - wall_axis) * (b.y - wall_axis) > 0.0:
				continue
			if is_equal_approx(a.y, b.y):
				continue
			var ratio: float = (wall_axis - a.y) / (b.y - a.y)
			var crossing: Vector2 = a.lerp(b, ratio)
			if absf(crossing.x - gap_center) <= gap_width * 0.5 + 8.0:
				return true
		else:
			if (a.x - wall_axis) * (b.x - wall_axis) > 0.0:
				continue
			if is_equal_approx(a.x, b.x):
				continue
			var ratio: float = (wall_axis - a.x) / (b.x - a.x)
			var crossing: Vector2 = a.lerp(b, ratio)
			if absf(crossing.y - gap_center) <= gap_width * 0.5 + 8.0:
				return true
	return false


func _finish() -> void:
	print("OPEN_SETTLEMENT_TEST failures=%d" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
