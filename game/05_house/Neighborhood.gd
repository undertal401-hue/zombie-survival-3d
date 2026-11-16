class_name Neighborhood
extends Node2D

## Barrio de 10x10 celdas (4800x3000 px): 5x el area del mapa anterior.
## La red vial es asimetrica y por sectores; las casas se colocan dentro de
## celdas libres con separacion suficiente para calles, patios y callejones.

const HOUSE_SCENE: PackedScene = preload("res://05_house/House.tscn")
const LOOT_SCENE: PackedScene = preload("res://04_items/LootContainer.tscn")

enum Zone { NW, NORTH, NE, WEST, CENTER, EAST, SW, SOUTH, SE }

# [x1, y1, x2, y2, ancho, tipo] en lineas de celda (0..10).
# tipo: 0 = avenida, 1 = calle, 2 = callejon.
const ROAD_SEGMENTS := [
	[0, 5, 10, 5, 140.0, 0],   # Avenida Central (este-oeste)
	[7, 0, 7, 10, 140.0, 0],   # Avenida Este (norte-sur)
	[0, 8, 7, 8, 110.0, 1],    # Calle del Mercado
	[3, 5, 3, 10, 110.0, 1],   # Avenida del Parque
	[1, 5, 1, 10, 90.0, 1],    # Los Olmos
	[0, 7, 5, 7, 90.0, 1],
	[0, 9, 5, 9, 90.0, 1],
	[2, 7, 2, 10, 90.0, 1],
	[6, 5, 6, 10, 90.0, 1],
	[5, 7, 5, 10, 90.0, 1],
	[8, 5, 8, 10, 90.0, 1],
	[7, 7, 10, 7, 90.0, 1],
	[7, 9, 10, 9, 90.0, 1],
	[4, 3, 8, 3, 90.0, 1],
	[4, 3, 4, 6, 90.0, 1],
	[0, 2, 4, 2, 90.0, 1],
	[2, 0, 2, 4, 90.0, 1],
	[1, 1, 1, 4, 90.0, 1],
	[1, 1, 4, 1, 90.0, 1],
	[4, 2, 8, 2, 90.0, 1],
	[5, 0, 5, 3, 90.0, 1],
	[7, 1, 10, 1, 110.0, 1],
	[8, 0, 8, 5, 90.0, 1],
	[9, 1, 9, 5, 90.0, 1],
	[4, 0, 4, 2, 90.0, 1],
	[4, 4, 7, 4, 90.0, 1],
	[1, 3, 4, 3, 90.0, 1],
	[1, 4, 4, 4, 90.0, 1],
	[4, 7, 4, 8, 56.0, 2],
	[5, 6, 6, 6, 56.0, 2],
	[6, 2, 6, 3, 56.0, 2],
	[3, 6, 4, 6, 56.0, 2],
	[8, 6, 9, 6, 56.0, 2],
	[8, 2, 9, 2, 56.0, 2],
]

# Celdas reservadas para hitos, plazas y patios.
const OPEN_CELLS := [
	[0, 9, "start"],
	[5, 4, "plaza"],
	[9, 0, "extraction"],
	[5, 8, "market"],
	[2, 7, "courtyard"],
	[1, 2, "tower"],
	[3, 0, "green"],
	[6, 3, "yard"],
	[1, 5, "green"],
	[7, 5, "green"],
	[8, 4, "parking"],
	[3, 8, "green"],
	[6, 7, "yard"],
	[9, 8, "depot_yard"],
	[7, 2, "yard"],
]

const SPECIAL_CELLS := [
	[4, 4, "clinic"],
	[8, 7, "depot"],
	[6, 1, "warehouse"],
]

const FUEL_ZONES := [
	Zone.NW, Zone.NORTH, Zone.NE, Zone.WEST,
	Zone.CENTER, Zone.SW, Zone.SOUTH, Zone.SE,
]

## La comida se reparte por varios sectores para que explorar siga teniendo
## sentido sin convertir cada casa en una despensa.
const FOOD_ZONES := [
	Zone.SW, Zone.SOUTH, Zone.WEST, Zone.CENTER,
	Zone.NORTH, Zone.NE, Zone.SE,
]

@export var columns: int = 10
@export var rows: int = 10
@export var cell_size: Vector2 = Vector2(480, 300)
@export var layout_seed: int = 20261115
@export var house_min_size: Vector2 = Vector2(240, 120)
@export var house_max_size: Vector2 = Vector2(320, 140)
@export var road_color: Color = Color(0.15, 0.15, 0.16)
@export var alley_color: Color = Color(0.11, 0.11, 0.12)
@export var sidewalk_color: Color = Color(0.3, 0.3, 0.3)
@export var alley_sidewalk_color: Color = Color(0.25, 0.25, 0.25)
@export var lawn_color: Color = Color(0.18, 0.28, 0.15)
@export var concrete_color: Color = Color(0.32, 0.32, 0.31)
@export var dirt_color: Color = Color(0.31, 0.25, 0.18)
@export var driveway_color: Color = Color(0.36, 0.35, 0.32)
@export var mark_color: Color = Color(0.65, 0.58, 0.3, 0.85)
@export var tree_color: Color = Color(0.2, 0.42, 0.18)

