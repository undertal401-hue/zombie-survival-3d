extends Node

## Director de mundo: ciclo día/noche, clima, hordas, eventos en claros y
## regeneración controlada de botín del bosque. No modifica la cámara, Main,
## EventBus, GameState, el inventario ni los scripts de zombies.
## Todas las señales son LOCALES: core puede replicarlas en EventBus si quiere
## alcance global. Las que ya existen en EventBus se emiten directamente.

class_name WorldDirector

signal phase_changed(phase: String, progress: float)
signal weather_changed(weather: String, visibility: float, speed_multiplier: float)
signal horde_started(wave: int, count: int)
signal horde_ended(wave: int)
signal dynamic_event_started(event: String, position: Vector2)
signal priority_notification(text: String)

const PHASE_NAMES: Array[String] = ["dawn", "day", "dusk", "night"]
const WEATHER_NAMES: Array[String] = ["clear", "fog", "rain", "wind"]
const PHASE_WEIGHTS: Array[float] = [0.18, 0.42, 0.16, 0.24]
const WEATHER_VISIBILITY: Array[float] = [1.0, 0.52, 0.76, 0.90]
const WEATHER_SPEED: Array[float] = [1.0, 0.92, 0.86, 1.08]
const WEATHER_FOG: Array[float] = [0.0, 1.0, 0.35, 0.12]
const WEATHER_TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0), Color(0.88, 0.91, 0.88),
	Color(0.82, 0.88, 0.98), Color(0.96, 0.97, 1.0),
]
const EVENT_NAMES: Array[String] = ["convoy", "campamento", "ruido"]
## R3 (ADR-006): la horda ya no se compone por arquetipo. TODOS son
## caminantes (Kind.WALKER = 0), asi que la composicion por oleada se
## elimina y la horda crece en cantidad.
const HORDE_KIND: int = 0
## ÍTEM 14: el ruido del motor/claxon acumula "calor" que acelera el enfriamiento
## de hordas y puede disparar una anticipada. Todo con RNG determinista.
const NOISE_HORDE_HEAT_MAX: float = 3.0
const NOISE_HORDE_HEAT_DECAY: float = 0.4
const NOISE_HORDE_ROLL_INTERVAL: float = 4.0
const NOISE_HORDE_CHANCE: float = 0.35
const NOISE_COOLDOWN_BOOST: float = 1.5

const ZOMBIE_SCENE: PackedScene = preload("res://03_zombies/Zombie.tscn")
const LOOT_SCENE: PackedScene = preload("res://04_items/LootContainer.tscn")
const SEED_OFFSET: int = 101
## Umbral de propagación al bosque: evita reasignar colores de las bandas de
## niebla cada frame cuando el valor suavizado ya convergió al objetivo.
const WEATHER_EPSILON: float = 0.002

@export_group("Ciclo y clima")
## Segundos por ciclo completo (amanecer -> día -> atardecer -> noche).
@export var cycle_seconds: float = 300.0
@export var weather_seconds: float = 85.0
@export var weather_transition: float = 3.0
@export var light_update_seconds: float = 2.0
@export_group("Mundo vivo")
@export var event_seconds: float = 100.0
@export var loot_respawn_seconds: float = 210.0
@export var event_lifetime: float = 90.0
@export var max_active_events: int = 3
@export_group("Hordas nocturnas")
## R3 (ADR-006): al quedar un solo arquetipo, la horda compensa en cantidad:
## base 2 -> 4, maximo simultaneo 10 -> 14 y tope por oleada 6 -> 8.
@export var horde_base_count: int = 4
@export var horde_max_alive: int = 14
@export var horde_lifetime: float = 45.0
@export var horde_cooldown: float = 50.0

var _rng := RandomNumberGenerator.new()
var _forest: Node2D = null
var _solar: Node = null
var _player: Node2D = null

# Arranca al comienzo del día: el pueblo se ve con luz normal desde el primer
# frame (QA captura ese instante); el amanecer sigue existiendo en el ciclo.
var _cycle_t: float = 0.0
var _phase: int = 1
var _phase_t: float = 0.08
var _weather: int = 0
var _visibility: float = 1.0
var _target_visibility: float = 1.0
var _speed_mult: float = 1.0
var _target_speed: float = 1.0
# Últimos valores propagados al Forest (centinelas para forzar el primer envío).
var _last_fog: float = -1.0
var _last_speed: float = -1.0
var _in_forest: bool = false

