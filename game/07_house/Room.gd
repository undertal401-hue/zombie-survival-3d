class_name Room


extends Node3D
## Habitacion modular: suelo, paredes, techo, puertas.
## Accesible globalmente via `Room` (class_name).

@export var size: Vector2i = Vector2i(4, 4)
@export var grid_pos: Vector2i = Vector2i(0, 0)
@export var wall_height: float = 3.0
@export var wall_thickness: float = 0.2

var floor: MeshInstance3D
var walls: Array[MeshInstance3D] = []
var doors: Array[Node3D] = []


func build() -> void:
	_build_floor()
	_build_walls()
	global_position = Vector3(grid_pos.x * 8.0, 0.0, grid_pos.y * 8.0)


func _build_floor() -> void:
	floor = MeshInstance3D.new()
	floor.name = "Floor"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(size.x * 4.0, 0.1, size.y * 4.0)
	floor.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.18, 0.2)
	floor.material_override = mat
	floor.position = Vector3(0.0, 0.05, 0.0)
	add_child(floor)
	var static_body := StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	(collision.shape as BoxShape3D).size = Vector3(size.x * 4.0, 0.1, size.y * 4.0)
	static_body.add_child(collision)
	static_body.position = Vector3(0.0, 0.05, 0.0)
	add_child(static_body)


func _build_walls() -> void:
	var half_x: float = size.x * 2.0
	var half_y: float = size.y * 2.0
	var positions: Array[Vector3] = [
		Vector3(0.0, wall_height * 0.5, -half_y),  # norte
		Vector3(0.0, wall_height * 0.5, half_y),   # sur
		Vector3(-half_x, wall_height * 0.5, 0.0),  # oeste
		Vector3(half_x, wall_height * 0.5, 0.0),   # este
	]
	var sizes: Array[Vector3] = [
		Vector3(size.x * 4.0 + wall_thickness * 2.0, wall_height, wall_thickness),
		Vector3(size.x * 4.0 + wall_thickness * 2.0, wall_height, wall_thickness),
		Vector3(wall_thickness, wall_height, size.y * 4.0),
		Vector3(wall_thickness, wall_height, size.y * 4.0),
	]
	var rotations: Array[Vector3] = [
		Vector3.ZERO, Vector3.ZERO, Vector3(0.0, PI * 0.5, 0.0), Vector3(0.0, PI * 0.5, 0.0)
	]
	for i: int in 4:
		var wall: MeshInstance3D = MeshInstance3D.new()
		wall.name = "Wall_%d" % i
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = sizes[i]
		wall.mesh = mesh
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.2, 0.18)
		wall.material_override = mat
		wall.position = positions[i]
		wall.rotation = rotations[i]
		add_child(wall)
		walls.append(wall)
		var static_body := StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = BoxShape3D.new()
		(collision.shape as BoxShape3D).size = sizes[i]
		static_body.add_child(collision)
		static_body.position = positions[i]
		static_body.rotation = rotations[i]
		add_child(static_body)


## Centro de la habitacion.
func get_center() -> Vector3:
	return global_position + Vector3(0.0, 1.0, 0.0)


## Posicion aleatoria dentro de la habitacion.
func get_random_point() -> Vector3:
	var half_x: float = size.x * 2.0 - 0.5
	var half_y: float = size.y * 2.0 - 0.5
	return global_position + Vector3(randf_range(-half_x, half_x), 0.1, randf_range(-half_y, half_y))