var _rng: RandomNumberGenerator
var _road_rects: Array[Rect2] = []
var _road_widths: Array[float] = []
var _all_houses: Array[House] = []
var _houses_by_zone: Dictionary = {}
var _special_houses: Dictionary = {}
var _start_position: Vector2
var _extraction_position: Vector2
var _zombie_points: Array[Vector2] = []

func _ready() -> void:
	build()

## (Re)genera el barrio completo de forma determinista.
func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_rng = RandomNumberGenerator.new()
	_rng.seed = layout_seed
	_road_rects.clear()
	_road_widths.clear()
	_all_houses.clear()
	_houses_by_zone.clear()
	_special_houses.clear()
	_zombie_points.clear()
	for zone in range(9):
		_houses_by_zone[zone] = []

	_start_position = _cell_center(0, 9) + Vector2(60.0, 0.0)
	_extraction_position = _cell_center(9, 0) + Vector2(0.0, 20.0)

	_build_ground_patches()
	_build_roads()
	_build_houses()
	_assign_loot()
	_build_plaza()
	_build_market()
	_build_courtyard()
	_build_tower()
	_build_yards()
	_build_barricade()
	_build_streetlights()
	_build_start_camp()
	_build_extraction_lot()
	_build_signs()
	_collect_zombie_spawns()

func map_size() -> Vector2:
	return Vector2(cell_size.x * columns, cell_size.y * rows)

func start_position() -> Vector2:
	return _start_position

func extraction_position() -> Vector2:
	return _extraction_position

func zombie_spawn_points() -> Array[Vector2]:
	return _zombie_points.duplicate()

func plaza_position() -> Vector2:
	return _cell_center(5, 4)

func market_position() -> Vector2:
	return _cell_center(5, 8)

func _cell_center(column: int, row: int) -> Vector2:
	var half: Vector2 = map_size() * 0.5
	return Vector2(
		-half.x + cell_size.x * (column + 0.5),
		-half.y + cell_size.y * (row + 0.5)
	)

func _gx(column: int) -> float:
	return -map_size().x * 0.5 + cell_size.x * column

func _gy(row: int) -> float:
	return -map_size().y * 0.5 + cell_size.y * row

func _build_ground_patches() -> void:
	# Poligono industrial al norte: hormigon desgastado.
	_add_rect(Rect2(Vector2(_gx(4), _gy(0)), Vector2(cell_size.x * 4.0, cell_size.y * 3.0)), concrete_color.darkened(0.16), -9)
	# Deposito y patio de camiones al sureste.
	_add_rect(Rect2(Vector2(_gx(8), _gy(6)), Vector2(cell_size.x * 2.0, cell_size.y * 4.0)), concrete_color.darkened(0.12), -9)
	# Explanada del mercado.
	_add_rect(Rect2(Vector2(_gx(4), _gy(7)), Vector2(cell_size.x * 4.0, cell_size.y * 2.0)), Color(0.24, 0.24, 0.23), -9)

	for entry in OPEN_CELLS:
		var cell := Vector2i(entry[0], entry[1])
		var kind: String = entry[2]
		var color: Color = lawn_color
		match kind:
			"yard", "depot_yard", "parking":
				color = concrete_color.darkened(0.08)
			"courtyard":
				color = dirt_color.darkened(0.08)
			"market":
				color = Color(0.24, 0.24, 0.23)
			_:
				color = lawn_color.darkened(0.06)
		_add_rect(Rect2(_cell_center(cell.x, cell.y) - cell_size * 0.5 + Vector2(8, 8), cell_size - Vector2(16, 16)), color, -9.5)

func _build_roads() -> void:
	for segment in ROAD_SEGMENTS:
		_road_rects.append(_segment_rect(segment))
		_road_widths.append(segment[4])

	for i in range(ROAD_SEGMENTS.size()):
		var segment: Array = ROAD_SEGMENTS[i]
		var extra: float = 8.0 if segment[5] == 2 else 16.0
		var sidewalk: Rect2 = _road_rects[i].grow(extra * 0.5)
		_add_rect(sidewalk, alley_sidewalk_color if segment[5] == 2 else sidewalk_color, -6)

	for i in range(ROAD_SEGMENTS.size()):
		var segment: Array = ROAD_SEGMENTS[i]
		_add_rect(_road_rects[i], alley_color if segment[5] == 2 else road_color, -5)

	for i in range(ROAD_SEGMENTS.size()):
		_add_road_dashes(ROAD_SEGMENTS[i], i)

func _segment_rect(segment: Array) -> Rect2:
	var a := Vector2(_gx(segment[0]), _gy(segment[1]))
	var b := Vector2(_gx(segment[2]), _gy(segment[3]))
	var width: float = segment[4]
	var min_corner := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var max_corner := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(min_corner - Vector2(width, width) * 0.5, (max_corner - min_corner) + Vector2(width, width))