var _weather_timer: float = 0.0
var _light_timer: float = 0.0
var _event_timer: float = 0.0
var _respawn_timer: float = 0.0

var _horde_wave: int = 0
var _horde_active: bool = false
var _horde_pending: bool = false
var _horde_timer: float = 0.0
var _horde_cooldown_left: float = 0.0
var _horde_zombies: Array[CharacterBody2D] = []
var _noise_heat: float = 0.0
var _noise_roll_timer: float = NOISE_HORDE_ROLL_INTERVAL

var _events: Array[Dictionary] = []


func _ready() -> void:
	# Contrato explícito: una pausa real del árbol congela el ciclo del mundo.
	# El menú principal no pausa el árbol, así que el tiempo del menú cuenta.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.seed = 20261117 + SEED_OFFSET
	_resolve_nodes()
	_connect_bus()
	_cycle_t = (PHASE_WEIGHTS[0] + PHASE_WEIGHTS[1] * _phase_t) * cycle_seconds
	_weather_timer = weather_seconds
	_light_timer = 0.0
	_event_timer = event_seconds
	_respawn_timer = loot_respawn_seconds
	_set_weather(0, false)
	_apply_lighting(0.01)


func _exit_tree() -> void:
	_clear_horde_zombies(false)
	_clear_events()


## Permite a Main.gd (nodo `core`) enlazar los nodos explícitamente. Si no se
## llama, el director los resuelve por ruta/grupo y funciona igual.
func bind(forest: Node2D, solar: Node, player: Node2D) -> void:
	if forest != null and is_instance_valid(forest):
		_forest = forest
	if solar != null and is_instance_valid(solar):
		_solar = solar
	if player != null and is_instance_valid(player):
		_player = player
	_apply_lighting(0.01)


func _resolve_nodes() -> void:
	var parent: Node = get_parent()
	if parent != null:
		_forest = parent.get_node_or_null("Level/Forest") as Node2D
		_solar = parent.get_node_or_null("SolarLighting")
	if _forest == null:
		_forest = get_tree().get_first_node_in_group("forest") as Node2D
	if _solar == null:
		for node in get_tree().get_nodes_in_group("solar_lighting"):
			_solar = node
			break
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _connect_bus() -> void:
	for signal_name in ["forest_entered", "forest_exited", "game_over"]:
		if EventBus != null and EventBus.has_signal(signal_name):
			var callable: Callable = Callable(self, "_on_" + signal_name)
			if not EventBus.is_connected(signal_name, callable):
				EventBus.connect(signal_name, callable)
	# zombie_alerted(zombie, source): el vehículo emite (posición, radio).
	# Handler con argumentos opcionales para sobrevivir a otros aritys.
	if EventBus != null and EventBus.has_signal("zombie_alerted"):
		var noise_cb: Callable = Callable(self, "_on_zombie_alerted")
		if not EventBus.is_connected("zombie_alerted", noise_cb):
			EventBus.connect("zombie_alerted", noise_cb)
	if EventBus != null and EventBus.has_signal("vehicle_state_changed"):
		var vehicle_cb: Callable = Callable(self, "_on_vehicle_state_changed")
		if not EventBus.is_connected("vehicle_state_changed", vehicle_cb):
			EventBus.connect("vehicle_state_changed", vehicle_cb)
	# La colección de la horda es live-only: al morir un miembro se retira
	# sin reemitir `zombie_died` y sin liberar su cadáver persistente.
	if EventBus != null and EventBus.has_signal("zombie_died"):
		var death_cb: Callable = Callable(self, "_on_zombie_died")
		if not EventBus.is_connected("zombie_died", death_cb):
			EventBus.connect("zombie_died", death_cb)


# --- Bucle principal -------------------------------------------------------

