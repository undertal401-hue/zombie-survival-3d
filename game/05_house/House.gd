class_name House
extends Node2D

## Una casa del barrio: suelo + 4 muros con un unico hueco de puerta
## (con marco y umbral). Todo es configurable por export para poder
## modificarla/mejorarla sin tocar el resto del juego. Llama a build()
## si cambias props en runtime.

enum DoorSide { TOP, BOTTOM, LEFT, RIGHT }

@export var size: Vector2 = Vector2(300, 150):
	set(value):
		size = value
		if is_inside_tree():
			build()
@export var wall_thickness: float = 10.0:
	set(value):
		wall_thickness = value
		if is_inside_tree():
			build()
@export var door_width: float = 60.0:
	set(value):
		door_width = value
		if is_inside_tree():
			build()
@export var door_side: DoorSide = DoorSide.BOTTOM:
	set(value):
		door_side = value
		if is_inside_tree():
			build()
@export var wall_color: Color = Color(0.55, 0.52, 0.45):
	set(value):
		wall_color = value
		if is_inside_tree():
			build()
@export var floor_color: Color = Color(0.24, 0.22, 0.2):
	set(value):
		floor_color = value
		if is_inside_tree():
			build()
@export var door_color: Color = Color(0.35, 0.24, 0.14):
	set(value):
		door_color = value
		if is_inside_tree():
			build()

func _ready() -> void:
	add_to_group("houses")
	build()

## (Re)construye la casa entera a partir de los exports actuales.
func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_add_floor()

	var half: Vector2 = size * 0.5
	var t: float = wall_thickness

	if door_side == DoorSide.TOP or door_side == DoorSide.BOTTOM:
		var gap: float = minf(door_width, size.x - t * 2.0)
		var segment: float = (size.x - gap) * 0.5
		if door_side == DoorSide.TOP:
			_add_wall(Rect2(-half.x, -half.y, segment, t))
			_add_wall(Rect2(half.x - segment, -half.y, segment, t))
			_add_wall(Rect2(-half.x, half.y - t, size.x, t))
		else:
			_add_wall(Rect2(-half.x, -half.y, size.x, t))
			_add_wall(Rect2(-half.x, half.y - t, segment, t))
			_add_wall(Rect2(half.x - segment, half.y - t, segment, t))
		_add_wall(Rect2(-half.x, -half.y, t, size.y))
		_add_wall(Rect2(half.x - t, -half.y, t, size.y))
		_add_door_frame(gap)
	else:
		var gap: float = minf(door_width, size.y - t * 2.0)
		var segment: float = (size.y - gap) * 0.5
		if door_side == DoorSide.LEFT:
			_add_wall(Rect2(-half.x, -half.y, t, segment))
			_add_wall(Rect2(-half.x, half.y - segment, t, segment))
			_add_wall(Rect2(half.x - t, -half.y, t, size.y))
		else:
			_add_wall(Rect2(-half.x, -half.y, t, size.y))
			_add_wall(Rect2(half.x - t, -half.y, t, segment))
			_add_wall(Rect2(half.x - t, half.y - segment, t, segment))
		_add_wall(Rect2(-half.x, -half.y, size.x, t))
		_add_wall(Rect2(-half.x, half.y - t, size.x, t))
		_add_door_frame(gap)

## Marco y umbral de la unica puerta (solo visual, no bloquea el paso).
func _add_door_frame(gap: float) -> void:
	var half: Vector2 = size * 0.5
	var t: float = wall_thickness
	var post: float = 8.0
	var trim: Color = door_color.darkened(0.2)

	if door_side == DoorSide.TOP or door_side == DoorSide.BOTTOM:
		var y: float = -half.y if door_side == DoorSide.TOP else half.y - t
		var edge_y: float = y - 2.0 if door_side == DoorSide.TOP else y + t - 2.0
		_add_visual_rect(Rect2(-gap * 0.5, y, post, t), door_color)
		_add_visual_rect(Rect2(gap * 0.5 - post, y, post, t), door_color)
		_add_visual_rect(Rect2(-gap * 0.5 + post, edge_y, gap - post * 2.0, 4.0), trim)
	else:
		var x: float = -half.x if door_side == DoorSide.LEFT else half.x - t
		var edge_x: float = x - 2.0 if door_side == DoorSide.LEFT else x + t - 2.0
		_add_visual_rect(Rect2(x, -gap * 0.5, t, post), door_color)
		_add_visual_rect(Rect2(x, gap * 0.5 - post, t, post), door_color)
		_add_visual_rect(Rect2(edge_x, -gap * 0.5 + post, 4.0, gap - post * 2.0), trim)

func _add_visual_rect(rect: Rect2, color: Color, z: int = 0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var visual := Polygon2D.new()
	visual.color = color
	visual.position = rect.position + rect.size * 0.5
	visual.z_index = z

	var hx: float = rect.size.x * 0.5
	var hy: float = rect.size.y * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy),
		Vector2(hx, hy), Vector2(-hx, hy),
	])
	add_child(visual)

func _add_floor() -> void:
	var floor_rect := ColorRect.new()
	floor_rect.color = floor_color
	floor_rect.position = -size * 0.5
	floor_rect.size = size
	floor_rect.z_index = -1
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor_rect)

func _add_wall(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var body := StaticBody2D.new()
	body.position = rect.position + rect.size * 0.5

	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = rect.size
	shape.shape = rect_shape
	body.add_child(shape)

	var visual := Polygon2D.new()
	visual.color = wall_color
	var hx: float = rect.size.x * 0.5
	var hy: float = rect.size.y * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy),
		Vector2(hx, hy), Vector2(-hx, hy),
	])
	body.add_child(visual)

	add_child(body)