func _add_road_dashes(segment: Array, index: int) -> void:
	if segment[5] == 2:
		return
	var horizontal: bool = segment[1] == segment[3]
	if horizontal:
		var y: float = _gy(segment[1])
		var x: float = minf(_gx(segment[0]), _gx(segment[2])) + 46.0
		var end_x: float = maxf(_gx(segment[0]), _gx(segment[2])) - 46.0
		while x < end_x:
			if not _point_on_other_road(Vector2(x, y), index):
				_add_rect(Rect2(x - 12.0, y - 2.0, 24.0, 4.0), mark_color, -4)
			x += 88.0
	else:
		var x: float = _gx(segment[0])
		var y: float = minf(_gy(segment[1]), _gy(segment[3])) + 46.0
		var end_y: float = maxf(_gy(segment[1]), _gy(segment[3])) - 46.0
		while y < end_y:
			if not _point_on_other_road(Vector2(x, y), index):
				_add_rect(Rect2(x - 2.0, y - 12.0, 4.0, 24.0), mark_color, -4)
			y += 88.0

func _point_on_other_road(point: Vector2, skip: int) -> bool:
	for i in range(_road_rects.size()):
		if i == skip:
			continue
		if _road_rects[i].grow(2.0).has_point(point):
			return true
	return false

func _build_houses() -> void:
	for r in range(rows):
		for c in range(columns):
			var cell := Vector2i(c, r)
			if _open_kind(cell) != "":
				continue

			var kind: String = _special_kind(cell)
			var house := HOUSE_SCENE.instantiate() as House
			house.name = "House_r%dc%d" % [r, c]
			var house_size: Vector2 = _house_size(kind)
			var door_side: int = _pick_door_side(cell, kind)
			var clearance: Vector2 = _cell_clearance(cell)
			var max_offset: Vector2 = (cell_size - house_size) * 0.5 - clearance
			max_offset = max_offset.max(Vector2.ZERO)
			var offset := Vector2(
				_rng.randf_range(-max_offset.x, max_offset.x),
				_rng.randf_range(-max_offset.y, max_offset.y)
			)

			var zone: int = _zone_of(cell)
			house.position = _cell_center(c, r) + offset
			house.size = house_size
			house.door_side = door_side
			_style_house(house, kind, zone)
			add_child(house)

			_add_lot(house, kind, zone)
			_add_driveway(house, cell, door_side)
			_all_houses.append(house)
			_houses_by_zone[zone].append(house)

			if kind != "":
				_special_houses[kind] = house
			if kind == "clinic":
				_decorate_clinic(house)
			elif kind == "depot":
				_decorate_warehouse(house, "DEPÓSITO")
			elif kind == "warehouse":
				_decorate_warehouse(house, "ALMACÉN")

func _house_size(kind: String) -> Vector2:
	match kind:
		"clinic":
			return Vector2(330, 140)
		"depot":
			return Vector2(340, 190)
		"warehouse":
			return Vector2(320, 190)
		_:
			return Vector2(
				_rng.randf_range(house_min_size.x, house_max_size.x),
				_rng.randf_range(house_min_size.y, house_max_size.y)
			).round()

func _style_house(house: House, kind: String, zone: int) -> void:
	match kind:
		"clinic":
			house.wall_color = Color(0.82, 0.82, 0.78)
			house.floor_color = Color(0.42, 0.44, 0.42)
			house.door_color = Color(0.55, 0.16, 0.16)
		"depot", "warehouse":
			house.wall_color = Color(0.42, 0.42, 0.4).lerp(Color(0.36, 0.36, 0.34), _rng.randf())
			house.floor_color = Color(0.3, 0.3, 0.28)
			house.door_color = Color(0.28, 0.3, 0.34)
		_:
			var base: Color = Color(0.55, 0.52, 0.45)
			if zone == Zone.NORTH or zone == Zone.NE or zone == Zone.SE:
				base = Color(0.48, 0.46, 0.42)
			house.wall_color = base.lerp(Color(0.45, 0.4, 0.35), _rng.randf())
			house.floor_color = Color(0.24, 0.22, 0.2).lerp(Color(0.3, 0.26, 0.22), _rng.randf())
			house.door_color = Color(0.35, 0.24, 0.14).lerp(Color(0.42, 0.3, 0.18), _rng.randf())

func _add_lot(house: House, kind: String, zone: int) -> void:
	var margin: float = 10.0
	var color: Color = lawn_color.lerp(Color(0.22, 0.32, 0.16), _rng.randf())
	if kind == "clinic":
		color = Color(0.38, 0.4, 0.38)
	elif kind == "depot" or kind == "warehouse" or zone == Zone.NORTH or zone == Zone.NE or zone == Zone.SE:
		color = concrete_color.darkened(0.06).lerp(concrete_color.darkened(0.16), _rng.randf())
	_add_rect(Rect2(house.position - house.size * 0.5 - Vector2(margin, margin), house.size + Vector2(margin, margin) * 2.0), color, -3.6)

