class_name House
extends Node2D

## Una casa del barrio: suelo + 4 muros con un hueco de puerta.
## Todo es configurable por export para poder modificarla/mejorarla
## sin tocar el resto del juego. Llama a build() si cambias props
## en runtime.

enum DoorSide { TOP, BOTTOM, LEFT, RIGHT }

@export var size: Vector2 = Vector2(320, 160):
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
	var gap: float = minf(door_width, size.x - t * 2.0)

	if door_side == DoorSide.TOP or door_side == DoorSide.BOTTOM:
		var segment: float = (size.x - gap) * 0.5
		var y: float = -half.y if door_side == DoorSide.TOP else half.y - t
		_add_wall(Rect2(-half.x, y, segment, t))
		_add_wall(Rect2(half.x - segment, y, segment, t))
	else:
		_add_wall(Rect2(-half.x, -half.y, size.x, t))
		_add_wall(Rect2(-half.x, half.y - t, size.x, t))

	if door_side == DoorSide.LEFT or door_side == DoorSide.RIGHT:
		var segment: float = (size.y - gap) * 0.5
		var x: float = -half.x if door_side == DoorSide.LEFT else half.x - t
		_add_wall(Rect2(x, -half.y, t, segment))
		_add_wall(Rect2(x, half.y - segment, t, segment))
	else:
		_add_wall(Rect2(-half.x, -half.y, t, size.y))
		_add_wall(Rect2(half.x - t, -half.y, t, size.y))

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
