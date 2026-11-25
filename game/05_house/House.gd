class_name House
extends Node2D

## Una casa del barrio con interiores de 2–3 plantas.
## Floor0 = exterior (doorway abierto); Floor1/Floor2 = interiores (doorway cerrado).
## Solo la planta activa es visible + colisionable.

enum DoorSide { TOP, BOTTOM, LEFT, RIGHT }
enum FloorIndex { FLOOR_0 = 0, FLOOR_1 = 1, FLOOR_2 = 2 }

const NUM_FLOORS: int = 3
## Capas de colisión por contrato:
## outside=3 (bit 0+1), floor0=1 (bit 0), upper=4 (bit 2), player=5 (bit 0+2)
const LAYER_OUTSIDE: int = 3
const LAYER_FLOOR0: int = 1
const LAYER_UPPER: int = 4
const MASK_PLAYER: int = 5

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
## Planta activa (0 = exterior, 1/2 = interiores). Se cambia por entrada/salida.
@export var active_floor: int = 0:
	set(value):
		active_floor = clampi(value, 0, NUM_FLOORS - 1)
		if is_inside_tree():
			_set_floor_visibility(active_floor)

var _floors: Array[Node2D] = []

func _ready() -> void:
	add_to_group("houses")
	build()
	_set_floor_visibility(active_floor)

## (Re)construye la casa completa con 3 plantas.
func build() -> void:
	# Limpiar hijos existentes
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_floors.clear()

	# Crear las 3 plantas como nodos hijos directos en (0,0)
	for i in range(NUM_FLOORS):
		var floor: Node2D = Node2D.new()
		floor.name = "Floor%d" % i
		floor.position = Vector2.ZERO
		floor.rotation = 0.0
		floor.scale = Vector2.ONE
		add_child(floor)
		_floors.append(floor)

	# Construir cada planta
	_build_floor(0, true)   # Floor0: exterior, doorway abierto
	_build_floor(1, false)  # Floor1: interior, doorway cerrado
	_build_floor(2, false)  # Floor2: interior, doorway cerrado

	# Escaleras entre plantas (misma posición local en cada piso)
	_build_stairs()

	# Ventanas (solo visuales, en todas las plantas)
	_add_windows_to_all_floors()

## Construye una planta individual.
## @param floor_index  0, 1 o 2
## @param is_exterior  true solo para Floor0 (doorway abierto)
func _build_floor(floor_index: int, is_exterior: bool) -> void:
	var floor: Node2D = _floors[floor_index]
	var half: Vector2 = size * 0.5
	var t: float = wall_thickness

	# Suelo de la planta
	_add_floor_to(floor, floor_index)

	# Determinar qué lado es el doorway
	var doorway_side: DoorSide = door_side

	# Construir los 4 lados: solo dividir el lado del doorway si es exterior
	# TOP
	if doorway_side == DoorSide.TOP and is_exterior:
		var gap: float = minf(door_width, size.x - t * 2.0)
		var segment: float = (size.x - gap) * 0.5
		_add_wall_to(floor, Rect2(-half.x, -half.y, segment, t), floor_index, is_exterior)
		_add_wall_to(floor, Rect2(half.x - segment, -half.y, segment, t), floor_index, is_exterior)
		_add_door_frame_to(floor, gap)
	else:
		_add_wall_to(floor, Rect2(-half.x, -half.y, size.x, t), floor_index, is_exterior)

	# BOTTOM
	if doorway_side == DoorSide.BOTTOM and is_exterior:
		var gap: float = minf(door_width, size.x - t * 2.0)
		var segment: float = (size.x - gap) * 0.5
		_add_wall_to(floor, Rect2(-half.x, half.y - t, segment, t), floor_index, is_exterior)
		_add_wall_to(floor, Rect2(half.x - segment, half.y - t, segment, t), floor_index, is_exterior)
		_add_door_frame_to(floor, gap)
	else:
		_add_wall_to(floor, Rect2(-half.x, half.y - t, size.x, t), floor_index, is_exterior)

	# LEFT
	if doorway_side == DoorSide.LEFT and is_exterior:
		var gap: float = minf(door_width, size.y - t * 2.0)
		var segment: float = (size.y - gap) * 0.5
		_add_wall_to(floor, Rect2(-half.x, -half.y, t, segment), floor_index, is_exterior)
		_add_wall_to(floor, Rect2(-half.x, half.y - segment, t, segment), floor_index, is_exterior)
		_add_door_frame_to(floor, gap)
	else:
		_add_wall_to(floor, Rect2(-half.x, -half.y, t, size.y), floor_index, is_exterior)

	# RIGHT
	if doorway_side == DoorSide.RIGHT and is_exterior:
		var gap: float = minf(door_width, size.y - t * 2.0)
		var segment: float = (size.y - gap) * 0.5
		_add_wall_to(floor, Rect2(half.x - t, -half.y, t, segment), floor_index, is_exterior)
		_add_wall_to(floor, Rect2(half.x - t, half.y - segment, t, segment), floor_index, is_exterior)
		_add_door_frame_to(floor, gap)
	else:
		_add_wall_to(floor, Rect2(half.x - t, -half.y, t, size.y), floor_index, is_exterior)