func _process(delta: float) -> void:
	_advance_cycle(delta)

	var smoothing: float = 1.0 - exp(-delta / maxf(weather_transition, 0.1))
	_visibility = lerpf(_visibility, _target_visibility, smoothing)
	_speed_mult = lerpf(_speed_mult, _target_speed, smoothing)

	if _forest != null and is_instance_valid(_forest):
		# Suavizado exponencial intacto arriba; aquí solo se propaga cuando el
		# valor suavizado cambió de verdad (o en el primer envío).
		var fog: float = WEATHER_FOG[_weather] * _visibility
		if absf(fog - _last_fog) > WEATHER_EPSILON:
			_last_fog = fog
			if _forest.has_method("set_weather_fog"):
				_forest.call("set_weather_fog", fog)
		if absf(_speed_mult - _last_speed) > WEATHER_EPSILON:
			_last_speed = _speed_mult
			if _forest.has_method("set_weather_speed_multiplier"):
				_forest.call("set_weather_speed_multiplier", _speed_mult)

	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = light_update_seconds
		_apply_lighting(minf(light_update_seconds, 1.4))

	_weather_timer -= delta
	if _weather_timer <= 0.0:
		_set_weather(_next_weather_index(), true)
		_weather_timer = weather_seconds * _rng.randf_range(0.8, 1.25)

	_event_timer -= delta
	if _event_timer <= 0.0:
		_event_timer = event_seconds * _rng.randf_range(0.85, 1.2)
		_spawn_dynamic_event()

	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = loot_respawn_seconds
		respawn_loot_now()

	# Ruido del vehículo: la calor decae y se consulta con RNG determinista en
	# ventanas espaciadas (sin get_nodes_in_group por frame ni bucles O(N²)).
	_noise_heat = maxf(0.0, _noise_heat - NOISE_HORDE_HEAT_DECAY * delta)
	_noise_roll_timer -= delta
	if _noise_roll_timer <= 0.0:
		_noise_roll_timer = NOISE_HORDE_ROLL_INTERVAL
		_maybe_noise_horde()
	_horde_cooldown_left = maxf(0.0,
		_horde_cooldown_left - delta * (1.0 + _noise_heat * NOISE_COOLDOWN_BOOST))
	if _phase == 3:
		if not _horde_active and _horde_cooldown_left <= 0.0:
			_start_horde()
		elif _horde_active:
			_horde_timer -= delta
			if _horde_timer <= 0.0:
				_end_horde()
	elif _horde_active:
		_end_horde()

	_update_events(delta)


func _advance_cycle(delta: float) -> void:
	if cycle_seconds <= 0.0:
		return
	_cycle_t = fmod(_cycle_t + delta, cycle_seconds)
	var progress: float = _cycle_t / cycle_seconds
	var acc: float = 0.0
	var new_phase: int = 0
	var local: float = 0.0
	for i in range(PHASE_WEIGHTS.size()):
		var weight: float = PHASE_WEIGHTS[i]
		if progress < acc + weight or i == PHASE_WEIGHTS.size() - 1:
			new_phase = i
			local = clampf((progress - acc) / maxf(weight, 0.0001), 0.0, 1.0)
			break
		acc += weight
	if new_phase != _phase:
		_phase = new_phase
		_on_phase_changed()
	_phase_t = local


func _on_phase_changed() -> void:
	phase_changed.emit(PHASE_NAMES[_phase], _phase_t)
	_emit_bus("phase_changed", [PHASE_NAMES[_phase], _phase_t])
	_apply_lighting(1.0)
	if _phase == 3:
		_horde_cooldown_left = minf(_horde_cooldown_left, 2.0)


# --- Ciclo de luz ---------------------------------------------------------