func _add_driveway(house: House, cell: Vector2i, door_side: int) -> void:
	var half: Vector2 = house.size * 0.5
	var front: Vector2 = house.position
	var target: Vector2 = house.position
	var horizontal: bool = door_side == House.DoorSide.LEFT or door_side == House.DoorSide.RIGHT
	var road_width: float = _road_width_at(_side_point(cell, door_side))

	match door_side:
		House.DoorSide.TOP:
			front = house.position - Vector2(0.0, half.y)
			target = Vector2(house.position.x, _gy(cell.y) + (road_width * 0.5 + 8.0 if road_width > 0.0 else 0.0))
		House.DoorSide.BOTTOM:
			front = house.position + Vector2(0.0, half.y)
			target = Vector2(house.position.x, _gy(cell.y + 1) - (road_width * 0.5 + 8.0 if road_width > 0.0 else 0.0))
		House.DoorSide.LEFT:
			front = house.position - Vector2(half.x, 0.0)
			target = Vector2(_gx(cell.x) + (road_width * 0.5 + 8.0 if road_width > 0.0 else 0.0), house.position.y)
		House.DoorSide.RIGHT:
			front = house.position + Vector2(half.x, 0.0)
			target = Vector2(_gx(cell.x + 1) - (road_width * 0.5 + 8.0 if road_width > 0.0 else 0.0), house.position.y)

	if horizontal:
		var left: float = minf(front.x, target.x)
		var width: float = absf(front.x - target.x)
		if width > 2.0:
			_add_rect(Rect2(left, house.position.y - 20.0, width, 40.0), driveway_color, -3.5)
	else:
		var top: float = minf(front.y, target.y)
		var height: float = absf(front.y - target.y)
		if height > 2.0:
			_add_rect(Rect2(house.position.x - 20.0, top, 40.0, height), driveway_color, -3.5)

func _assign_loot() -> void:
	var used: Dictionary = {}
	var specials: Array = _special_houses.values()

	for zone in FUEL_ZONES:
		var candidates: Array = _houses_by_zone[zone]
		var pool: Array = []
		for house in candidates:
			if not specials.has(house):
				pool.append(house)
		if pool.is_empty():
			pool = candidates
		if pool.is_empty():
			continue
		var fuel_house: House = pool[_rng.randi_range(0, pool.size() - 1)]
		_add_loot_container(fuel_house, "combustible", 1, "armario")
		used[fuel_house] = true

	var clinic: House = _find_special_house("clinic")
	if clinic != null:
		_add_loot_container(clinic, "medkit", 2, "botiquín")
		used[clinic] = true

	var depot: House = _find_special_house("depot")
	if depot != null and not used.has(depot):
		_add_loot_container(depot, "combustible", 1, "armario")
		used[depot] = true

	for zone in range(9):
		var pool: Array = []
		for house in _houses_by_zone[zone]:
			if not used.has(house):
				pool.append(house)
		if pool.is_empty():
			continue
		var medkit_house: House = pool[_rng.randi_range(0, pool.size() - 1)]
		_add_loot_container(medkit_house, "medkit", 1, "armario")
		used[medkit_house] = true

	for zone in FOOD_ZONES:
		var pool: Array = []
		for house in _houses_by_zone[zone]:
			if not used.has(house):
				pool.append(house)
		if pool.is_empty():
			continue
		var food_house: House = pool[_rng.randi_range(0, pool.size() - 1)]
		_add_loot_container(food_house, "comida", 1, "despensa")
		used[food_house] = true

	var empty_target: int = 18
	var attempts: int = 0
	while empty_target > 0 and attempts < 200:
		attempts += 1
		var house: House = _all_houses[_rng.randi_range(0, _all_houses.size() - 1)]
		if used.has(house):
			continue
		_add_loot_container(house, "", 0, "armario")
		used[house] = true
		empty_target -= 1

	_add_world_loot(_cell_center(2, 7) + Vector2(0, 30), "medkit", 1, "caja")
	_add_world_loot(_cell_center(9, 8) + Vector2(0, 50), "medkit", 1, "caja")

func _add_loot_container(house: House, item_id: String, amount: int, container_name: String) -> void:
	var loot := LOOT_SCENE.instantiate() as LootContainer
	loot.name = "Loot"
	loot.position = house.back_interior_point()
	loot.item_id = item_id
	loot.amount = amount
	loot.container_name = container_name
	house.add_child(loot)

func _add_world_loot(position: Vector2, item_id: String, amount: int, container_name: String) -> void:
	var loot := LOOT_SCENE.instantiate() as LootContainer
	loot.name = "WorldLoot"
	loot.position = position
	loot.item_id = item_id
	loot.amount = amount
	loot.container_name = container_name
	add_child(loot)

func _find_special_house(kind: String) -> House:
	return _special_houses.get(kind, null) as House

