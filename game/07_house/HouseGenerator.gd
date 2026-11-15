class_name HouseGenerator


extends Node3D
## Generador procedural de la casa (escenario principal).
##
## Construye habitaciones y pasillos conectados en tiempo de ejecucion,
## coloca puntos de spawn y el baño (safe zone). Data-driven via
## RoomLayout en 16_data/HouseLayout.tres.
## Accesible globalmente via `HouseGenerator` (class_name).

const GRID_SIZE: float = 4.0
const WALL_HEIGHT: float = 3.0
const WALL_THICKNESS: float = 0.2

var layout: RoomLayout = RoomLayout.new()
var rooms: Array[Room] = []
var corridors: Array[Corridor] = []
var bathroom: Bathroom = null
var spawn_points: Array[Node3D] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_layout()
	generate()


## Carga el layout desde recurso de datos.
func _load_layout() -> void:
	var res: Resource = load("res://16_data/HouseLayout.tres")
	if res != null and res is RoomLayout:
		layout = res
	else:
		layout = RoomLayout.default_layout()


## Genera toda la casa: habitaciones, pasillos, baño, spawn points.
func generate() -> void:
	_clear()
	_build_rooms()
	_build_corridors()
	_place_bathroom()
	_place_spawn_points()
	_build_navmesh()
	EventBus.ui_notification.emit("Casa generada: %d habitaciones" % rooms.size(), &"info")


## Limpia instancias anteriores.
func _clear() -> void:
	for room: Room in rooms:
		room.queue_free()
	for corridor: Corridor in corridors:
		corridor.queue_free()
	if bathroom != null:
		bathroom.queue_free()
	for point: Node3D in spawn_points:
		point.queue_free()
	rooms.clear()
	corridors.clear()
	spawn_points.clear()
	bathroom = null


## Construye las habitaciones base (5 minimo).
func _build_rooms() -> void:
	var count: int = maxi(layout.room_count, 5)
	for i: int in count:
		var room: Room = Room.new()
		room.name = "Room_%d" % i
		room.size = layout.room_sizes[_rng.randi_range(0, layout.room_sizes.size() - 1)]
		room.grid_pos = Vector2i(_rng.randi_range(-3, 3), _rng.randi_range(-3, 3))
		add_child(room)
		room.build()
		rooms.append(room)


## Conecta habitaciones con pasillos (8 minimo).
func _build_corridors() -> void:
	if rooms.size() < 2:
		return
	var connected: Array[int] = [0]
	var target_count: int = maxi(layout.corridor_count, 8)
	while corridors.size() < target_count and connected.size() < rooms.size():
		var from_idx: int = connected[_rng.randi_range(0, connected.size() - 1)]
		var to_idx: int = _rng.randi_range(0, rooms.size() - 1)
		if to_idx in connected:
			continue
		var corridor: Corridor = Corridor.new()
		corridor.name = "Corridor_%d" % corridors.size()
		corridor.link(rooms[from_idx], rooms[to_idx])
		add_child(corridor)
		corridor.build()
		corridors.append(corridor)
		connected.append(to_idx)


## Coloca el baño (safe zone) en una habitacion aleatoria.
func _place_bathroom() -> void:
	if rooms.is_empty():
		return
	var target: Room = rooms[_rng.randi_range(0, rooms.size() - 1)]
	bathroom = Bathroom.new()
	bathroom.name = "Bathroom"
	add_child(bathroom)
	bathroom.setup_in_room(target)
	EventBus.ui_notification.emit("Zona segura: Baño", &"info")


## Crea puntos de spawn de zombies en pasillos y bordes.
func _place_spawn_points() -> void:
	var count: int = 12
	for i: int in count:
		var point: Node3D = Node3D.new()
		point.name = "SpawnPoint_%d" % i
		point.add_to_group("spawn_points")
		add_child(point)
		if corridors.is_empty():
			point.global_position = Vector3(_rng.randi_range(-20, 20), 0.1, _rng.randi_range(-20, 20))
		else:
			var corridor: Corridor = corridors[_rng.randi_range(0, corridors.size() - 1)]
			point.global_position = corridor.get_random_point()
		spawn_points.append(point)


## Construye NavMesh para pathfinding si se usa NavigationServer.
func _build_navmesh() -> void:
	var nav: NavigationRegion3D = get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if nav == null:
		nav = NavigationRegion3D.new()
		nav.name = "NavigationRegion3D"
		add_child(nav)
	# El NavigationServer lo construye en background; aqui solo aseguramos la region.


## Obtiene la posicion del jugador para spawn inicial.
func get_player_start() -> Vector3:
	if bathroom != null:
		return bathroom.get_safe_position()
	for room: Room in rooms:
		if room != null:
			return room.get_center()
	return Vector3.ZERO


## Obtiene la posicion del baño (safe zone).
func get_bathroom_position() -> Vector3:
	return bathroom.global_position if bathroom != null else Vector3.ZERO


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	pass # Replace with function body.