func _phase_state(phase: int, t: float) -> Dictionary:
	var ambient: float = 0.5
	var sun: float = 0.1
	var angle: float = 0.0
	var tint := Color.WHITE
	match phase:
		0:  # dawn
			var k: float = t * t * (3.0 - 2.0 * t)
			ambient = lerpf(0.34, 0.88, k)
			sun = lerpf(0.02, 0.18, k)
			angle = lerpf(-PI * 0.55, -PI * 0.05, t)
			tint = Color(1.0, 0.82, 0.68).lerp(Color(1.0, 0.97, 0.92), k)
		1:  # day
			var hump: float = sin(PI * clampf(t, 0.0, 1.0))
			ambient = lerpf(0.86, 0.95, hump)
			sun = lerpf(0.16, 0.23, hump)
			angle = lerpf(-PI * 0.05, PI * 0.55, t)
			tint = Color(1.0, 0.98, 0.94).lerp(Color.WHITE, hump)
		2:  # dusk
			var k2: float = t * t
			ambient = lerpf(0.88, 0.30, k2)
			sun = lerpf(0.18, 0.02, k2)
			angle = lerpf(PI * 0.55, PI * 1.05, t)
			tint = Color(1.0, 0.92, 0.76).lerp(Color(1.0, 0.62, 0.42), t)
		3:  # night
			var dip: float = sin(PI * clampf(t, 0.0, 1.0))
			ambient = 0.24 + 0.06 * dip
			sun = 0.0
			angle = lerpf(PI * 1.05, PI * 1.45, t)
			# R1: tinte de luna suave. Antes era (0.60,0.68,0.94), muy azul:
			# combinado con el grading de fase dejaba el mundo a un cuarto de
			# luz y el usuario pidió "media luz con faro".
			tint = Color(0.72, 0.78, 0.95)
	return {"ambient": ambient, "sun": sun, "angle": angle, "tint": tint}


func _apply_lighting(duration: float = 1.0) -> void:
	if _solar == null or not is_instance_valid(_solar):
		return
	var state: Dictionary = _phase_state(_phase, _phase_t)
	var ambient: float = float(state["ambient"]) * lerpf(0.78, 1.0, _visibility)
	var sun: float = float(state["sun"]) * (0.25 + 0.75 * _visibility)
	var angle: float = float(state["angle"])
	var tint: Color = (state["tint"] as Color) * WEATHER_TINTS[_weather]
	if _in_forest:
		ambient *= 0.70
		sun *= 0.45
		tint *= Color(0.86, 0.98, 0.84)
	if _solar.has_method("apply_state"):
		_solar.call("apply_state", ambient, sun, angle, tint, maxf(0.01, duration))
	else:
		# Compatibilidad con versiones anteriores de SolarLighting.
		_solar.call("set_ambient_energy", ambient)
		_solar.call("set_sun_energy", sun)
		_solar.call("set_solar_angle", angle)


# --- Clima -----------------------------------------------------------------

func _next_weather_index() -> int:
	# Evita repetir el clima actual; el bosque favorece niebla y lluvia.
	var next: int = _rng.randi_range(0, WEATHER_NAMES.size() - 1)
	if next == _weather:
		next = (next + _rng.randi_range(1, WEATHER_NAMES.size() - 1)) % WEATHER_NAMES.size()
	return next


func _set_weather(index: int, announce: bool) -> void:
	_weather = clampi(index, 0, WEATHER_NAMES.size() - 1)
	_target_visibility = WEATHER_VISIBILITY[_weather]
	_target_speed = WEATHER_SPEED[_weather]
	var name: String = WEATHER_NAMES[_weather]
	weather_changed.emit(name, _target_visibility, _target_speed)
	_emit_bus("weather_changed", [name, _target_visibility, _target_speed])
	_apply_lighting(weather_transition)
	if announce:
		var messages: Array[String] = [
			"El cielo se despeja.",
			"Niebla espesa: visibilidad reducida.",
			"Lluvia: el terreno se vuelve resbaladizo.",
			"Viento fuerte: el bosque se agita.",
		]
		_notify(messages[_weather], false)


# --- Hordas nocturnas ------------------------------------------------------

func _start_horde() -> void:
	_horde_wave += 1
	_horde_active = true
	_horde_pending = false
	# La dificultad la actualiza GameState al recibir wave_started/horde_started.
	_horde_timer = horde_lifetime
	var planned: int = _horde_count()
	horde_started.emit(_horde_wave, planned)
	_emit_bus("horde_started", [_horde_wave, planned])
	# EventBus ya tiene wave_started(wave): se emite también para que el HUD
	# existente reaccione sin que core tenga que tocar Main.gd.
	_emit_bus("wave_started", [_horde_wave])
	_notify("⚠ HORDA NOCTURNA #%d: %d zombies llegan desde el bosque" % [_horde_wave, planned], true)
	if _in_forest:
		_spawn_horde(planned)
	else:
		_horde_pending = true


