class_name Neighborhood
extends Node2D

## Traza el barrio completo: rejilla de calles + casas colocadas de forma
## determinista. Cada casa es independiente (05_house/House.gd) y se puede
## modificar sin tocar este generador.

const HOUSE_SCENE: PackedScene = preload("res://05_house/House.tscn")
const LOOT_SCENE: PackedScene = preload("res://04_items/LootContainer.tscn")

const FUEL_HOUSES := [0, 3, 7, 12, 15, 19]
const MEDKIT_HOUSES := [1, 2, 5, 8, 10, 13, 16, 18]
const CLINIC_HOUSE := 2

@export var columns: int = 5
@export var rows: int = 4
@export var cell_size: Vector2 = Vector2(480, 300)
@export var road_width: float = 110.0
@export var layout_seed: int = 1337
@export var house_min_size: Vector2 = Vector2(240, 120)
@export var house_max_size: Vector2 = Vector2(320, 150)
@export var road_color: Color = Color(0.15, 0.15, 0.16)
@export var sidewalk_color: Color = Color(0.3, 0.3, 0.3)
@export var lawn_color: Color = Color(0.18, 0.28, 0.15)
@export var driveway_color: Color = Color(0.36, 0.35, 0.32)
@export var mark_color: Color = Color(0.65, 0.58, 0.3, 0.85)
@export var tree_color: Color = Color(0.2, 0.42, 0.18)

func _ready() -> void:
	build()

## (Re)genera calles, casas y puntos de interes a partir de los exports.
func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed

	_build_roads()
	_build_houses(rng)
	_build_plaza()
	_build_barricade()
	_build_streetlights()

func map_size() -> Vector2:
	return Vector2(cell_size.x * columns, cell_size.y * rows)

func _cell_center(column: int, row: int) -> Vector2:
	var half: Vector2 = map_size() * 0.5
	return Vector2(
		-half.x + cell_size.x * (column + 0.5),
		-half.y + cell_size.y * (row + 0.5)
	)

func _build_roads() -> void:
	var total: Vector2 = map_size()
	var half: Vector2 = total * 0.5
	var sidewalk_width: float = road_width + 16.0

	for c in range(1, columns):
		var x: float = -half.x + cell_size.x * c
		_add_rect(Rect2(x - sidewalk_width * 0.5, -half.y, sidewalk_width, total.y), sidewalk_color, -6)
		_add_rect(Rect2(x - road_width * 0.5, -half.y, road_width, total.y), road_color, -5)
		_add_vertical_dashes(x, total)

	for r in range(1, rows):
		var y: float = -half.y + cell_size.y * r
		_add_rect(Rect2(-half.x, y - sidewalk_width * 0.5, total.x, sidewalk_width), sidewalk_color, -6)
		_add_rect(Rect2(-half.x, y - road_width * 0.5, total.x, road_width), road_color, -5)
		_add_horizontal_dashes(y, total)

func _build_houses(rng: RandomNumberGenerator) -> void:
	var house_index: int = 0

	for r in range(rows):
		for c in range(columns):
			var house := HOUSE_SCENE.instantiate() as House
			house.name = "House_r%dc%d" % [r, c]
			var door_side: int = House.DoorSide.BOTTOM if r < rows / 2 else House.DoorSide.TOP
			var house_size := Vector2(
				rng.randf_range(house_min_size.x, house_max_size.x),
				rng.randf_range(house_min_size.y, house_max_size.y)
			).round()
			var max_offset := Vector2(
				maxf(0.0, cell_size.x * 0.5 - house_size.x * 0.5 - road_width * 0.5 - 14.0),
				maxf(0.0, cell_size.y * 0.5 - house_size.y * 0.5 - road_width * 0.5 - 14.0)
			)
			var offset := Vector2(
				rng.randf_range(-max_offset.x, max_offset.x),
				rng.randf_range(-max_offset.y, max_offset.y)
			)
			offset.y += -8.0 if door_side == House.DoorSide.BOTTOM else 8.0
			offset.y = clampf(offset.y, -max_offset.y, max_offset.y)

			house.position = _cell_center(c, r) + offset
			house.size = house_size
			house.door_side = door_side
			house.wall_color = Color(0.55, 0.52, 0.45).lerp(Color(0.45, 0.4, 0.35), rng.randf())
			house.floor_color = Color(0.24, 0.22, 0.2).lerp(Color(0.3, 0.26, 0.22), rng.randf())
			add_child(house)

			_add_yard(house, rng)
			_add_driveway(house, r)
			_add_loot(house, house_index)
			if house_index == CLINIC_HOUSE:
				_decorate_clinic(house)
			house_index += 1

func _add_yard(house: House, rng: RandomNumberGenerator) -> void:
	var margin: float = 10.0
	var tint: Color = lawn_color.lerp(Color(0.22, 0.32, 0.16), rng.randf())
	_add_rect(Rect2(house.position - house.size * 0.5 - Vector2(margin, margin), house.size + Vector2(margin, margin) * 2.0), tint, -3.6)

func _add_driveway(house: House, row: int) -> void:
	var half_cell: Vector2 = cell_size * 0.5
	var road_y: float = _cell_center(0, row).y + (half_cell.y if house.door_side == House.DoorSide.BOTTOM else -half_cell.y)
	var front_y: float = house.position.y + (house.size.y * 0.5 if house.door_side == House.DoorSide.BOTTOM else -house.size.y * 0.5)
	var top: float = minf(front_y, road_y)
	var height: float = absf(road_y - front_y)
	_add_rect(Rect2(house.position.x - 22.0, top, 44.0, height), driveway_color, -3.5)

