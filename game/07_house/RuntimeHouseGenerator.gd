class_name RuntimeHouseGenerator
extends Node3D
## Generador de casa procedural en runtime (basado en algoritmos de Atrium).
## Sin @tool: funciona tanto en editor como en juego exportado.

const MIN_GRID: int = 3
const MAX_GRID: int = 8

@export var seed: int = 0
@export var grid_size: Vector2i = Vector2i(3, 3)
@export var room_size: Vector3 = Vector3(8, 3.5, 8)
@export var floor_count: int = 2
@export var branch_count: int = 4
@export var critical_path_min: int = 3
@export var wall_thickness: float = 0.2
@export var door_width: float = 1.6
@export var door_height: float = 2.3
@export var wall_material: StandardMaterial3D
@export var floor_material: StandardMaterial3D
@export var ceiling_material: StandardMaterial3D

var _rng: RandomNumberGenerator
var _rooms: Array[Dictionary] = []
var _connections: Array[Dictionary] = []


func _ready() -> void:
	if seed == 0:
		seed = Time.get_ticks_msec()
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed


## Genera la casa completa y la añade como hijo.
func generate() -> void:
	_clear()
	_generate_layout()
	_build_geometry()


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_rooms.clear()
	_connections.clear()


## Genera el layout (habitaciones y conexiones) usando algoritmos tipo Atrium.
func _generate_layout() -> void:
	var grid_w: int = grid_size.x
	var grid_h: int = grid_size.y
	var target_rooms: int = critical_path_min + branch_count
	var max_cells: int = grid_w * grid_h
	target_rooms = clampi(target_rooms, 2, max_cells)
	
	# 1. Generar camino crítico (entrada -> salida)
	var path: Array[Vector2i] = _generate_critical_path(grid_w, grid_h, critical_path_min)
	if path.is_empty():
		return
	
	# 2. Añadir ramas
	_generate_branches(path, branch_count, grid_w, grid_h)
	
	# 3. Crear datos de habitaciones
	_create_room_data(path)
	
	# 4. Crear conexiones
	_create_connections()


func _generate_critical_path(grid_w: int, grid_h: int, min_len: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var occupied: Dictionary = {}
	
	# Empezar en una esquina aleatoria
	var start_x: int = _rng.randi_range(0, grid_w - 1)
	var start_y: int = _rng.randi_range(0, grid_h - 1)
	var current: Vector2i = Vector2i(start_x, start_y)
	path.append(current)
	occupied[str(current)] = true
	
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]
	
	while path.size() < min_len:
		var shuffled: Array[Vector2i] = directions.duplicate()
		# Fisher-Yates shuffle manual
		for i in range(shuffled.size() - 1, 0, -1):
			var j: int = _rng.randi_range(0, i)
			var tmp: Vector2i = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = tmp
		
		var found: bool = false
		for dir in shuffled:
			var next: Vector2i = current + dir
			if next.x < 0 or next.x >= grid_w or next.y < 0 or next.y >= grid_h:
				continue
			if occupied.has(str(next)):
				continue
			
			current = next
			path.append(current)
			occupied[str(current)] = true
			found = true
			break
		
		if not found:
			break
	
	return path


func _generate_branches(main_path: Array[Vector2i], count: int, grid_w: int, grid_h: int) -> void:
	var occupied: Dictionary = {}
	for p in main_path:
		occupied[str(p)] = true
	
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]
	var added: int = 0
	
	while added < count:
		var candidates: Array[Dictionary] = []
		
		for i in main_path.size():
			var cell: Vector2i = main_path[i]
			for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + dir
				if neighbor.x < 0 or neighbor.x >= grid_w or neighbor.y < 0 or neighbor.y >= grid_h:
					continue
				if occupied.has(str(neighbor)):
					continue
				candidates.append({"from": cell, "new": neighbor, "dir": dir})
		
		if candidates.is_empty():
			break
		
		var chosen: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]
		var new_cell: Vector2i = chosen["new"]
		
		# Añadir a la ruta principal (extendiendo)
		main_path.append(new_cell)
		occupied[str(new_cell)] = true
		added += 1


func _create_room_data(path: Array[Vector2i]) -> void:
	for i in path.size():
		var cell: Vector2i = path[i]
		var room: Dictionary = {
			"cell": cell,
			"index": i,
			"role": _get_role(i, path.size()),
			"world_pos": Vector3(cell.x * room_size.x, 0, cell.y * room_size.z),
			"connections": []
		}
		_rooms.append(room)