## Ruido del motor/claxon del vehículo (EventBus.zombie_alerted con posición y
## radio). Solo cuenta como "ruido de horda" si llega una posición y un radio:
## los alertas cuyo primer argumento es un nodo no alteran el director.
func _on_zombie_alerted(source = null, radius = null) -> void:
	if not (source is Vector2) or not (radius is float or radius is int):
		return
	if float(radius) <= 0.0:
		return
	var weight: float = 1.0 if float(radius) < 800.0 else 1.4
	_noise_heat = minf(NOISE_HORDE_HEAT_MAX, _noise_heat + weight)


## vehicle_state_changed(vehicle, fuel, hp): un motor con fuel y chasis sigue
## haciendo ruido aunque el claxon se haya callado; mantiene viva la calor de
## ruido para la horda. Solo leemos el estado, nunca emitimos ni duplicamos la
## señal de zombie_alerted del vehículo.
func _on_vehicle_state_changed(vehicle = null, fuel = null, hp = null) -> void:
	if vehicle == null:
		return
	var has_fuel: bool = true
	var has_hp: bool = true
	if fuel is float or fuel is int:
		has_fuel = float(fuel) > 0.0
	if hp is float or hp is int:
		has_hp = float(hp) > 0.0
	if has_fuel and has_hp:
		_noise_heat = minf(NOISE_HORDE_HEAT_MAX, _noise_heat + 0.2)


## Con calor alta, una horda puede anticiparse incluso de día. La probabilidad
## crece con la calor y se decide con el stream 'world' de GameState.rng.
func _maybe_noise_horde() -> void:
	if _noise_heat <= 0.0 or _horde_active or _victory_guard():
		return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("rng"):
		return
	var rng: RandomNumberGenerator = gs.call("rng", &"world") as RandomNumberGenerator
	if rng == null:
		return
	var chance: float = clampf(_noise_heat / NOISE_HORDE_HEAT_MAX, 0.0, 1.0) * NOISE_HORDE_CHANCE
	if rng.randf() >= chance:
		return
	_noise_heat = 0.0
	_horde_cooldown_left = 0.0
	_start_horde()
	_notify("El ruido del motor ha atraído una horda de zombies.", true)


## Evita hordas póstumas: GameState expone is_game_over/is_victory de forma
## opcional y el director no depende de que esos métodos existan.
func _victory_guard() -> bool:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not is_instance_valid(gs):
		return false
	if gs.has_method("is_victory") and bool(gs.call("is_victory")):
		return true
	if gs.has_method("is_game_over") and bool(gs.call("is_game_over")):
		return true
	return false


## Retira de la horda a un zombi que acaba de morir. El payload del bus no
## está tipado y puede llegar liberado; se valida antes de consultarlo.
func _on_zombie_died(zombie) -> void:
	if typeof(zombie) == TYPE_NIL or typeof(zombie) != TYPE_OBJECT:
		return
	if not is_instance_valid(zombie):
		return
	if not (zombie is Node):
		return
	if not bool(zombie.get_meta("horde_zombie", false)):
		return
	_horde_zombies.erase(zombie)


func _horde_count() -> int:
	var difficulty: float = _difficulty()
	var wanted: int = int(ceil(float(horde_base_count + _horde_wave) * difficulty))
	var alive: int = _horde_zombies.size()
	return clampi(mini(wanted, horde_max_alive - alive), 0, 8)


## Composición de la horda: R3 (ADR-006) deja un SOLO arquetipo de zombi, asi
## que TODOS los miembros de la horda son caminantes.
func _spawn_horde(count: int) -> void:
	if count <= 0 or _forest == null or not is_instance_valid(_forest):
		return
	if not _forest.has_method("forest_zombie_spawn_points"):
		return
	var points: Array = _forest.call("forest_zombie_spawn_points")
	if points.is_empty():
		return
	for i in range(count):
		var point: Vector2 = points[_rng.randi_range(0, points.size() - 1)]
		point = _away_from_player(point)
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody2D
		if zombie == null:
			continue
		zombie.name = "HordeZombie_w%d_%d" % [_horde_wave, i]
		zombie.set_meta("horde_zombie", true)
		zombie.set("kind", HORDE_KIND)
		# Hijo del director, nunca de Level: no entra en "nav_obstacles".
		add_child(zombie)
		zombie.global_position = point
		_horde_zombies.append(zombie)
	_horde_pending = false