## Añade el suelo (ColorRect) a una planta.
func _add_floor_to(floor: Node2D, floor_index: int) -> void:
	var floor_rect := ColorRect.new()
	floor_rect.name = "FloorSurface"
	floor_rect.color = floor_color
	floor_rect.position = -size * 0.5
	floor_rect.size = size
	floor_rect.z_index = -1
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor.add_child(floor_rect)

## Añade un muro (StaticBody2D + CollisionShape2D + visual + occluder) a una planta.
## @param floor_index  índice de la planta (0, 1, 2)
## @param is_exterior  true para Floor0: capa 1; false para upper: capa 4
func _add_wall_to(floor: Node2D, rect: Rect2, floor_index: int, is_exterior: bool) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var body := StaticBody2D.new()
	body.name = "Wall"
	body.position = rect.position + rect.size * 0.5

	# Capa de colisión según planta
	body.collision_layer = LAYER_FLOOR0 if is_exterior else LAYER_UPPER
	# Máscara: player (5) + outside (3) para Floor0; solo player (5) para upper
	body.collision_mask = MASK_PLAYER if is_exterior else MASK_PLAYER

	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = rect.size
	shape.shape = rect_shape
	body.add_child(shape)

	var visual := Polygon2D.new()
	visual.name = "WallVisual"
	visual.color = wall_color
	visual.position = Vector2.ZERO
	var vhx: float = rect.size.x * 0.5
	var vhy: float = rect.size.y * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-vhx, -vhy), Vector2(vhx, -vhy),
		Vector2(vhx, vhy), Vector2(-vhx, vhy),
	])
	body.add_child(visual)

	# Oclusor de luz por segmento (igual que antes)
	var occluder := LightOccluder2D.new()
	occluder.name = "WallOccluder"
	var occ_poly := OccluderPolygon2D.new()
	occ_poly.polygon = PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
	])
	occluder.occluder = occ_poly
	occluder.position = Vector2.ZERO
	floor.add_child(occluder)

	# Guardar capa base para poder restaurarla al activar la planta
	body.set_meta("base_collision_layer", LAYER_FLOOR0 if is_exterior else LAYER_UPPER)

	floor.add_child(body)

## Marco y umbral de la puerta (solo visual, en Floor0).
func _add_door_frame_to(floor: Node2D, gap: float) -> void:
	var half: Vector2 = size * 0.5
	var t: float = wall_thickness
	var post: float = 8.0
	var trim: Color = door_color.darkened(0.2)

	if door_side == DoorSide.TOP or door_side == DoorSide.BOTTOM:
		var y: float = -half.y if door_side == DoorSide.TOP else half.y - t
		var edge_y: float = y - 2.0 if door_side == DoorSide.TOP else y + t - 2.0
		_add_visual_rect_to(floor, Rect2(-gap * 0.5, y, post, t), door_color)
		_add_visual_rect_to(floor, Rect2(gap * 0.5 - post, y, post, t), door_color)
		_add_visual_rect_to(floor, Rect2(-gap * 0.5 + post, edge_y, gap - post * 2.0, 4.0), trim)
	else:
		var x: float = -half.x if door_side == DoorSide.LEFT else half.x - t
		var edge_x: float = x - 2.0 if door_side == DoorSide.LEFT else x + t - 2.0
		_add_visual_rect_to(floor, Rect2(x, -gap * 0.5, t, post), door_color)
		_add_visual_rect_to(floor, Rect2(x, gap * 0.5 - post, t, post), door_color)
		_add_visual_rect_to(floor, Rect2(edge_x, -gap * 0.5 + post, 4.0, gap - post * 2.0), trim)