func _add_loot(house: House, index: int) -> void:
	var loot := LOOT_SCENE.instantiate() as LootContainer
	loot.name = "Loot"
	loot.position = house.back_interior_point()
	if index in FUEL_HOUSES:
		loot.item_id = "combustible"
		loot.amount = 1
	elif index in MEDKIT_HOUSES:
		loot.item_id = "medkit"
		loot.amount = 2 if index == CLINIC_HOUSE else 1
		loot.container_name = "botiquín" if index == CLINIC_HOUSE else "armario"
	else:
		loot.item_id = ""
		loot.amount = 0
	house.add_child(loot)

func _build_plaza() -> void:
	var center := Vector2.ZERO

	var pad := Polygon2D.new()
	pad.color = sidewalk_color.darkened(0.08)
	pad.polygon = _circle_points(52.0, 24)
	pad.z_index = -3.9
	add_child(pad)

	var planter := StaticBody2D.new()
	planter.position = center

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	planter.add_child(shape)

	var ring := Polygon2D.new()
	ring.color = Color(0.42, 0.38, 0.3)
	ring.polygon = _circle_points(18.0, 16)
	ring.z_index = 1
	planter.add_child(ring)

	var green := Polygon2D.new()
	green.color = tree_color
	green.polygon = _circle_points(11.0, 14)
	green.z_index = 2
	planter.add_child(green)

	add_child(planter)
	_add_label("PLAZA", center + Vector2(-70.0, -82.0), Color(0.85, 0.9, 0.75), 14)

func _build_barricade() -> void:
	var body := StaticBody2D.new()
	body.name = "Barricade"
	body.position = Vector2(240.0, 450.0)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(126.0, 18.0)
	shape.shape = rect
	body.add_child(shape)

	var visual := Polygon2D.new()
	visual.color = Color(0.78, 0.38, 0.12)
	visual.polygon = PackedVector2Array([
		Vector2(-63, -9), Vector2(63, -9), Vector2(63, 9), Vector2(-63, 9),
	])
	body.add_child(visual)

	for i in range(-2, 3):
		var stripe := Polygon2D.new()
		stripe.color = Color(0.12, 0.1, 0.08)
		var sx: float = i * 24.0
		stripe.polygon = PackedVector2Array([
			Vector2(sx - 6, -9), Vector2(sx + 6, -9), Vector2(sx + 12, 9), Vector2(sx, 9),
		])
		body.add_child(stripe)

	add_child(body)
	_add_label("CERRADO", body.position + Vector2(-32.0, -34.0), Color(0.95, 0.65, 0.35), 14)

func _build_streetlights() -> void:
	for pos in [Vector2(-720, -300), Vector2(720, -300), Vector2(-720, 300)]:
		var pole := Polygon2D.new()
		pole.color = Color(0.2, 0.2, 0.2)
		pole.position = pos + Vector2(0, -10)
		pole.polygon = PackedVector2Array([Vector2(-2, -12), Vector2(2, -12), Vector2(2, 12), Vector2(-2, 12)])
		pole.z_index = 3
		add_child(pole)

		var lamp := Polygon2D.new()
		lamp.color = Color(0.95, 0.88, 0.5)
		lamp.position = pos + Vector2(0, -24)
		lamp.polygon = PackedVector2Array([Vector2(-6, -4), Vector2(6, -4), Vector2(4, 4), Vector2(-4, 4)])
		lamp.z_index = 4
		add_child(lamp)

func _decorate_clinic(house: House) -> void:
	var half: Vector2 = house.size * 0.5
	_add_cross(house, Vector2(half.x * 0.55, half.y - 4.0), 8.0, Color(0.9, 0.2, 0.2))
	var label := Label.new()
	label.text = "CLÍNICA"
	label.position = Vector2(-34.0, half.y + 12.0)
	label.size = Vector2(68.0, 20.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	label.z_index = 4
	house.add_child(label)

func _add_cross(parent: Node2D, pos: Vector2, size: float, color: Color) -> void:
	var horizontal := ColorRect.new()
	horizontal.color = color
	horizontal.size = Vector2(size * 2.0, size * 0.6)
	horizontal.position = pos - horizontal.size * 0.5
	horizontal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal.z_index = 2
	parent.add_child(horizontal)

	var vertical := ColorRect.new()
	vertical.color = color
	vertical.size = Vector2(size * 0.6, size * 2.0)
	vertical.position = pos - vertical.size * 0.5
	vertical.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical.z_index = 2
	parent.add_child(vertical)

func _add_vertical_dashes(x: float, total: Vector2) -> void:
	var y: float = -total.y * 0.5 + 34.0
	while y < total.y * 0.5 - 34.0:
		_add_rect(Rect2(x - 2.0, y, 4.0, 24.0), mark_color, -4)
		y += 82.0

func _add_horizontal_dashes(y: float, total: Vector2) -> void:
	var x: float = -total.x * 0.5 + 34.0
	while x < total.x * 0.5 - 34.0:
		_add_rect(Rect2(x, y - 2.0, 24.0, 4.0), mark_color, -4)
		x += 82.0

func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _add_label(text: String, pos: Vector2, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = Vector2(140.0, 24.0)
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