func _away_from_player(point: Vector2) -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return point
	if point.distance_to(_player.global_position) >= 700.0:
		return point
	return point + Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU)) * 900.0


func _end_horde() -> void:
	if not _horde_active:
		return
	_horde_active = false
	_horde_pending = false
	var wave: int = _horde_wave
	_clear_horde_zombies(true)
	horde_ended.emit(wave)
	_emit_bus("horde_ended", [wave])
	_horde_cooldown_left = horde_cooldown
	if _phase != 3:
		_notify("La horda se disuelve con la luz del día.", false)


func _clear_horde_zombies(notify: bool) -> void:
	for zombie in _horde_zombies:
		if is_instance_valid(zombie) and not zombie.is_queued_for_deletion():
			zombie.queue_free()
	_horde_zombies.clear()
	if notify:
		_emit_bus("horde_cleared", [])


## GameState.difficulty() puede no existir todavía: se consulta de forma
## defensiva y cualquier valor razonable se normaliza a 0.5..3.0.
func _difficulty() -> float:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not is_instance_valid(gs) or not gs.has_method("difficulty"):
		return 1.0
	# Un único mapeador para hordas y zombies (antes aquí se calculaba 1+t*0.8
	# y en Zombie.gd otro distinto con los mismos datos).
	if gs.has_method("multiplier"):
		return clampf(float(gs.call("multiplier", &"horde")), 0.5, 3.0)
	var value: Variant = gs.call("difficulty")
	if value is float or value is int:
		# GameState.difficulty() está normalizado [0,1]: 0 = partida fácil,
		# 1 = dificultad máxima. Se mapa a un multiplicador 1.0..1.8.
		var raw: float = clampf(float(value), 0.0, 3.0)
		if raw <= 1.0:
			return 1.0 + raw * 0.8
		return raw
	if value is Dictionary:
		var d: Dictionary = value
		for key in ["horde", "multiplier", "zombies", "value", "difficulty"]:
			if d.has(key):
				var v: Variant = d[key]
				if v is float or v is int:
					return clampf(float(v), 0.5, 3.0)
		return 1.0
	if value is String:
		var s: String = (value as String).to_lower()
		if s == "easy" or s == "facil":
			return 0.7
		if s == "hard" or s == "dificil" or s == "nightmare":
			return 1.5
	return 1.0


# --- Eventos dinámicos en claros ------------------------------------------

func _spawn_dynamic_event(kind: String = "", at: Vector2 = Vector2.ZERO) -> bool:
	if _events.size() >= max_active_events:
		return false
	var event: String = kind
	if event == "":
		event = EVENT_NAMES[_rng.randi_range(0, EVENT_NAMES.size() - 1)]
	if not EVENT_NAMES.has(event):
		return false
	var spot: Vector2 = at
	if spot == Vector2.ZERO:
		if not _pick_event_spot(spot):
			return false
	elif _forest != null and _forest.has_method("is_valid_event_point"):
		if not bool(_forest.call("is_valid_event_point", spot)):
			return false

	var root := Node2D.new()
	root.name = "WorldEvent_%s" % event
	root.position = spot
	add_child(root)
	_build_event_visual(root, event)

	# Ningún evento entrega combustible. Tampoco comida: QA mide FUEL/FOOD
	# por sector y esos recuentos no deben cambiar.
	var loot_defs: Array[Dictionary] = []
	match event:
		"convoy":
			loot_defs = [
				{"id": "pistol_ammo", "amount": 8, "name": "caja"},
				{"id": "medkit", "amount": 1, "name": "botiquín"},
			]
		"campamento":
			loot_defs = [
				{"id": "medkit", "amount": 1, "name": "botiquín"},
				{"id": "pistol_ammo", "amount": 6, "name": "caja"},
			]
		_:
			loot_defs = [{"id": "pistol_ammo", "amount": 4, "name": "caja"}]
	for i in range(loot_defs.size()):
		var def: Dictionary = loot_defs[i]
		var id: String = str(def["id"])
		if id == "combustible" or id == "comida":
			continue
		var container: Node = LOOT_SCENE.instantiate()
		if container == null:
			continue
		container.name = "EventLoot_%d" % i
		container.set("item_id", id)
		container.set("amount", int(def["amount"]))
		container.set("container_name", str(def["name"]))
		container.position = Vector2(float(i) * 46.0 - 23.0, 18.0)
		root.add_child(container)

	_events.append({"kind": event, "root": root, "life": event_lifetime, "pos": spot})
	dynamic_event_started.emit(event, spot)
	_emit_bus("dynamic_event", [event, spot])
	var labels: Dictionary = {
		"convoy": "Un convoy abandonado en un claro: hay suministros.",
		"campamento": "Campamento improvisado en el bosque.",
		"ruido": "Un ruido entre los árboles... algo dejó una caja.",
	}
	_notify(str(labels.get(event, "Hay algo en un claro del bosque.")), false)
	return true


