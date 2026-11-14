class_name Corridor


extends Node3D
## Pasillo que conecta dos habitaciones.
## Accesible globalmente via `Corridor` (class_name).

const WIDTH: float = 2.0
const HEIGHT: float = 3.0

var from_room: Room
var to_room: Room
var floor: MeshInstance3D
var walls: Array[MeshInstance3D] = []


func link(p_from: Room, p_to: Room) -> void:
	from_room = p_from
	to_room = p_to


func build() -> void:
	var from_center: Vector3 = from_room.get_center()
	var to_center: Vector3 = to_room.get_center()
	var direction: Vector3 = to_center - from_center
	direction.y = 0.0
	var length: float = direction.length()
	if length < 1.0:
		return
	var mid: Vector3 = (from_center + to_center) * 0.5
	global_position = mid
	look_at(to_center)
	_build_floor(length)
	_build_walls(length)


func _build_floor(length: float) -> void:
	floor = MeshInstance3D.new()
	floor.name = "Floor"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(length, 0.1, WIDTH)
	floor.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.18)
	floor.material_override = mat
	floor.position = Vector3(0.0, 0.05, 0.0)
	add_child(floor)
	var static_body := StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	(collision.shape as BoxShape3D).size = Vector3(length, 0.1, WIDTH)
	static_body.add_child(collision)
	static_body.position = Vector3(0.0, 0.05, 0.0)
	add_child(static_body)


func _build_walls(length: float) -> void:
	var wall_size: Vector3 = Vector3(length, HEIGHT, 0.15)
	var positions: Array[Vector3] = [
		Vector3(0.0, HEIGHT * 0.5, WIDTH * 0.5 + 0.075),
		Vector3(0.0, HEIGHT * 0.5, -WIDTH * 0.5 - 0.075),
	]
	for i: int in 2:
		var wall: MeshInstance3D = MeshInstance3D.new()
		wall.name = "Wall_%d" % i
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = wall_size
		wall.mesh = mesh
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.18, 0.16)
		wall.material_override = mat
		wall.position = positions[i]
		add_child(wall)
		walls.append(wall)
		var static_body := StaticBody3D.new()
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = BoxShape3D.new()
		(collision.shape as BoxShape3D).size = wall_size
		static_body.add_child(collision)
		static_body.position = positions[i]
		add_child(static_body)


## Punto aleatorio dentro del pasillo.
func get_random_point() -> Vector3:
	var from_center: Vector3 = from_room.get_center()
	var to_center: Vector3 = to_room.get_center()
	var direction: Vector3 = to_center - from_center
	direction.y = 0.0
	var length: float = direction.length()
	if length < 1.0:
		return global_position
	var t: float = randf()
	return from_center + direction * t + Vector3(0.0, 0.1, 0.0)