func _build_plaza() -> void:
	var center: Vector2 = _cell_center(5, 4)
	var border := Polygon2D.new()
	border.color = sidewalk_color.darkened(0.18)
	border.polygon = _circle_points(98.0, 32)
	border.position = center
	border.z_index = -4.0
	add_child(border)

	var pad := Polygon2D.new()
	pad.color = sidewalk_color.darkened(0.02)
	pad.polygon = _circle_points(90.0, 32)
	pad.position = center
	pad.z_index = -3.9
	add_child(pad)

	var fountain := StaticBody2D.new()
	fountain.name = "PlazaFountain"
	fountain.position = center

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 22.0
	shape.shape = circle
	fountain.add_child(shape)

	var basin := Polygon2D.new()
	basin.color = Color(0.48, 0.46, 0.4)
	basin.polygon = _circle_points(27.0, 20)
	basin.z_index = 1
	fountain.add_child(basin)

	var water := Polygon2D.new()
	water.color = Color(0.25, 0.5, 0.62)
	water.polygon = _circle_points(19.0, 20)
	water.z_index = 2
	fountain.add_child(water)
	add_child(fountain)

	for offset in [Vector2(-130, -60), Vector2(130, -60), Vector2(-130, 60), Vector2(130, 60)]:
		_add_planter(center + offset)
	_add_label("PLAZA", center + Vector2(-50, -132), Color(0.85, 0.9, 0.75), 18)

func _build_market() -> void:
	var center: Vector2 = _cell_center(5, 8)
	for i in range(6):
		_add_rect(Rect2(center.x - 180.0 + i * 62.0, center.y - 96.0, 3.0, 54.0), Color(0.7, 0.7, 0.65, 0.6), -4.0)
	for offset in [Vector2(-160, -70), Vector2(160, -70), Vector2(-160, 70), Vector2(160, 70)]:
		_add_stall(center + offset)
	_add_label("MERCADO", center + Vector2(-62, 132), Color(0.95, 0.8, 0.45), 18)

func _build_courtyard() -> void:
	var center: Vector2 = _cell_center(2, 7)
	_add_tree(center + Vector2(-140, -70))
	_add_tree(center + Vector2(130, 60))
	_add_planter(center + Vector2(110, -70))
	_add_label("PATIO", center + Vector2(-42, -126), Color(0.8, 0.9, 0.65), 16)

func _build_tower() -> void:
	var center: Vector2 = _cell_center(1, 2)
	var tower := StaticBody2D.new()
	tower.name = "Mirador"
	tower.position = center

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	shape.shape = circle
	tower.add_child(shape)

	var legs := Polygon2D.new()
	legs.color = Color(0.3, 0.28, 0.24)
	legs.polygon = _circle_points(30.0, 8)
	legs.z_index = 1
	tower.add_child(legs)

	var tank := Polygon2D.new()
	tank.color = Color(0.55, 0.52, 0.42)
	tank.polygon = _circle_points(22.0, 18)
	tank.z_index = 2
	tower.add_child(tank)

	var cap := Polygon2D.new()
	cap.color = Color(0.7, 0.66, 0.52)
	cap.polygon = _circle_points(9.0, 12)
	cap.z_index = 3
	tower.add_child(cap)
	add_child(tower)

	_add_tree(center + Vector2(-150, 70))
	_add_tree(center + Vector2(150, -60))
	_add_label("MIRADOR", center + Vector2(-62, -118), Color(0.85, 0.88, 0.7), 16)

func _build_yards() -> void:
	for entry in OPEN_CELLS:
		var cell := Vector2i(entry[0], entry[1])
		var kind: String = entry[2]
		var center: Vector2 = _cell_center(cell.x, cell.y)
		match kind:
			"green":
				_add_tree(center + Vector2(-120, -60))
				_add_tree(center + Vector2(110, 70))
				_add_planter(center + Vector2(120, -60))
			"yard":
				_add_container(center + Vector2(-120, -60), Color(0.35, 0.42, 0.4))
				_add_container(center + Vector2(110, 65), Color(0.42, 0.38, 0.3))
			"depot_yard":
				_add_container(center + Vector2(-130, -60), Color(0.42, 0.3, 0.22))
				_add_container(center + Vector2(120, 60), Color(0.3, 0.36, 0.4))
				_add_label("PATIO DE CAMIONES", center + Vector2(-100, -124), Color(0.8, 0.8, 0.72), 15)
			"parking":
				for i in range(5):
					_add_rect(Rect2(center.x - 170.0 + i * 68.0, center.y - 80.0, 3.0, 70.0), Color(0.7, 0.7, 0.65, 0.5), -4.0)
				_add_parked_car(center + Vector2(-110, 55), Color(0.35, 0.42, 0.5))
				_add_parked_car(center + Vector2(120, -60), Color(0.5, 0.35, 0.3))

func _add_planter(position: Vector2) -> void:
	var planter := StaticBody2D.new()
	planter.position = position

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	planter.add_child(shape)

	var ring := Polygon2D.new()
	ring.color = Color(0.42, 0.38, 0.3)
	ring.polygon = _circle_points(14.0, 14)
	ring.z_index = 1
	planter.add_child(ring)

	var green := Polygon2D.new()
	green.color = tree_color
	green.polygon = _circle_points(8.0, 12)
	green.z_index = 2
	planter.add_child(green)
	add_child(planter)