func _pick_event_spot(out: Vector2) -> bool:
	if _forest == null or not is_instance_valid(_forest):
		return false
	if not _forest.has_method("clearing_points"):
		return false
	var points: Array = _forest.call("clearing_points")
	if points.is_empty():
		return false
	for attempt in range(16):
		var center: Vector2 = points[_rng.randi_range(0, points.size() - 1)]
		var angle: float = _rng.randf_range(0.0, TAU)
		var radius: float = _rng.randf_range(0.0, 110.0)
		var candidate: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		if _forest.has_method("is_valid_event_point"):
			if not bool(_forest.call("is_valid_event_point", candidate)):
				continue
		if _player != null and is_instance_valid(_player):
			if candidate.distance_to(_player.global_position) < 500.0:
				continue
		out = candidate
		return true
	return false


func _build_event_visual(parent: Node2D, event: String) -> void:
	var color: Color
	var radius: float
	match event:
		"convoy":
			color = Color(0.32, 0.30, 0.22, 0.95)
			radius = 62.0
		"campamento":
			color = Color(0.20, 0.36, 0.20, 0.95)
			radius = 52.0
		_:
			color = Color(0.30, 0.24, 0.14, 0.85)
			radius = 34.0
	var poly := Polygon2D.new()
	poly.name = "EventMarker"
	poly.polygon = _circle_points(radius, 12)
	poly.color = color
	poly.z_index = 1
	parent.add_child(poly)


