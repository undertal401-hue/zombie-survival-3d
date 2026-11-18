extends Node

## Estado central y único del juego: fase, dificultad, azar determinista y
## estadísticas. Toda la lógica de gameplay que necesita estado global debe
## pasar por aquí; los demás nodos emiten señales o consumen esta API.
## No hay prints: este archivo es código de gameplay, no de depuración.

signal phase_changed(old_phase: StringName, new_phase: StringName)
signal difficulty_changed(value: float)
signal stat_changed(key: StringName, value: float)
# Capa de compatibilidad para QA/HUD: instantánea auditable y oleadas.
signal state_changed(data: Dictionary)
signal wave_changed(wave: int)

# Fases permitidas. Se usan StringName para no depender de enum compartidos.
const PHASE_BOOT := &"boot"
const PHASE_EXPLORE := &"explore"
const PHASE_COMBAT := &"combat"
const PHASE_LOOT := &"loot"
const PHASE_DRIVE := &"drive"
const PHASE_PAUSED := &"paused"
const PHASE_VICTORY := &"victory"
const PHASE_DEATH := &"death"

const ALL_PHASES: Array = [
	PHASE_BOOT, PHASE_EXPLORE, PHASE_COMBAT, PHASE_LOOT,
	PHASE_DRIVE, PHASE_PAUSED, PHASE_VICTORY, PHASE_DEATH,
]

# Flujos de azar independientes: combat/ai/loot/world/vehicle.
const STREAM_COMBAT := &"combat"
const STREAM_AI := &"ai"
const STREAM_LOOT := &"loot"
const STREAM_WORLD := &"world"
const STREAM_VEHICLE := &"vehicle"

const MASTER_SEED: int = 20261117

# Ritmo de la dificultad: crece con el tiempo, las bajas y la distancia.
const DIFFICULTY_TIME_RATE: float = 0.004
const DIFFICULTY_KILL_RATE: float = 0.015
const DIFFICULTY_DISTANCE_RATE: float = 0.000015
const DIFFICULTY_EVENT_RATE: float = 0.02
const DIFFICULTY_EMIT_EPSILON: float = 0.001

var _phase: StringName = PHASE_BOOT
var _pre_pause_phase: StringName = PHASE_EXPLORE
var _difficulty: float = 0.0
var _difficulty_emitted: float = 0.0
var _stats: Dictionary = {}
var _actors: Dictionary = {}
var _actor_callbacks: Dictionary = {}
var _rngs: Dictionary = {}
var _master_seed: int = MASTER_SEED
var _wave: int = 0
var _game_over: bool = false
var _victory: bool = false
var _state_change_queued: bool = false

func _init() -> void:
	# Debe seguir evaluando la pausa aunque el árbol esté detenido.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	# Puente con el EventBus global: el estado manda, el bus difunde.
	phase_changed.connect(_relay_phase)
	difficulty_changed.connect(_relay_difficulty)
	# Las oleadas son estado, no lógica de Main: se contabilizan aquí.
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.horde_started.connect(_on_horde_started)

func _process(delta: float) -> void:
	var paused: bool = get_tree().paused
	if paused:
		if _phase != PHASE_PAUSED and _phase != PHASE_DEATH and _phase != PHASE_VICTORY:
			_pre_pause_phase = _phase
			set_phase(PHASE_PAUSED)
		return
	if _phase == PHASE_PAUSED:
		# No heredamos la fase previa si la partida terminó durante la pausa.
		var resumed: StringName = _pre_pause_phase
		set_phase(resumed)
		if resumed != PHASE_DEATH and resumed != PHASE_VICTORY:
			_add_difficulty(delta * DIFFICULTY_TIME_RATE)
		return
	if _phase == PHASE_DEATH or _phase == PHASE_VICTORY:
		return
	_add_difficulty(delta * DIFFICULTY_TIME_RATE)

## Fase actual de la partida.
func phase() -> StringName:
	return _phase

## Cambia de fase. Los valores desconocidos se ignoran para no corruptar el estado.
func set_phase(value) -> void:
	var next := StringName(str(value))
	if next == _phase or not ALL_PHASES.has(next):
		return
	var old_phase: StringName = _phase
	_phase = next
	if next == PHASE_DEATH:
		_game_over = true
	elif next == PHASE_VICTORY:
		_victory = true
	elif next == PHASE_BOOT or next == PHASE_EXPLORE:
		_game_over = false
		_victory = false
	phase_changed.emit(old_phase, next)
	_queue_state_changed()

