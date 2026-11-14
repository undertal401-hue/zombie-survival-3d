class_name ZombieSpawner
extends Node3D

const ZombieTypes := preload("res://03_zombies/ZombieTypes.gd")
const WaveScaling := preload("res://06_waves/WaveScaling.gd")
const WaveComposition := preload("res://06_waves/WaveComposition.gd")
const WeightedPicker := preload("res://06_waves/WeightedPicker.gd")
const WaveData := preload("res://06_waves/WaveData.gd")
const ZombiePool := preload("res://03_zombies/ZombiePool.gd")
const ObjectPool := preload("res://01_core/ObjectPool.gd")
const Currency := preload("res://12_economy/Currency.gd")
const PermanentUpgrade := preload("res://11_items/PermanentUpgrade.gd")

## Genera zombies durante las oleadas usando pools por tipo.
##
## Escucha `wave_spawn_batch`, elige el tipo con la composicion de la oleada y
## coloca cada zombie en un punto de aparicion libre. Aplica el escalado de
## oleada desde WaveScaling.
## Accesible globalmente via `ZombieSpawner` (class_name).

const MAX_ALIVE: int = 80
const SPAWN_CLEARANCE: float = 1.5

var types: ZombieTypes = ZombieTypes.new()
var pool: ZombiePool
var scaling: WaveScaling = WaveScaling.new()
var composition: WaveComposition = WaveComposition.new()
var current_data: WaveData = null
var spawn_points: Array[Node3D] = []
var alive: Array[BaseZombie] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spawn_queue: Array[StringName] = []

func _ready() -> void:
	add_to_group("zombie_spawner")
	pool = ZombiePool.new()
	pool.setup(self, types)
	_rng.randomize()
	scaling = load("res://16_data/WaveScaling.tres") as WaveScaling
	if scaling == null:
		scaling = WaveScaling.new()
	current_data = WaveData.new()
	_refresh_spawn_points()
	EventBus.wave_spawn_batch.connect(_on_wave_spawn_batch)
	EventBus.zombie_died.connect(_on_zombie_died)

func _process(_delta: float) -> void:
	if not _spawn_queue.is_empty():
		_try_spawn_next()

## Recalcula los puntos de aparicion disponibles (grupo `spawn_points`).
func _refresh_spawn_points() -> void:
	spawn_points.clear()
	for node: Node in get_tree().get_nodes_in_group("spawn_points"):
		if node is Node3D:
			spawn_points.append(node as Node3D)

## Recibe un lote de la oleada y encola los tipos concretos.
## @param count: numero de zombies del lote.
## @param fallback_type: tipo si la composicion esta vacia.
func _on_wave_spawn_batch(count: int, fallback_type: StringName) -> void:
	if current_data == null or current_data.composition.is_empty():
		for i: int in count:
			_spawn_queue.append(fallback_type)
		return
	var picker := WeightedPicker.new()
	for entry: Dictionary in current_data.composition:
		picker.add(entry["type"], float(entry["weight"]))
	for i: int in count:
		_spawn_queue.append(picker.pick(_rng))

## Intenta generar el siguiente zombie de la cola.
func _try_spawn_next() -> void:
	if alive.size() >= MAX_ALIVE or spawn_points.is_empty():
		return
	var type_name: StringName = _spawn_queue.pop_front()
	var point: Node3D = _pick_spawn_point()
	if point == null:
		_spawn_queue.push_front(type_name)
		return
	var zombie: BaseZombie = pool.acquire(type_name,
		scaling.hp_multiplier(current_data.wave_number),
		scaling.damage_multiplier(current_data.wave_number),
		scaling.speed_multiplier(current_data.wave_number))
	if zombie == null:
		return
	zombie.global_position = point.global_position + Vector3.UP * 0.1
	zombie.current_wave = current_data.wave_number
	add_child(zombie)
	alive.append(zombie)
	EventBus.zombie_spawned.emit(zombie)

## Elige el punto de aparicion mas alejado del jugador (menos sensacion de
## aparicion injusta) y con espacio libre.
func _pick_spawn_point() -> Node3D:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var best: Node3D = null
	var best_score: float = -INF
	for point: Node3D in spawn_points:
		var score: float = randf()
		if player != null:
			score += point.global_position.distance_to(player.global_position) * 0.05
		if _is_point_clear(point):
			score += 10.0
		if score > best_score:
			best_score = score
			best = point
	return best

func _is_point_clear(point: Node3D) -> bool:
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = SPAWN_CLEARANCE
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point.global_position)
	query.collision_mask = (1 << 1) | (1 << 3)
	return space.intersect_shape(query, 8).is_empty()

func _on_zombie_died(zombie: Node3D, _killer: Node3D, _reward: int) -> void:
	alive.erase(zombie)

## True si el spawner gestiona este zombie (para devolverlo al pool).
func is_managed(zombie: BaseZombie) -> bool:
	return alive.has(zombie) or _is_pool_child(zombie)

func _is_pool_child(zombie: BaseZombie) -> bool:
	return zombie != null and zombie.get_parent() == self

## Devuelve un zombie al pool.
func release(zombie: BaseZombie) -> void:
	alive.erase(zombie)
	if pool != null:
		pool.release(zombie)
	else:
		zombie.queue_free()

## Configura la oleada actual (llamado por WaveManager al inicio).
## @param data: WaveData de la oleada.
func set_wave_data(data: WaveData) -> void:
	current_data = data

## Vacia la cola y recicla zombies activos (fin de partida).
func clear_all() -> void:
	_spawn_queue.clear()
	for zombie: BaseZombie in alive.duplicate():
		release(zombie)
	alive.clear()

## Informe de uso de pools para DEBUG.
func pool_report() -> Dictionary:
	return pool.usage_report() if pool != null else {}