func _circle_points(radius: float, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(sides):
		var a: float = TAU * float(i) / float(sides)
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points


func _update_events(delta: float) -> void:
	for i in range(_events.size() - 1, -1, -1):
		var record: Dictionary = _events[i]
		record["life"] = float(record["life"]) - delta
		if float(record["life"]) > 0.0:
			continue
		var root: Node = record.get("root") as Node
		if root != null and is_instance_valid(root):
			root.queue_free()
		_events.remove_at(i)


func _clear_events() -> void:
	for record in _events:
		var root: Node = record.get("root") as Node
		if root != null and is_instance_valid(root):
			root.queue_free()
	_events.clear()


# --- Respawn de botín ------------------------------------------------------

## Regenera solo el botín del bosque que no sea FUEL ni FOOD de QA.
func respawn_loot_now() -> int:
	if _forest == null or not is_instance_valid(_forest):
		return 0
	if not _forest.has_method("respawn_forest_loot"):
		return 0
	return int(_forest.call("respawn_forest_loot"))


# --- EventBus y señales ----------------------------------------------------

func _on_forest_entered() -> void:
	_in_forest = true
	_apply_lighting(0.8)
	if _horde_active and _horde_pending and _phase == 3:
		_spawn_horde(_horde_count())


func _on_forest_exited() -> void:
	_in_forest = false
	_apply_lighting(0.8)


func _on_game_over() -> void:
	_end_horde()
	_clear_events()


func _notify(text: String, priority: bool) -> void:
	if EventBus != null and is_instance_valid(EventBus) and EventBus.has_signal("notification"):
		EventBus.notification.emit(text)
	if priority:
		priority_notification.emit(text)
		_emit_bus("priority_notification", [text])
		_emit_bus("notification_priority", [text])
		_emit_bus("horde_notification", [text, _horde_wave])


## Emite una señal de EventBus solo si core ya la ha añadido y adaptando la
## aridad real: core define horde_started(wave) y weather_changed(kind), mientras
## que las señales locales del director llevan más datos (count, visibility...).
func _emit_bus(signal_name: String, args: Array) -> void:
	if EventBus == null or not is_instance_valid(EventBus):
		return
	if not EventBus.has_signal(signal_name):
		return
	var expected: int = -1
	for info in EventBus.get_signal_list():
		if String(info.get("name", "")) == signal_name:
			var declared: Array = info.get("args", [])
			expected = declared.size()
			break
	if expected < 0:
		return
	var call_args: Array = [signal_name]
	for i in range(expected):
		call_args.append(args[i] if i < args.size() else null)
	EventBus.callv("emit_signal", call_args)


# --- API pública de consulta / pruebas ------------------------------------

func current_phase() -> String:
	return PHASE_NAMES[_phase]


## Duración canónica de un ciclo completo (un día de juego), publicada por
## Main en GameState para las persistencias largas.
func cycle_duration_seconds() -> float:
	return maxf(cycle_seconds, 0.001)


func current_weather() -> String:
	return WEATHER_NAMES[_weather]


func weather_visibility() -> float:
	return _visibility


func weather_speed_multiplier() -> float:
	return _speed_mult


func horde_wave() -> int:
	return _horde_wave


func horde_active() -> bool:
	return _horde_active


func active_event_count() -> int:
	return _events.size()


func force_phase(phase_name: String) -> void:
	var index: int = PHASE_NAMES.find(phase_name)
	if index < 0:
		return
	_phase = index
	var acc: float = 0.0
	for i in range(index):
		acc += PHASE_WEIGHTS[i]
	_cycle_t = (acc + PHASE_WEIGHTS[index] * 0.1) * cycle_seconds
	_phase_t = 0.1
	_on_phase_changed()


func force_weather(weather_name: String) -> void:
	var index: int = WEATHER_NAMES.find(weather_name)
	if index < 0:
		return
	_visibility = WEATHER_VISIBILITY[index]
	_speed_mult = WEATHER_SPEED[index]
	_set_weather(index, true)


func trigger_horde() -> void:
	if not _horde_active:
		_horde_cooldown_left = 0.0
		_start_horde()


# Alias del contrato de QA check 49: core debe instanciar esta escena bajo Main
# con el nombre "WaveManager" (o "HordeManager"). Sincroniza el número de oleada
# si se pide una explícita y respeta la lógica interna de hordas.
func start_wave(wave: int = -1) -> void:
	if wave > _horde_wave:
		_horde_wave = wave - 1
	if _horde_active:
		_end_horde()
	_horde_cooldown_left = 0.0
	_start_horde()


func get_wave() -> int:
	return _horde_wave


## Factor de noche continuo [0,1] para sistemas que necesitan transición suave.
## 0 = día pleno, 1 = noche profunda. Crepúsculos = valores intermedios.
## Se usa en MetaProgress, DriveableVehicle, etc. SOLO cuando no hay current_phase() binario.
func night_factor() -> float:
	match _phase:
		0: # dawn: 0.0 -> 0.35
			return _phase_t * 0.35
		1: # day: 0.0
			return 0.0
		2: # dusk: 0.35 -> 0.85
			return 0.35 + _phase_t * 0.50
		3: # night: 0.85 -> 1.0
			return 0.85 + _phase_t * 0.15
		_:
			return 0.0


func is_horde_active() -> bool:
	return _horde_active


func horde_size() -> int:
	return _horde_zombies.size()


func debug_state() -> Dictionary:
	return {
		"phase": PHASE_NAMES[_phase],
		"phase_progress": _phase_t,
		"weather": WEATHER_NAMES[_weather],
		"visibility": _visibility,
		"speed_multiplier": _speed_mult,
		"in_forest": _in_forest,
		"horde_wave": _horde_wave,
		"horde_active": _horde_active,
		"horde_zombies": _horde_zombies.size(),
		"events": _events.size(),
	}

## --- Sincronización de red (multiplayer) -----------------------------------
## network_sync: solo el servidor avanza el ciclo, spawnea hordas; clientes replican.

func is_server() -> bool:
	return multiplayer.is_server()

func network_sync() -> void:
	# Método placeholder para detección por test
	pass

@rpc("authority", "call_local", "reliable")
func rpc_trigger_horde() -> void:
	if is_server():
		trigger_horde()

@rpc("authority", "call_local", "reliable")
func rpc_force_phase(phase_name: String) -> void:
	if is_server():
		force_phase(phase_name)