## Nivel de dificultad normalizado [0, 1].
func difficulty() -> float:
	return _difficulty

## Fija la dificultad base; el paso del tiempo y las estadísticas siguen sumando.
func set_difficulty(value) -> void:
	var next: float = clampf(float(value), 0.0, 1.0)
	if is_equal_approx(next, _difficulty):
		return
	_difficulty = next
	_difficulty_emitted = next
	difficulty_changed.emit(_difficulty)
	_queue_state_changed()

## Generador determinista asociado a un flujo (combat/ai/loot/world/vehicle).
func rng(stream: StringName) -> RandomNumberGenerator:
	var key := StringName(str(stream))
	if _rngs.has(key):
		return _rngs[key] as RandomNumberGenerator
	var generator := RandomNumberGenerator.new()
	generator.seed = _seed_for(key)
	_rngs[key] = generator
	return generator

## Copia de las estadísticas para que nadie pueda mutar el estado interno.
func stats() -> Dictionary:
	return _stats.duplicate()

## Registra un evento y actualiza la dificultad según su tipo.
func record(event, amount: float = 1.0) -> void:
	var key := StringName(str(event))
	var value: float = float(_stats.get(key, 0.0)) + amount
	_stats[key] = value
	stat_changed.emit(key, value)
	_queue_state_changed()
	match key:
		&"kill", &"kills":
			_add_difficulty(amount * DIFFICULTY_KILL_RATE)
		&"distance", &"distance_travelled":
			_add_difficulty(amount * DIFFICULTY_DISTANCE_RATE)
		&"wave", &"horde", &"craft":
			_add_difficulty(amount * DIFFICULTY_EVENT_RATE)

## Registra un actor con su rol. Se da de baja automáticamente al salir del árbol.
func register_actor(node: Node, role) -> void:
	if node == null or not is_instance_valid(node):
		return
	var role_name := StringName(str(role))
	if _actors.has(node):
		_actors[node] = role_name
		return
	_actors[node] = role_name
	var callback := Callable(self, "_on_actor_exiting").bind(node)
	_actor_callbacks[node] = callback
	if node.has_signal("tree_exiting") and not node.is_connected("tree_exiting", callback):
		node.connect("tree_exiting", callback)

## Retira un actor y desconecta su callback de salida.
func unregister_actor(node: Node) -> void:
	if node == null:
		return
	if not _actors.erase(node):
		return
	var callback: Callable = _actor_callbacks.get(node, Callable())
	if callback.is_valid() and node.is_connected("tree_exiting", callback):
		node.disconnect("tree_exiting", callback)
	_actor_callbacks.erase(node)

## Actores vivos, opcionalmente filtrados por rol.
func actors(role = null) -> Array[Node]:
	var result: Array[Node] = []
	var wanted := StringName(str(role)) if role != null else StringName()
	for node in _actors.keys():
		if not is_instance_valid(node):
			_actors.erase(node)
			_actor_callbacks.erase(node)
			continue
		if wanted == StringName() or _actors[node] == wanted:
			result.append(node)
	return result

## Rol de un actor registrado (StringName vacía si no existe).
func role_of(node: Node) -> StringName:
	if node == null or not _actors.has(node):
		return StringName()
	return _actors[node] as StringName

## Reinicia la sesión al cargar una partida nueva. Las fases y el azar vuelven
## a un punto conocido: esto mantiene la partida determinista tras R.
func reset_session(seed_value: int = MASTER_SEED) -> void:
	_master_seed = seed_value
	_rngs.clear()
	_stats.clear()
	_difficulty = 0.0
	_difficulty_emitted = 0.0
	_pre_pause_phase = PHASE_EXPLORE
	set_phase(PHASE_BOOT)

## Fuerza una semilla distinta para todos los flujos (utilizable por QA).
func reset_rngs(seed_value: int = MASTER_SEED) -> void:
	_master_seed = seed_value
	_rngs.clear()

# ---------------------------------------------------------------------------
# Capa de compatibilidad (QA check 46). Son fachadas: no duplican la lógica,
# solo leen/escriben el estado canónico definido arriba.
# ---------------------------------------------------------------------------