func _get_role(index: int, total: int) -> int:
	if index == 0:
		return 0  # ENTRANCE
	elif index == total - 1:
		return 2  # EXIT
	return 1  # MAIN


func _create_connections() -> void:
	for i in _rooms.size() - 1:
		var a: Dictionary = _rooms[i]
		var b: Dictionary = _rooms[i + 1]
		var delta: Vector2i = b["cell"] - a["cell"]
		var wall_a: int = _wall_for_delta(delta)
		var wall_b: int = _wall_for_delta(-delta)
		
		a["connections"].append({"to": b["index"], "wall": wall_a})
		b["connections"].append({"to": a["index"], "wall": wall_b})
		
		_connections.append({
			"from": i,
			"to": i + 1,
			"wall_a": wall_a,
			"wall_b": wall_b
		})


func _wall_for_delta(delta: Vector2i) -> int:
	# 0=FRONT(+Z), 1=RIGHT(+X), 2=BACK(-Z), 3=LEFT(-X)
	if delta.x == 1:
		return 1  # RIGHT
	if delta.x == -1:
		return 3  # LEFT
	if delta.y == 1:
		return 2  # BACK
	return 0  # FRONT


## Rotación simple alrededor del eje Y.
static func _rotate_y(v: Vector3, angle: float) -> Vector3:
	var ca: float = cos(angle)
	var sa: float = sin(angle)
	return Vector3(
		v.x * ca - v.z * sin(angle),
		v.y,
		v.x * sin(angle) + v.z * ca
	)


## Construye la geometría 3D real.
func _build_geometry() -> void:
	if wall_material == null:
		wall_material = StandardMaterial3D.new()
		wall_material.albedo_color = Color(0.65, 0.67, 0.59, 1)
	if floor_material == null:
		floor_material = StandardMaterial3D.new()
		floor_material.albedo_color = Color(0.32, 0.23, 0.16, 1)
	if ceiling_material == null:
		ceiling_material = StandardMaterial3D.new()
		ceiling_material.albedo_color = Color(0.82, 0.80, 0.72, 1)
	
	for floor_idx in range(floor_count):
		var floor_y: float = floor_idx * room_size.y
		_build_floor_rooms(floor_y)
		if floor_idx < floor_count - 1:
			_build_stairs(floor_y + room_size.y)


func _build_floor_rooms(floor_y: float) -> void:
	for room_data in _rooms:
		var pos: Vector3 = room_data["world_pos"]
		pos.y = floor_y
		_build_room(pos, room_data)