func _add_visual_rect_to(floor: Node2D, rect: Rect2, color: Color, z: int = 0) -> void:
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
	floor.add_child(visual)

## Ventanas en todas las plantas (solo visuales).
func _add_windows_to_all_floors() -> void:
	var half: Vector2 = size * 0.5
	var t: float = wall_thickness
	var glass: Color = Color(0.55, 0.72, 0.78)
	var window_length: float = 30.0
	var window_depth: float = 6.0

	for floor_index in range(NUM_FLOORS):
		var floor: Node2D = _floors[floor_index]
		for side in [-1.0, 1.0]:
			var x: float = half.x * 0.5 * side
			_add_visual_rect_to(floor, Rect2(x - window_length * 0.5, -half.y + t * 0.5 - window_depth * 0.5, window_length, window_depth), glass, 1)
			_add_visual_rect_to(floor, Rect2(x - window_length * 0.5, half.y - t * 0.5 - window_depth * 0.5, window_length, window_depth), glass, 1)
			var y: float = half.y * 0.5 * side
			_add_visual_rect_to(floor, Rect2(-half.x + t * 0.5 - window_depth * 0.5, y - window_length * 0.5, window_depth, window_length), glass, 1)
			_add_visual_rect_to(floor, Rect2(half.x - t * 0.5 - window_depth * 0.5, y - window_length * 0.5, window_depth, window_length), glass, 1)

## Escaleras entre Floor0<->Floor1 y Floor1<->Floor2.
## Se colocan en la misma posición local en cada planta.
func _build_stairs() -> void:
	var stairs_pos: Vector2 = _stairs_position()

	# Floor0 -> Floor1 (Area2D en Floor0 y Floor1, misma posición local)
	_create_stairs_pair(_floors[0], _floors[1], stairs_pos, "Stairs_0_1")
	# Floor1 -> Floor2
	_create_stairs_pair(_floors[1], _floors[2], stairs_pos, "Stairs_1_2")

func _stairs_position() -> Vector2:
	match door_side:
		DoorSide.TOP:
			return Vector2(0.0, size.y * 0.5 - 40.0)
		DoorSide.BOTTOM:
			return Vector2(0.0, -size.y * 0.5 + 40.0)
		DoorSide.LEFT:
			return Vector2(size.x * 0.5 - 40.0, 0.0)
		DoorSide.RIGHT:
			return Vector2(-size.x * 0.5 + 40.0, 0.0)
		_:
			return Vector2.ZERO