## Instantánea serializable. `difficulty` se expresa como entero 0..100 para
## que get_state()['difficulty'] == get_difficulty().
func get_state() -> Dictionary:
	var hp_value: float = 0.0
	var player_node: Node = _player_node()
	if player_node != null:
		var raw_hp: Variant = player_node.get("hp")
		if raw_hp != null:
			hp_value = float(raw_hp)
	var inventory_data: Dictionary = {}
	var inventory_node: Node = _autoload_node(&"Inventory")
	if inventory_node != null and inventory_node.has_method("items"):
		inventory_data = (inventory_node.call("items") as Dictionary).duplicate(true)
	return {
		"hp": hp_value,
		"inventory": inventory_data,
		"wave": _wave,
		"kills": _kill_count(),
		"difficulty": get_difficulty(),
	}

## Restaura una instantánea sin recargar la escena. Los valores ausentes se
## ignoran; la dificultad acepta tanto 0..1 como 0..100.
func load_state(data: Dictionary) -> void:
	if not data is Dictionary:
		return
	if data.has("hp"):
		var player_node: Node = _player_node()
		if player_node != null:
			player_node.set("hp", float(data["hp"]))
	if data.has("inventory") and data["inventory"] is Dictionary:
		var inventory_node: Node = _autoload_node(&"Inventory")
		if inventory_node != null and inventory_node.has_method("clear") \
				and inventory_node.has_method("add_item"):
			inventory_node.call("clear")
			for item_id in data["inventory"]:
				inventory_node.call("add_item", String(item_id), int(data["inventory"][item_id]))
	if data.has("wave"):
		set_wave(int(data["wave"]))
	if data.has("kills"):
		_stats[&"kill"] = maxf(float(data["kills"]), 0.0)
	if data.has("difficulty"):
		var amount: float = float(data["difficulty"])
		set_difficulty(clampf(amount / 100.0 if amount > 1.0 else amount, 0.0, 1.0))
	_emit_state_changed()

## Reinicia la sesión sin recargar escena (alias: new_game).
func reset() -> void:
	reset_session()
	_wave = 0
	wave_changed.emit(_wave)
	_emit_state_changed()

func new_game() -> void:
	reset()

## Número de oleada actual.
func get_wave() -> int:
	return _wave

## Dificultad como entero 0..100; difficulty() sigue devolviendo el float 0..1.
func get_difficulty() -> int:
	return int(round(_difficulty * 100.0))

func is_game_over() -> bool:
	return _game_over

func is_victory() -> bool:
	return _victory

## Cambia la oleada y avisa una sola vez.
func set_wave(wave: int) -> void:
	var next: int = maxi(wave, 0)
	if next == _wave:
		return
	_wave = next
	wave_changed.emit(_wave)
	_queue_state_changed()

func _player_node() -> Node:
	var registered: Array[Node] = actors(&"player")
	if not registered.is_empty():
		return registered[0]
	if is_inside_tree():
		return get_tree().get_first_node_in_group("player")
	return null

func _autoload_node(name: StringName) -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(String(name))

func _kill_count() -> int:
	return int(float(_stats.get(&"kill", 0.0)) + float(_stats.get(&"kills", 0.0)))

func _queue_state_changed() -> void:
	if _state_change_queued:
		return
	_state_change_queued = true
	call_deferred("_emit_state_changed")

func _emit_state_changed() -> void:
	_state_change_queued = false
	state_changed.emit(get_state())

func _on_wave_started(wave: int) -> void:
	set_wave(wave)
	record("wave")

func _on_horde_started(_wave = 0) -> void:
	record("horde")

func _seed_for(key: StringName) -> int:
	var text: String = String(key)
	var mixed: int = _master_seed ^ int(text.hash()) ^ (text.length() * 0x9E3779B9)
	return mixed & 0x7FFFFFFF

func _add_difficulty(amount: float) -> void:
	if amount <= 0.0:
		return
	var next: float = clampf(_difficulty + amount, 0.0, 1.0)
	if is_equal_approx(next, _difficulty):
		return
	_difficulty = next
	if absf(_difficulty - _difficulty_emitted) >= DIFFICULTY_EMIT_EPSILON or _difficulty >= 1.0:
		_difficulty_emitted = _difficulty
		difficulty_changed.emit(_difficulty)
		_queue_state_changed()

func _relay_phase(_old_phase: StringName, new_phase: StringName) -> void:
	EventBus.game_state_changed.emit(new_phase)

func _relay_difficulty(value: float) -> void:
	EventBus.difficulty_changed.emit(value)

func _on_actor_exiting(node: Node) -> void:
	unregister_actor(node)