func _build_room(pos: Vector3, data: Dictionary) -> void:
	var room_node: Node3D = Node3D.new()
	room_node.name = "Room_%d" % data["index"]
	room_node.global_position = pos
	add_child(room_node)
	
	var size: Vector3 = room_size
	var half_x: float = size.x * 0.5
	var half_z: float = size.z * 0.5
	var half_y: float = size.y * 0.5
	
	# Suelo
	_build_box(room_node, Vector3(size.x, 0.2, size.z), pos + Vector3(0, -half_y + 0.1, 0), floor_material, true)
	# Techo
	_build_box(room_node, Vector3(size.x, 0.2, size.z), pos + Vector3(0, half_y - 0.1, 0), ceiling_material, true)
	
	# Paredes con huecos para puertas
	var walls: Array[Dictionary] = [
		{"wall": 0, "pos": Vector3(0, 0, -half_z), "rot": Vector3(0, 0, 0), "size": Vector3(size.x - wall_thickness*2, size.y, wall_thickness), "door_wall": 0},  # FRONT
		{"wall": 1, "pos": Vector3(half_x, 0, 0), "rot": Vector3(0, PI/2, 0), "size": Vector3(size.z - wall_thickness*2, size.y, wall_thickness), "door_wall": 1},  # RIGHT
		{"wall": 2, "pos": Vector3(0, 0, half_z), "rot": Vector3(0, PI, 0), "size": Vector3(size.x - wall_thickness*2, size.y, wall_thickness), "door_wall": 2},  # BACK
		{"wall": 3, "pos": Vector3(-half_x, 0, 0), "rot": Vector3(0, -PI/2, 0), "size": Vector3(size.z - wall_thickness*2, size.y, wall_thickness), "door_wall": 3},  # LEFT
	]
	
	var connected_walls: Array[int] = []
	for conn in data["connections"]:
		connected_walls.append(conn["wall"])
	
	for wall_data in walls:
		var wall_id: int = wall_data["wall"]
		var has_door: bool = wall_id in connected_walls
		var rot_y: float = wall_data["rot"].y
		
		if has_door:
			# Pared con hueco para puerta (3 partes: izquierda, dintel, derecha)
			var door_w: float = door_width
			var wall_w: float = wall_data["size"].x
			var left_w: float = (wall_w - door_w) * 0.5
			
			# Rotación del offset local
			var offset_left: Vector3 = _rotate_y(Vector3(-wall_w*0.5 + left_w*0.5, 0, 0), wall_data["rot"].y)
			var offset_lintel: Vector3 = _rotate_y(Vector3(0, size.y*0.5 - 0.6, 0), wall_data["rot"].y)
			var offset_right: Vector3 = _rotate_y(Vector3(wall_w*0.5 - left_w*0.5, 0, 0), wall_data["rot"].y)
			
			if left_w > 0.1:
				_build_box(room_node, Vector3(left_w, size.y, wall_thickness),
					pos + wall_data["pos"] + _rotate_y(Vector3(-wall_w*0.5 + left_w*0.5, 0, 0), wall_data["rot"].y),
					wall_material, true)
			
			# Dintel sobre la puerta
			_build_box(room_node, Vector3(door_w, 1.2, wall_thickness),
				pos + wall_data["pos"] + _rotate_y(Vector3(0, size.y*0.5 - 0.6, 0), wall_data["rot"].y),
				wall_material, true)
			
			if left_w > 0.1:
				_build_box(room_node, Vector3(left_w, size.y, wall_thickness),
					pos + wall_data["pos"] + _rotate_y(Vector3(wall_w*0.5 - left_w*0.5, 0, 0), wall_data["rot"].y),
					wall_material, true)
		else:
			# Pared completa
			_build_box(room_node, wall_data["size"],
				pos + wall_data["pos"],
				wall_material, true)


func _build_box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D, with_collision: bool) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	
	if with_collision:
		var static_body: StaticBody3D = StaticBody3D.new()
		static_body.collision_layer = 4  # environment
		static_body.collision_mask = 15
		var col_shape: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = size
		col_shape.shape = box_shape
		static_body.add_child(col_shape)
		static_body.position = pos
		parent.add_child(static_body)


func _build_stairs(start_y: float) -> void:
	# Escalera simple entre plantas
	var stairs: Node3D = Node3D.new()
	stairs.name = "Stairs"
	add_child(stairs)
	
	var step_h: float = room_size.y / 12.0
	var step_d: float = room_size.x / 12.0
	
	for i in range(12):
		var step: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(room_size.x * 0.8, step_h, step_d)
		step.mesh = box
		step.material_override = floor_material
		step.position = Vector3(0, start_y + i * step_h - room_size.y * 0.5, -room_size.z * 0.4 + i * step_d)
		stairs.add_child(step)
		
		var static_body: StaticBody3D = StaticBody3D.new()
		static_body.collision_layer = 4
		static_body.collision_mask = 15
		var col: CollisionShape3D = CollisionShape3D.new()
		var bshape: BoxShape3D = BoxShape3D.new()
		bshape.size = Vector3(room_size.x * 0.8, step_h, step_d)
		col.shape = bshape
		static_body.add_child(col)
		static_body.position = step.position
		stairs.add_child(static_body)
	
	# Barandilla
	var rail: MeshInstance3D = MeshInstance3D.new()
	var rail_box: BoxMesh = BoxMesh.new()
	rail_box.size = Vector3(0.1, 1.0, room_size.x * 0.8)
	rail.mesh = rail_box
	rail.material_override = wall_material
	rail.position = Vector3(room_size.x * 0.4, start_y + room_size.y * 0.5, -room_size.z * 0.4)
	add_child(rail)
	
	var rail_col: StaticBody3D = StaticBody3D.new()
	rail_col.collision_layer = 4
	rail_col.collision_mask = 15
	var rail_shape: CollisionShape3D = CollisionShape3D.new()
	var rail_box_shape: BoxShape3D = BoxShape3D.new()
	rail_box_shape.size = Vector3(0.1, 1.0, room_size.x * 0.8)
	rail_shape.shape = rail_box_shape
	rail_col.add_child(rail_shape)
	rail_col.position = rail.position
	add_child(rail_col)