func _create_stairs_pair(floor_a: Node2D, floor_b: Node2D, pos: Vector2, name: String) -> void:
	# Area2D en planta A (subida) - hijo directo de floor_a
	var area_a: Area2D = Area2D.new()
	area_a.name = name + "_Up"
	area_a.position = pos
	area_a.collision_layer = 0
	area_a.collision_mask = MASK_PLAYER
	area_a.monitoring = false  # Se activa con _set_floor_areas_monitoring
	var shape_a: CollisionShape2D = CollisionShape2D.new()
	var rect_a: RectangleShape2D = RectangleShape2D.new()
	rect_a.size = Vector2(32.0, 32.0)
	shape_a.shape = rect_a
	area_a.add_child(shape_a)
	area_a.body_entered.connect(_on_stairs_body_entered.bind(floor_a, floor_b, 1))
	floor_a.add_child(area_a)

	# Visual en planta A
	var visual_a: Polygon2D = Polygon2D.new()
	visual_a.name = name + "_Visual"
	visual_a.color = Color(0.3, 0.25, 0.2)
	visual_a.position = pos
	visual_a.z_index = 2
	var hx: float = 16.0
	var hy: float = 16.0
	visual_a.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy),
		Vector2(hx, hy), Vector2(-hx, hy),
	])
	floor_a.add_child(visual_a)

	# Area2D en planta B (bajada) - hijo directo de floor_b, misma posición local
	var area_b: Area2D = Area2D.new()
	area_b.name = name + "_Down"
	area_b.position = pos
	area_b.collision_layer = 0
	area_b.collision_mask = MASK_PLAYER
	area_b.monitoring = false
	var shape_b: CollisionShape2D = CollisionShape2D.new()
	var rect_b: RectangleShape2D = RectangleShape2D.new()
	rect_b.size = Vector2(32.0, 32.0)
	shape_b.shape = rect_b
	area_b.add_child(shape_b)
	area_b.body_entered.connect(_on_stairs_body_entered.bind(floor_b, floor_a, -1))
	floor_b.add_child(area_b)

	# Visual en planta B
	var visual_b: Polygon2D = Polygon2D.new()
	visual_b.name = name + "_Visual"
	visual_b.color = Color(0.3, 0.25, 0.2)
	visual_b.position = pos
	visual_b.z_index = 2
	visual_b.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy),
		Vector2(hx, hy), Vector2(-hx, hy),
	])
	floor_b.add_child(visual_b)

func _on_stairs_body_entered(body: Node2D, from_floor: Node2D, to_floor: Node2D, direction: int) -> void:
	if not body.is_in_group("player"):
		return
	var house: House = self
	var current_index: int = _floors.find(from_floor)
	var target_index: int = _floors.find(to_floor)
	if current_index >= 0 and target_index >= 0:
		house.set_active_floor(target_index)

## Cambia la planta activa: muestra solo esa, oculta las otras.
func set_active_floor(floor_index: int) -> void:
	active_floor = clampi(floor_index, 0, NUM_FLOORS - 1)
	_set_floor_visibility(active_floor)

func _set_floor_visibility(active_index: int) -> void:
	for i in range(NUM_FLOORS):
		var floor: Node2D = _floors[i]
		var is_active: bool = (i == active_index)
		floor.visible = is_active
		# Colisión: solo planta activa tiene cuerpos con collision_layer > 0
		_set_floor_collision_enabled(floor, is_active)
		# Area2D (escaleras, loot): solo planta activa monitoring=true
		_set_floor_areas_monitoring(floor, is_active)

func _set_floor_collision_enabled(floor: Node2D, enabled: bool) -> void:
	for child in floor.get_children():
		if child is StaticBody2D:
			var base_layer: int = child.get_meta("base_collision_layer", 0)
			child.collision_layer = base_layer if enabled else 0
			child.collision_mask = MASK_PLAYER if enabled else 0

func _set_floor_areas_monitoring(floor: Node2D, enabled: bool) -> void:
	for child in floor.get_children():
		if child is Area2D:
			child.monitoring = enabled
			child.monitorable = enabled
		# Recursivo para hijos de hijos
		_set_areas_monitoring_recursive(child, enabled)

func _set_areas_monitoring_recursive(node: Node, enabled: bool) -> void:
	for child in node.get_children():
		if child is Area2D:
			child.monitoring = enabled
			child.monitorable = enabled
		_set_areas_monitoring_recursive(child, enabled)

## Punto interior en la pared opuesta a la puerta (para loot en Floor0).
func back_interior_point() -> Vector2:
	match door_side:
		DoorSide.TOP:
			return Vector2(0.0, size.y * 0.5 - 28.0)
		DoorSide.BOTTOM:
			return Vector2(0.0, -size.y * 0.5 + 28.0)
		DoorSide.LEFT:
			return Vector2(size.x * 0.5 - 30.0, 0.0)
		_:
			return Vector2(-size.x * 0.5 + 30.0, 0.0)

## API para tests: obtener nodo de planta.
func get_floor(index: int) -> Node2D:
	if index >= 0 and index < _floors.size():
		return _floors[index]
	return null

## API para tests: planta activa actual.
func get_active_floor() -> int:
	return active_floor

## API para tests: lado de la puerta.
func get_door_side() -> int:
	return int(door_side)