func _add_tree(position: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = position

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
	shape.shape = circle
	body.add_child(shape)

	var trunk := Polygon2D.new()
	trunk.color = Color(0.3, 0.2, 0.12)
	trunk.polygon = PackedVector2Array([Vector2(-4, -2), Vector2(4, -2), Vector2(4, 10), Vector2(-4, 10)])
	trunk.z_index = 1
	body.add_child(trunk)

	var canopy := Polygon2D.new()
	canopy.color = tree_color
	canopy.polygon = _circle_points(18.0, 14)
	canopy.z_index = 2
	body.add_child(canopy)
	add_child(body)

func _add_stall(position: Vector2) -> void:
	var stall := StaticBody2D.new()
	stall.position = position

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(54.0, 34.0)
	shape.shape = rect
	stall.add_child(shape)

	var table := Polygon2D.new()
	table.color = Color(0.45, 0.35, 0.24)
	table.polygon = PackedVector2Array([Vector2(-27, -8), Vector2(27, -8), Vector2(27, 17), Vector2(-27, 17)])
	table.z_index = 1
	stall.add_child(table)

	var awning := Polygon2D.new()
	awning.color = Color(0.7, 0.25, 0.2) if position.x < 0.0 else Color(0.25, 0.4, 0.55)
	awning.polygon = PackedVector2Array([Vector2(-30, -20), Vector2(30, -20), Vector2(24, -6), Vector2(-24, -6)])
	awning.z_index = 2
	stall.add_child(awning)
	add_child(stall)

func _add_container(position: Vector2, color: Color) -> void:
	var body := StaticBody2D.new()
	body.position = position

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(74.0, 32.0)
	shape.shape = rect
	body.add_child(shape)

	var visual := Polygon2D.new()
	visual.color = color
	visual.polygon = PackedVector2Array([Vector2(-37, -16), Vector2(37, -16), Vector2(37, 16), Vector2(-37, 16)])
	visual.z_index = 1
	body.add_child(visual)

	for i in range(-2, 3):
		var stripe := Polygon2D.new()
		stripe.color = color.darkened(0.25)
		stripe.polygon = PackedVector2Array([
			Vector2(i * 12 - 2, -16), Vector2(i * 12 + 2, -16),
			Vector2(i * 12 + 2, 16), Vector2(i * 12 - 2, 16),
		])
		stripe.z_index = 2
		body.add_child(stripe)
	add_child(body)

func _add_parked_car(position: Vector2, color: Color) -> void:
	var body := StaticBody2D.new()
	body.position = position

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(66.0, 30.0)
	shape.shape = rect
	body.add_child(shape)

	var visual := Polygon2D.new()
	visual.color = color
	visual.polygon = PackedVector2Array([Vector2(-33, -15), Vector2(33, -15), Vector2(33, 15), Vector2(-33, 15)])
	visual.z_index = 1
	body.add_child(visual)

	var roof := Polygon2D.new()
	roof.color = color.darkened(0.22)
	roof.polygon = PackedVector2Array([Vector2(-14, -11), Vector2(14, -11), Vector2(14, 11), Vector2(-14, 11)])
	roof.z_index = 2
	body.add_child(roof)
	add_child(body)

func _build_barricade() -> void:
	var body := StaticBody2D.new()
	body.name = "Barricade"
	body.position = Vector2(600.0, 0.0)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(18.0, 126.0)
	shape.shape = rect
	body.add_child(shape)

	var visual := Polygon2D.new()
	visual.color = Color(0.78, 0.38, 0.12)
	visual.polygon = PackedVector2Array([
		Vector2(-9, -63), Vector2(9, -63), Vector2(9, 63), Vector2(-9, 63),
	])
	body.add_child(visual)

	for i in range(-2, 3):
		var stripe := Polygon2D.new()
		stripe.color = Color(0.12, 0.1, 0.08)
		var sy: float = i * 24.0
		stripe.polygon = PackedVector2Array([
			Vector2(-9, sy - 6), Vector2(9, sy - 12), Vector2(9, sy), Vector2(-9, sy + 6),
		])
		body.add_child(stripe)
	add_child(body)
	_add_label("CERRADO", body.position + Vector2(120, 0), Color(0.95, 0.65, 0.35), 14)

func _build_streetlights() -> void:
	for x in range(-2160, 2401, 480):
		_add_streetlight(Vector2(x, 84))
	for y in range(-1350, 1501, 450):
		_add_streetlight(Vector2(1044, y))

func _add_streetlight(position: Vector2) -> void:
	if _road_width_at(position) > 0.0:
		return
	var pole := Polygon2D.new()
	pole.color = Color(0.2, 0.2, 0.2)
	pole.position = position + Vector2(0, -10)
	pole.polygon = PackedVector2Array([Vector2(-2, -12), Vector2(2, -12), Vector2(2, 12), Vector2(-2, 12)])
	pole.z_index = 3
	add_child(pole)

	var lamp := Polygon2D.new()
	lamp.color = Color(0.95, 0.88, 0.5)
	lamp.position = position + Vector2(0, -24)
	lamp.polygon = PackedVector2Array([Vector2(-6, -4), Vector2(6, -4), Vector2(4, 4), Vector2(-4, 4)])
	lamp.z_index = 4
	add_child(lamp)

func _build_start_camp() -> void:
	var center: Vector2 = _cell_center(0, 9)
	_add_rect(Rect2(center - Vector2(200, 130), Vector2(400, 260)), dirt_color, -9.2)

	var tent := StaticBody2D.new()
	tent.name = "Tent"
	tent.position = center + Vector2(-140, 95)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(70.0, 50.0)
	shape.shape = rect
	tent.add_child(shape)

	var canvas := Polygon2D.new()
	canvas.color = Color(0.42, 0.5, 0.32)
	canvas.polygon = PackedVector2Array([Vector2(-35, 25), Vector2(0, -25), Vector2(35, 25)])
	canvas.z_index = 1
	tent.add_child(canvas)
	add_child(tent)

	var fire := Polygon2D.new()
	fire.color = Color(0.9, 0.45, 0.12)
	fire.position = center + Vector2(-20, 82)
	fire.polygon = _circle_points(9.0, 8)
	fire.z_index = 2
	add_child(fire)

	var start: Vector2 = _start_position
	_add_rect(Rect2(start.x - 20.0, _gy(9), 40.0, start.y - _gy(9) + 10.0), dirt_color.lightened(0.06), -3.4)
	_add_rect(Rect2(_gx(0), start.y - 20.0, start.x - _gx(0) + 20.0, 40.0), dirt_color.lightened(0.06), -3.4)
	_add_label("CAMPAMENTO", center + Vector2(-20, -128), Color(0.9, 0.82, 0.6), 16)

func _build_extraction_lot() -> void:
	var center: Vector2 = _extraction_position
	_add_rect(Rect2(center - Vector2(170, 100), Vector2(340, 200)), Color(0.2, 0.21, 0.2), -4.2)
	var hazard := Color(0.85, 0.7, 0.2, 0.8)
	_add_rect(Rect2(center.x - 170.0, center.y - 100.0, 340.0, 4.0), hazard, -4.1)
	_add_rect(Rect2(center.x - 170.0, center.y + 96.0, 340.0, 4.0), hazard, -4.1)
	_add_rect(Rect2(center.x - 170.0, center.y - 100.0, 4.0, 200.0), hazard, -4.1)
	_add_rect(Rect2(center.x + 166.0, center.y - 100.0, 4.0, 200.0), hazard, -4.1)
	_add_rect(Rect2(center.x - 40.0, center.y + 90.0, 80.0, _gy(1) - (center.y + 90.0)), road_color, -4.3)

func _build_signs() -> void:
	_add_label("LOS OLMOS", _cell_center(3, 8) + Vector2(0, -108), Color(0.82, 0.9, 0.7), 18)
	_add_label("POLÍGONO NORTE", _cell_center(6, 3) + Vector2(0, -108), Color(0.8, 0.82, 0.78), 18)
	_add_label("BARRIO DEL MERCADO", _cell_center(6, 8) + Vector2(0, -120), Color(0.9, 0.82, 0.6), 16)

	var sign_position: Vector2 = _start_position + Vector2(-80, -96)
	var post := Polygon2D.new()
	post.color = Color(0.32, 0.24, 0.15)
	post.position = sign_position + Vector2(0, 24)
	post.polygon = PackedVector2Array([Vector2(-3, -24), Vector2(3, -24), Vector2(3, 24), Vector2(-3, 24)])
	post.z_index = 3
	add_child(post)
	_add_label("EXTRACCIÓN: NE", sign_position, Color(1.0, 0.9, 0.5), 14)

func _collect_zombie_spawns() -> void:
	var candidates: Array[Vector2] = []
	for segment in ROAD_SEGMENTS:
		var a := Vector2(_gx(segment[0]), _gy(segment[1]))
		var b := Vector2(_gx(segment[2]), _gy(segment[3]))
		var steps: int = maxi(1, int(a.distance_to(b) / 380.0))
		for step in range(steps + 1):
			var point: Vector2 = a.lerp(b, float(step) / float(steps))
			var margin := Vector2(70.0, 70.0)
			var half: Vector2 = map_size() * 0.5 - margin
			point = point.clamp(-half, half)
			if point.distance_to(_start_position) < 560.0:
				continue
			if point.distance_to(_extraction_position) < 380.0:
				continue
			if _has_near(candidates, point, 100.0):
				continue
			candidates.append(point)

	if candidates.is_empty():
		return

	var chosen: Array[Vector2] = []
	var first: Vector2 = candidates[0]
	var best_distance: float = -1.0
	for point in candidates:
		var distance: float = point.distance_to(_start_position)
		if distance > best_distance:
			best_distance = distance
			first = point
	chosen.append(first)

	var target_count: int = 26
	while chosen.size() < target_count and chosen.size() < candidates.size():
		var best_point: Vector2 = candidates[0]
		var best_score: float = -1.0
		for point in candidates:
			if chosen.has(point):
				continue
			var min_distance: float = INF
			for other in chosen:
				min_distance = minf(min_distance, point.distance_to(other))
			var score: float = minf(min_distance, point.distance_to(_start_position) * 0.6)
			if score > best_score:
				best_score = score
				best_point = point
		chosen.append(best_point)
	_zombie_points = chosen

func _has_near(points: Array[Vector2], point: Vector2, radius: float) -> bool:
	for other in points:
		if point.distance_to(other) < radius:
			return true
	return false

func _open_kind(cell: Vector2i) -> String:
	for entry in OPEN_CELLS:
		if entry[0] == cell.x and entry[1] == cell.y:
			return entry[2]
	return ""

func _special_kind(cell: Vector2i) -> String:
	for entry in SPECIAL_CELLS:
		if entry[0] == cell.x and entry[1] == cell.y:
			return entry[2]
	return ""

func _zone_of(cell: Vector2i) -> int:
	var row_band: int = 0 if cell.y <= 3 else (1 if cell.y <= 5 else 2)
	var col_band: int = 0 if cell.x <= 3 else (1 if cell.x <= 7 else 2)
	return row_band * 3 + col_band

func _side_point(cell: Vector2i, side: int) -> Vector2:
	var center: Vector2 = _cell_center(cell.x, cell.y)
	match side:
		House.DoorSide.TOP:
			return center + Vector2(0.0, -cell_size.y * 0.5)
		House.DoorSide.BOTTOM:
			return center + Vector2(0.0, cell_size.y * 0.5)
		House.DoorSide.LEFT:
			return center + Vector2(-cell_size.x * 0.5, 0.0)
		_:
			return center + Vector2(cell_size.x * 0.5, 0.0)

func _road_width_at(point: Vector2) -> float:
	for i in range(_road_rects.size()):
		if _road_rects[i].has_point(point):
			return _road_widths[i]
	return 0.0

func _side_clearance(cell: Vector2i, side: int) -> float:
	var road_width: float = _road_width_at(_side_point(cell, side))
	if road_width > 0.0:
		return road_width * 0.5 + 18.0
	return 26.0

func _cell_clearance(cell: Vector2i) -> Vector2:
	var x: float = maxf(
		_side_clearance(cell, House.DoorSide.LEFT),
		_side_clearance(cell, House.DoorSide.RIGHT)
	)
	var y: float = maxf(
		_side_clearance(cell, House.DoorSide.TOP),
		_side_clearance(cell, House.DoorSide.BOTTOM)
	)
	return Vector2(x, y)

func _pick_door_side(cell: Vector2i, kind: String) -> int:
	match kind:
		"clinic":
			return House.DoorSide.RIGHT
		"depot":
			return House.DoorSide.TOP
		"warehouse":
			return House.DoorSide.BOTTOM

	var options: Array[int] = []
	for side in [House.DoorSide.TOP, House.DoorSide.BOTTOM, House.DoorSide.LEFT, House.DoorSide.RIGHT]:
		if _road_width_at(_side_point(cell, side)) > 0.0:
			options.append(side)
	if options.is_empty():
		return House.DoorSide.BOTTOM if _rng.randf() < 0.5 else House.DoorSide.TOP
	return options[_rng.randi_range(0, options.size() - 1)]

func _decorate_clinic(house: House) -> void:
	var half: Vector2 = house.size * 0.5
	_add_cross(house, Vector2(0.0, -half.y + 5.0), 8.0, Color(0.9, 0.2, 0.2))
	var label := Label.new()
	label.text = "CLÍNICA"
	label.position = Vector2(-40.0, -half.y - 26.0)
	label.size = Vector2(80.0, 20.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	label.z_index = 4
	house.add_child(label)

func _decorate_warehouse(house: House, text: String) -> void:
	var half: Vector2 = house.size * 0.5
	var label := Label.new()
	label.text = text
	label.position = Vector2(-70.0, half.y + 8.0 if house.door_side == House.DoorSide.TOP else -half.y - 26.0)
	label.size = Vector2(140.0, 20.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.5))
	label.z_index = 4
	house.add_child(label)

func _add_cross(parent: Node2D, position: Vector2, size: float, color: Color) -> void:
	var horizontal := ColorRect.new()
	horizontal.color = color
	horizontal.size = Vector2(size * 2.0, size * 0.6)
	horizontal.position = position - horizontal.size * 0.5
	horizontal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal.z_index = 2
	parent.add_child(horizontal)

	var vertical := ColorRect.new()
	vertical.color = color
	vertical.size = Vector2(size * 0.6, size * 2.0)
	vertical.position = position - vertical.size * 0.5
	vertical.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical.z_index = 2
	parent.add_child(vertical)

func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _add_label(text: String, position: Vector2, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	var width: float = maxf(180.0, float(text.length()) * float(font_size) * 0.62)
	label.position = position - Vector2(width * 0.5, 0.0)
	label.size = Vector2(width, 26.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.03))
	label.add_theme_constant_override("outline_size", 3)
	label.z_index = 5
	add_child(label)

func _add_rect(rect: Rect2, color: Color, z: int) -> void:
	var visual := ColorRect.new()
	visual.position = rect.position
	visual.size = rect.size
	visual.color = color
	visual.z_index = z
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(visual)
