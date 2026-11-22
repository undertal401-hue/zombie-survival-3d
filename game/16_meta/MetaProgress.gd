extends Node

## Progreso meta persistente y logros. Vive en user:// y nunca escribe en
## GameState, Inventory ni en el estado de la partida. Solo lee señales y
## consultas defensivas; si el archivo está corrupto vuelve a los valores
## iniciales en silencio.

signal achievement_unlocked(id: String, title: String)

const SAVE_PATH: String = "user://meta_progress.json"
# ADR-003: v1 guardaba solo logros; v2 añade el árbol de mejoras y créditos.
const SAVE_VERSION: int = 2

## id -> recompensa cosmética. El identificador es la clave estable en el JSON.
const ACHIEVEMENTS: Dictionary = {
	"first_kill": {"title": "Primera sangre"},
	"horde_survivor": {"title": "Superviviente de hordas"},
	"craft_master": {"title": "Maestro artesano"},
	"mechanic": {"title": "Mecánico de campo"},
	"explorer": {"title": "Explorador del bosque"},
	"night_owl": {"title": "Búho nocturno"},
	"collector": {"title": "Coleccionista de bidones"},
	"pacifist_escape": {"title": "Pacifista"},
	"speedrun": {"title": "Velocista"},
	"survivor": {"title": "Invulnerable"},
}

## Orden determinista para get_title(): el último logro conseguido manda.
const TITLE_PRIORITY: Array[String] = [
	"survivor", "speedrun", "pacifist_escape", "collector", "craft_master",
	"horde_survivor", "mechanic", "explorer", "night_owl", "first_kill",
]
const DEFAULT_TITLE: String = "Nómada"

# ADR-003 — árbol de progresión entre partidas: 3 ramas, 2 niveles por rama.
# `cost` se paga con créditos ganados al cerrar runs. Cada `effect` está acotado
# y se valida al aplicarlo; el JSON nunca introduce claves arbitrarias.
const UPGRADE_TREE: Dictionary = {
	"supervivencia": {
		"label": "Supervivencia",
		"levels": [
			{"id": "hide", "level": 1, "cost": 1, "name": "Piel gruesa",
				"effect": {"hunger_drain_mult": 0.75}},
			{"id": "lungs", "level": 2, "cost": 2, "name": "Pulmones de acero",
				"effect": {"hunger_drain_mult": 0.5, "start_hp": 20.0}},
		],
	},
	"arsenal": {
		"label": "Arsenal",
		"levels": [
			{"id": "belt", "level": 1, "cost": 1, "name": "Cinturón de munición",
				"effect": {"ammo": {"pistol_ammo": 12}}},
			{"id": "backup", "level": 2, "cost": 3, "name": "Escopeta de reserva",
				"effect": {"ammo": {"shotgun_ammo": 8}, "extra_weapon": "shotgun"}},
		],
	},
	"botin": {
		"label": "Botín",
		"levels": [
			{"id": "scavenger", "level": 1, "cost": 1, "name": "Ojo de carroñero",
				"effect": {"loot": {"medkit": 1}}},
			{"id": "fuel_cache", "level": 2, "cost": 2, "name": "Reserva oculta",
				"effect": {"loot": {"combustible": 2}}},
		],
	},
}
const UPGRADE_BRANCHES: Array[String] = ["supervivencia", "arsenal", "botin"]
const MAX_UPGRADE_LEVEL: int = 2
const MAX_CREDITS: int = 1000000
# Plantilla real para el efecto "arma inicial extra" (ranura meta reservada).
const EXTRA_WEAPON_RES: Weapon = preload("res://02_player/weapons/Shotgun12ga.tres")

const SURVIVOR_LOW_HP: float = 45.0
const SURVIVOR_TARGET: int = 3
const COLLECTOR_FUEL: int = 9
const EXPLORER_CLEARINGS: int = 3
const CRAFT_RECIPES: int = 3
const HORDE_SURVIVAL_SECONDS: float = 45.0
const NIGHT_OWL_SECONDS: float = 45.0
const SPEEDRUN_SECONDS: float = 600.0
const POLL_SECONDS: float = 0.35

var _achievements: Dictionary = {}
var _titles: Dictionary = {}
var _best_time_seconds: float = 0.0
var _best_kills: int = 0
var _best_distance: float = 0.0
var _runs: int = 0
var _last_difficulty: float = 0.0
var _clearings_found: int = 0

# ADR-003 — progreso del árbol. Solo claves conocidas y niveles acotados.
var _credits: int = 0
var _purchased: Dictionary = {}   # rama -> nivel máximo comprado
var _selected: Dictionary = {}    # rama -> nivel equipado
var active_effects: Dictionary = {}
var _applied_player_ids: Dictionary = {}
var _applied_extra_weapon: Dictionary = {}
var _granted_run: int = -1

# Estado de la partida actual. Nada de esto se guarda: R recarga la escena.
var _run_kills: int = 0
var _crafted_ids: Dictionary = {}
var _visited_clearings: Dictionary = {}
var _lethal_saves: int = 0
var _low_hp_seen: bool = false
var _last_hp: float = -1.0
var _last_medkits: int = -1
var _vehicle_hp: Dictionary = {}
var _horde_active: bool = false
var _horde_elapsed: float = 0.0
var _run_elapsed: float = 0.0
var _clock_start: float = 0.0
var _poll_timer: float = 0.0
var _run_finished: bool = false


func _ready() -> void:
	_clock_start = _clock_now()
	_load_progress()
	_connect_bus()
	_snapshot_player()
	_snapshot_medkits()
	# ADR-003: aplicar mejoras equipadas al iniciar partida (efectos acotados).
	apply_upgrades()
	if EventBus.has_signal("wave_started") and not EventBus.is_connected(
			"wave_started", Callable(self, "_on_wave_started_upgrades")):
		EventBus.wave_started.connect(_on_wave_started_upgrades)
	if not Inventory.inventory_changed.is_connected(
			Callable(self, "_on_inventory_changed_upgrades")):
		Inventory.inventory_changed.connect(_on_inventory_changed_upgrades)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_run_elapsed += delta
	if _horde_active:
		_horde_elapsed += delta
		if _horde_elapsed >= HORDE_SURVIVAL_SECONDS and not _player_dead():
			_horde_active = false
			unlock("horde_survivor")
	if not is_unlocked("night_owl") and _elapsed_seconds() >= NIGHT_OWL_SECONDS \
			and not _player_dead() and _is_night():
		unlock("night_owl")

	_poll_timer += delta
	if _poll_timer < POLL_SECONDS:
		return
	_poll_timer = 0.0
	_poll_inventory()
	_poll_clearings()
	_poll_vehicles()
	_poll_survivor()


# --- API pública -----------------------------------------------------------

## Desbloquea un logro conocido. Devuelve true solo la primera vez.
func unlock(id, persist: bool = true) -> bool:
	var key: String = String(id)
	if not ACHIEVEMENTS.has(key) or _achievements.has(key):
		return false
	_achievements[key] = true
	var title: String = String((ACHIEVEMENTS[key] as Dictionary).get("title", key))
	_titles[title] = true
	achievement_unlocked.emit(key, title)
	_notify_unlock(title)
	if persist:
		save_progress()
	return true


func is_unlocked(id) -> bool:
	return _achievements.has(String(id))


## Cierra una partida y actualiza marcas. El nodo ya lo llama al recibir
## victory/game_over; llamarlo a mano es útil para pruebas o integraciones.
func record_run(stats: Dictionary) -> void:
	if not (stats is Dictionary):
		return
	_runs += 1
	var kills: int = maxi(0, int(_number(stats.get("kills", stats.get("kill", _run_kills)), 0.0)))
	var distance: float = maxf(0.0, _number(stats.get("distance", stats.get("distance_travelled", 0.0)), 0.0))
	var seconds: float = maxf(0.0, _number(stats.get("time_seconds", stats.get("time", 0.0)), 0.0))
	var victory: bool = bool(stats.get("victory", false))

	_best_kills = maxi(_best_kills, kills)
	_best_distance = maxf(_best_distance, distance)
	if victory and seconds > 0.0:
		if _best_time_seconds <= 0.0 or seconds < _best_time_seconds:
			_best_time_seconds = seconds
	_runs = maxi(_runs, 1)
	# ADR-003: cada run genera créditos para el árbol (acotados por MAX_CREDITS).
	var earned: int = (2 if victory else 1) + mini(kills / 25, 3)
	_credits = mini(MAX_CREDITS, _credits + earned)
	_last_difficulty = clampf(_number(stats.get("difficulty", _read_difficulty()), _last_difficulty), 0.0, 1.0)
	var found: int = maxi(0, int(_number(stats.get("clearings", _clearings_found), 0.0)))
	_clearings_found = maxi(_clearings_found, found)

	if kills >= 1:
		unlock("first_kill", false)
	if bool(stats.get("horde_survived", false)):
		unlock("horde_survivor", false)
	if int(_number(stats.get("crafts", 0), 0.0)) >= CRAFT_RECIPES:
		unlock("craft_master", false)
	if bool(stats.get("repaired", false)):
		unlock("mechanic", false)
	if found >= EXPLORER_CLEARINGS:
		unlock("explorer", false)
	if bool(stats.get("night", false)):
		unlock("night_owl", false)
	if int(_number(stats.get("fuel", 0), 0.0)) >= COLLECTOR_FUEL:
		unlock("collector", false)
	if int(_number(stats.get("medkit_saves", _lethal_saves), 0.0)) >= SURVIVOR_TARGET:
		unlock("survivor", false)
	if victory:
		if kills <= 0:
			unlock("pacifist_escape", false)
		if seconds > 0.0 and seconds < SPEEDRUN_SECONDS:
			unlock("speedrun", false)
	save_progress()


## Borra únicamente el progreso meta y vuelve a escribir el JSON inicial.
func reset_progress() -> void:
	_achievements.clear()
	_titles.clear()
	_best_time_seconds = 0.0
	_best_kills = 0
	_best_distance = 0.0
	_runs = 0
	_last_difficulty = 0.0
	_clearings_found = 0
	_credits = 0
	_purchased.clear()
	_selected.clear()
	active_effects.clear()
	save_progress()


func get_unlocked() -> Array:
	var result: Array = []
	for id in ACHIEVEMENTS:
		if _achievements.has(String(id)):
			result.append(String(id))
	return result


func get_title() -> String:
	for id in TITLE_PRIORITY:
		if _achievements.has(id):
			return String((ACHIEVEMENTS[id] as Dictionary).get("title", id))
	return DEFAULT_TITLE


## Copia legible de todo el progreso persistente (útil para QA/HUD futuro).
func get_progress() -> Dictionary:
	return _build_save_data().duplicate(true)


func save_progress() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_build_save_data(), "  "))
	file.close()


# --- ADR-003: árbol de mejoras ----------------------------------------------

## Compra el siguiente nivel de una rama. Solo se puede adquirir el nivel
## inmediatamente posterior al ya poseído; el coste se descuenta de créditos
## ganados en runs anteriores. Devuelve false ante cualquier dato inválido.
func buy_upgrade(branch, level) -> bool:
	var key: String = String(branch)
	if not UPGRADE_TREE.has(key):
		return false
	var requested: int = int(_number(level, 0.0))
	if requested < 1 or requested > MAX_UPGRADE_LEVEL:
		return false
	var owned: int = clampi(int(_number(_purchased.get(key, 0), 0.0)), 0, MAX_UPGRADE_LEVEL)
	if requested != owned + 1:
		return false
	var entry: Dictionary = _level_entry(key, requested)
	if entry.is_empty():
		return false
	var cost: int = clampi(int(_number(entry.get("cost", 1), 1.0)), 0, MAX_CREDITS)
	if _credits < cost:
		return false
	_credits -= cost
	_purchased[key] = requested
	_selected[key] = requested
	apply_upgrades()
	save_progress()
	return true


## Equipa un nivel ya comprado (permite bajar de nivel dentro de la rama).
func select_upgrade(branch, level) -> bool:
	var key: String = String(branch)
	if not UPGRADE_TREE.has(key):
		return false
	var requested: int = int(_number(level, 0.0))
	var owned: int = clampi(int(_number(_purchased.get(key, 0), 0.0)), 0, MAX_UPGRADE_LEVEL)
	if requested < 0 or requested > owned or requested > MAX_UPGRADE_LEVEL:
		return false
	_selected[key] = requested
	apply_upgrades()
	save_progress()
	return true


## Nivel comprado en una rama (0 si ninguno). Nunca expone datos del JSON crudo.
func get_upgrade_level(branch) -> int:
	var key: String = String(branch)
	if not UPGRADE_TREE.has(key):
		return 0
	return clampi(int(_number(_purchased.get(key, 0), 0.0)), 0, MAX_UPGRADE_LEVEL)


## Nivel equipado en una rama.
func get_selected_level(branch) -> int:
	var key: String = String(branch)
	if not UPGRADE_TREE.has(key):
		return 0
	return clampi(int(_number(_selected.get(key, 0), 0.0)), 0, MAX_UPGRADE_LEVEL)


func get_credits() -> int:
	return _credits


## Agrega los efectos de TODAS las ramas equipadas y los aplica a los nodos
## vivos. Se llama al iniciar partida y tras cada compra/selección.
func apply_upgrades() -> Dictionary:
	active_effects = _aggregate_effects()
	# Diferido: el jugador y el inventario se crean en el _ready de Main.
	call_deferred("_apply_effects_to_nodes")
	call_deferred("_grant_starting_loot")
	return active_effects.duplicate(true)


## Efectos reales y acotados: ralentiza el hambre (supervivencia), da munición
## inicial (arsenal) y botín de arranque (botín). Ningún valor sale del árbol.
func _aggregate_effects() -> Dictionary:
	var merged: Dictionary = {
		"hunger_drain_mult": 1.0,
		"start_hp": 0.0,
		"ammo": {},
		"loot": {},
		"extra_weapon": "",
	}
	for branch in UPGRADE_BRANCHES:
		var level: int = get_selected_level(branch)
		if level <= 0:
			continue
		var branch_data: Variant = UPGRADE_TREE.get(branch, {})
		if not (branch_data is Dictionary):
			continue
		var levels: Variant = (branch_data as Dictionary).get("levels", [])
		if not (levels is Array):
			continue
		for i in range(mini(level, (levels as Array).size())):
			var entry: Variant = (levels as Array)[i]
			if not (entry is Dictionary):
				continue
			var effect: Variant = (entry as Dictionary).get("effect", {})
			if effect is Dictionary:
				_merge_effect(merged, effect as Dictionary)
	return merged


func _merge_effect(target: Dictionary, effect: Dictionary) -> void:
	if effect.has("hunger_drain_mult"):
		var factor: float = clampf(_number(effect["hunger_drain_mult"], 1.0), 0.1, 1.0)
		target["hunger_drain_mult"] = clampf(
			_number(target.get("hunger_drain_mult", 1.0), 1.0) * factor, 0.25, 1.0)
	for key: String in ["start_hp"]:
		if effect.has(key):
			target[key] = clampf(_number(target.get(key, 0.0), 0.0)
					+ _number(effect[key], 0.0), 0.0, 40.0)
	for key: String in ["ammo", "loot"]:
		if not (effect.has(key) and effect[key] is Dictionary):
			continue
		var bucket: Dictionary = target.get(key, {}) as Dictionary
		if bucket == null:
			bucket = {}
			target[key] = bucket
		var source: Dictionary = effect[key] as Dictionary
		for item_id in source:
			var safe_id: String = String(item_id).substr(0, 32)
			var amount: int = clampi(int(_number(source[item_id], 0.0)), 0, 20)
			bucket[safe_id] = clampi(int(bucket.get(safe_id, 0)) + amount, 0, 40)
		target[key] = bucket
	if effect.has("extra_weapon"):
		target["extra_weapon"] = String(effect["extra_weapon"]).substr(0, 24)


func _apply_effects_to_nodes() -> void:
	var player_node: Node2D = _player()
	if player_node == null or not is_instance_valid(player_node):
		return
	var pid: int = player_node.get_instance_id()
	if _applied_player_ids.has(pid):
		return
	_applied_player_ids[pid] = true
	var drain: Variant = player_node.get("hunger_drain_per_second")
	if drain is float or drain is int:
		var factor: float = clampf(_number(active_effects.get("hunger_drain_mult", 1.0), 1.0), 0.25, 1.0)
		player_node.set("hunger_drain_per_second", maxf(0.01, float(drain) * factor))
	var start_hp: float = clampf(_number(active_effects.get("start_hp", 0.0), 0.0), 0.0, 40.0)
	var hp: Variant = player_node.get("hp")
	if start_hp > 0.0 and (hp is float or hp is int):
		player_node.set("hp", clampf(float(hp) + start_hp, 0.0, 100.0))
	if String(active_effects.get("extra_weapon", "")) == "shotgun":
		_equip_extra_weapon()


## Equipa el arma extra SOLO en su propia ranura reservada. Nunca sustituye
## el hacha ni otra recompensa: si la ranura esta ocupada, la operacion falla
## sin destruir el arma existente y sin emitir un aviso falso.
func _equip_extra_weapon() -> bool:
	var player_node: Node2D = _player()
	if player_node == null:
		return false
	var controller: Node = player_node.get_node_or_null("WeaponController")
	if controller == null or not controller.has_method("add_weapon_if_empty") \
			or not controller.has_method("get_weapon_in_slot"):
		return false
	var slots: Variant = controller.get("weapons")
	if not (slots is Array) or (slots as Array).size() <= WeaponController.SLOT_META_BONUS:
		return false
	var key: String = "extra_%d" % player_node.get_instance_id()
	var target: Weapon = controller.call("get_weapon_in_slot", WeaponController.SLOT_META_BONUS) as Weapon
	if target != null:
		# Idempotente: una segunda llamada solo confirma la recompensa ya instalada.
		return target.weapon_name == EXTRA_WEAPON_RES.weapon_name
	if _applied_extra_weapon.has(key):
		return false
	var equipped: bool = bool(controller.call("add_weapon_if_empty",
		EXTRA_WEAPON_RES, WeaponController.SLOT_META_BONUS))
	if equipped:
		_applied_extra_weapon[key] = true
	return equipped


func _grant_starting_loot() -> void:
	if _granted_run == 1:
		return
	var inventory: Node = _inventory()
	if inventory == null or not inventory.has_method("add_item"):
		return
	var loot: Variant = active_effects.get("loot", {})
	if loot is Dictionary:
		for item_id in (loot as Dictionary):
			inventory.call("add_item", String(item_id),
				clampi(int(_number((loot as Dictionary)[item_id], 0.0)), 0, 20), true)
	var ammo: Variant = active_effects.get("ammo", {})
	if ammo is Dictionary:
		for ammo_id in (ammo as Dictionary):
			inventory.call("add_item", String(ammo_id),
				clampi(int(_number((ammo as Dictionary)[ammo_id], 0.0)), 0, 20), true)
	_granted_run = 1
	var extra_weapon: String = String(active_effects.get("extra_weapon", ""))
	if not extra_weapon.is_empty() and _equip_extra_weapon():
		_emit_unlock_notice("Mejora equipada: %s" % EXTRA_WEAPON_RES.weapon_name)


func _on_wave_started_upgrades(wave: int) -> void:
	if int(wave) == 1 and _granted_run != 1:
		_grant_starting_loot()


## Detecta el Inventory.clear() de inicio de partida para volver a entregar el
## botín de la rama equipada en la siguiente run (sin duplicar dentro de una run).
func _on_inventory_changed_upgrades() -> void:
	var inventory: Node = _inventory()
	if inventory != null and inventory.has_method("total") \
			and int(_number(inventory.call("total"), 0.0)) <= 0:
		_granted_run = -1


func _level_entry(branch: String, level: int) -> Dictionary:
	if not UPGRADE_TREE.has(branch):
		return {}
	var branch_data: Variant = UPGRADE_TREE[branch]
	if not (branch_data is Dictionary):
		return {}
	var levels: Variant = (branch_data as Dictionary).get("levels", [])
	if not (levels is Array):
		return {}
	for i in range((levels as Array).size()):
		var entry: Variant = (levels as Array)[i]
		if entry is Dictionary \
				and clampi(int(_number((entry as Dictionary).get("level", 0), 0.0)), 0, MAX_UPGRADE_LEVEL) == level:
			return entry as Dictionary
	return {}


# --- EventBus --------------------------------------------------------------

func _connect_bus() -> void:
	var bus: Node = _bus()
	if bus == null:
		return
	var hooks: Dictionary = {
		"zombie_died": "_on_zombie_died",
		"victory": "_on_victory",
		"game_over": "_on_game_over",
		"craft_completed": "_on_craft_completed",
		"vehicle_state_changed": "_on_vehicle_state_changed",
		"horde_started": "_on_horde_started",
		"horde_ended": "_on_horde_ended",
		"player_health_changed": "_on_player_health_changed",
		"player_damaged": "_on_player_damaged",
	}
	for signal_name in hooks:
		var name_string: String = String(signal_name)
		if not bus.has_signal(name_string):
			continue
		var callback: Callable = Callable(self, String(hooks[signal_name]))
		if not callback.is_valid():
			continue
		var expected: int = _signal_argc(bus, name_string)
		if expected < 0 or callback.get_argument_count() != expected:
			continue
		if not bus.is_connected(name_string, callback):
			bus.connect(name_string, callback)


func _on_zombie_died(_zombie = null) -> void:
	if _run_finished:
		return
	_run_kills += 1
	if _run_kills >= 1:
		unlock("first_kill")


func _on_craft_completed(item_id = null, amount = 1) -> void:
	if _run_finished:
		return
	var key: String = String(item_id) if item_id != null else ""
	if key.is_empty():
		key = "craft_%d" % (_crafted_ids.size() + 1)
	_crafted_ids[key] = true
	var recipes: int = _crafted_ids.size()
	if int(_number(amount, 1.0)) > 0 and recipes >= CRAFT_RECIPES:
		unlock("craft_master")


func _on_vehicle_state_changed(_vehicle = null, _fuel = 0, hp = 0) -> void:
	var value: float = maxf(0.0, _number(hp, 0.0))
	var key: String = str(_vehicle.get_instance_id()) if _vehicle != null else "desconocido"
	var previous: float = _number(_vehicle_hp.get(key, value), value)
	if value > previous + 0.5:
		unlock("mechanic")
	_vehicle_hp[key] = value


func _on_horde_started(_wave = 0) -> void:
	if _run_finished:
		return
	_horde_active = true
	_horde_elapsed = 0.0


func _on_horde_ended(_wave = 0) -> void:
	if _horde_active and _horde_elapsed >= mini(HORDE_SURVIVAL_SECONDS, 5.0) \
			and not _player_dead():
		unlock("horde_survivor")
	_horde_active = false


func _on_player_health_changed(hp = 0, _max_hp = 0) -> void:
	var value: float = _number(hp, _last_hp)
	if value >= 0.0 and value <= SURVIVOR_LOW_HP:
		_low_hp_seen = true
	_last_hp = value


func _on_player_damaged(_amount = 0, _source = null) -> void:
	var player: Node2D = _player()
	if player == null:
		return
	var value: float = _number(player.get("hp"), -1.0)
	if value >= 0.0 and value <= SURVIVOR_LOW_HP:
		_low_hp_seen = true


func _on_victory() -> void:
	_finish_run(true)


func _on_game_over() -> void:
	_finish_run(false)


func _finish_run(victory: bool) -> void:
	if _run_finished:
		return
	_run_finished = true
	_horde_active = false
	var payload: Dictionary = _run_stats()
	payload["victory"] = victory
	record_run(payload)


func _run_stats() -> Dictionary:
	var source: Dictionary = {}
	var state: Node = _game_state()
	if state != null and state.has_method("stats"):
		var raw: Variant = state.call("stats")
		if raw is Dictionary:
			source = raw as Dictionary
	var kills: int = _run_kills
	for key in ["kill", "kills", "killed"]:
		kills = maxi(kills, int(_number(source.get(key, 0), 0.0)))
	var distance: float = 0.0
	for key in ["distance", "distance_travelled", "distancia"]:
		distance = maxf(distance, maxf(0.0, _number(source.get(key, 0), 0.0)))
	return {
		"kills": kills,
		"distance": distance,
		"time_seconds": _elapsed_seconds(),
		"crafts": maxi(int(_number(source.get("craft", 0), 0.0)), _crafted_ids.size()),
		"clearings": _clearings_found,
		"fuel": _fuel_count(),
		"medkit_saves": _lethal_saves,
		"difficulty": _read_difficulty(),
	}


# --- Sondeos silenciosos ---------------------------------------------------

func _poll_inventory() -> void:
	if not is_unlocked("collector") and _fuel_count() >= COLLECTOR_FUEL:
		unlock("collector")


func _poll_clearings() -> void:
	if is_unlocked("explorer"):
		return
	var forest: Node2D = _forest()
	var player: Node2D = _player()
	if forest == null or player == null:
		return
	var points: Array = []
	if forest.has_method("clearing_points"):
		var raw: Variant = forest.call("clearing_points")
		if raw is Array:
			points = raw as Array
	if points.is_empty():
		var raw_clearings: Variant = forest.get("_clearings")
		if raw_clearings is Array:
			for clearing in raw_clearings as Array:
				if clearing is Dictionary and (clearing as Dictionary).has("pos"):
					points.append((clearing as Dictionary)["pos"])
	if points.is_empty():
		return
	var center: Vector2 = player.global_position
	for i in range(points.size()):
		var raw_point: Variant = points[i]
		var point: Vector2 = Vector2.ZERO
		if raw_point is Vector2:
			point = raw_point as Vector2
		elif raw_point is Dictionary and (raw_point as Dictionary).has("pos"):
			var inner: Variant = (raw_point as Dictionary)["pos"]
			if not (inner is Vector2):
				continue
			point = inner as Vector2
		else:
			continue
		var radius: float = 320.0
		if raw_point is Dictionary:
			radius = maxf(120.0, _number((raw_point as Dictionary).get("radius", radius), radius))
		if center.distance_to(point) <= radius:
			_visited_clearings[i] = true
	if _visited_clearings.size() > _clearings_found:
		_clearings_found = _visited_clearings.size()
	if _clearings_found >= EXPLORER_CLEARINGS:
		unlock("explorer")


func _poll_vehicles() -> void:
	if is_unlocked("mechanic") or not is_inside_tree():
		return
	for vehicle in get_tree().get_nodes_in_group("player_vehicle"):
		if vehicle == null or not is_instance_valid(vehicle):
			continue
		var raw_hp: Variant = vehicle.get("hp")
		if not (raw_hp is float or raw_hp is int):
			continue
		var key: String = str(vehicle.get_instance_id())
		var value: float = maxf(0.0, float(raw_hp))
		var previous: float = _number(_vehicle_hp.get(key, value), value)
		if value > previous + 0.5:
			unlock("mechanic")
			return
		_vehicle_hp[key] = value


func _poll_survivor() -> void:
	if is_unlocked("survivor") or _run_finished:
		return
	var medkits: int = -1
	var inventory: Node = _inventory()
	if inventory != null and inventory.has_method("count"):
		medkits = maxi(0, int(_number(inventory.call("count", "medkit"), 0.0)))
	if _last_medkits >= 0 and medkits >= 0 and medkits < _last_medkits \
			and _low_hp_seen and _last_hp > 0.0:
		_lethal_saves += 1
		_low_hp_seen = false
		if _lethal_saves >= SURVIVOR_TARGET:
			unlock("survivor")
	_last_medkits = medkits


func _snapshot_player() -> void:
	var player: Node2D = _player()
	if player != null:
		_last_hp = _number(player.get("hp"), -1.0)


func _snapshot_medkits() -> void:
	var inventory: Node = _inventory()
	if inventory != null and inventory.has_method("count"):
		_last_medkits = maxi(0, int(_number(inventory.call("count", "medkit"), 0.0)))


func _fuel_count() -> int:
	var inventory: Node = _inventory()
	if inventory == null or not inventory.has_method("count"):
		return 0
	var cans: int = maxi(0, int(_number(inventory.call("count", "combustible"), 0.0)))
	var refined: int = maxi(0, int(_number(inventory.call("count", "vehicle_fuel"), 0.0)))
	return cans + refined


# --- Persistencia defensiva ------------------------------------------------

func _build_save_data() -> Dictionary:
	var titles: Array = []
	for id in get_unlocked():
		var entry: Dictionary = ACHIEVEMENTS[id] as Dictionary
		titles.append(String(entry.get("title", id)))
	return {
		"version": SAVE_VERSION,
		"achievements": get_unlocked(),
		"titles": titles,
		"best_time_seconds": _best_time_seconds,
		"best_kills": _best_kills,
		"best_distance": _best_distance,
		"runs": _runs,
		"difficulty": _last_difficulty,
		"clearings_found": _clearings_found,
		"credits": _credits,
		"purchased": _purchased.duplicate(true),
		"selected": _selected.duplicate(true),
	}


func _load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return
	# JSON.parse_string() escribe un error en stderr con JSON inválido; la
	# instancia JSON devuelve solo un Error y permite fallar en silencio.
	var parser := JSON.new()
	if parser.parse(text) != OK or not (parser.data is Dictionary):
		return
	var raw_data: Dictionary = parser.data as Dictionary
	var version: int = int(_number(raw_data.get("version", 0), 0.0))
	# v1 se migra sin pérdida; versiones futuras/desconocidas no se consumen.
	if version < 1 or version > SAVE_VERSION:
		return
	var data: Dictionary = _migrate(raw_data)
	var raw_achievements: Variant = data.get("achievements", [])
	if raw_achievements is Array:
		for item in raw_achievements as Array:
			var id: String = String(item)
			if ACHIEVEMENTS.has(id):
				_achievements[id] = true
				var title: String = String((ACHIEVEMENTS[id] as Dictionary).get("title", id))
				_titles[title] = true
	_best_time_seconds = maxf(0.0, _number(data.get("best_time_seconds", 0), 0.0))
	_best_kills = maxi(0, int(_number(data.get("best_kills", 0), 0.0)))
	_best_distance = maxf(0.0, _number(data.get("best_distance", 0), 0.0))
	_runs = maxi(0, int(_number(data.get("runs", 0), 0.0)))
	_last_difficulty = clampf(_number(data.get("difficulty", 0), 0.0), 0.0, 1.0)
	_clearings_found = maxi(0, int(_number(data.get("clearings_found", 0), 0.0)))
	# Campos v2 (presentes en saves v2; por defecto 0 en saves v1 migrados).
	_credits = clampi(int(_number(data.get("credits", 0), 0.0)), 0, MAX_CREDITS)
	_purchased = (data.get("purchased", {}) as Dictionary).duplicate(true)
	_selected = (data.get("selected", {}) as Dictionary).duplicate(true)


## Migración v1 -> v2. Preserva TODOS los campos conocidos del save antiguo y
## añade los nuevos con valores seguros. Todo se sanea: el archivo jamás puede
## introducir ramas, niveles ni identificadores arbitrarios (deuda de seguridad).
func _migrate(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	result["version"] = SAVE_VERSION
	result["achievements"] = _sanitize_ids(data.get("achievements", []))
	result["titles"] = _sanitize_strings(data.get("titles", []))
	result["best_time_seconds"] = clampf(_number(data.get("best_time_seconds", 0.0), 0.0), 0.0, 1.0e7)
	result["best_kills"] = clampi(int(_number(data.get("best_kills", 0), 0.0)), 0, 1000000)
	result["best_distance"] = clampf(_number(data.get("best_distance", 0.0), 0.0), 0.0, 1.0e8)
	result["runs"] = clampi(int(_number(data.get("runs", 0), 0.0)), 0, 1000000)
	result["difficulty"] = clampf(_number(data.get("difficulty", 0.0), 0.0), 0.0, 1.0)
	result["clearings_found"] = clampi(int(_number(data.get("clearings_found", 0), 0.0)), 0, 1000000)
	result["credits"] = clampi(int(_number(data.get("credits", 0), 0.0)), 0, MAX_CREDITS)
	result["purchased"] = _sanitize_levels(data.get("purchased", {}))
	result["selected"] = _sanitize_levels(data.get("selected", {}))
	# Un save v1 sin créditos recibe un pequeño-starter acorde a sus runs/logros,
	# sin perder ningún dato previo: la migración es aditiva, nunca destructiva.
	if int(_number(data.get("version", 1), 1.0)) < SAVE_VERSION:
		var earned: int = mini(int(result["runs"]), 25) + mini(int(result["achievements"]), 10)
		result["credits"] = maxi(int(result["credits"]), mini(earned, 50))
	return result


func _sanitize_ids(value: Variant) -> Array:
	var result: Array = []
	if not (value is Array):
		return result
	for item in (value as Array):
		var id: String = String(item).substr(0, 48)
		if ACHIEVEMENTS.has(id) and not result.has(id):
			result.append(id)
	return result


func _sanitize_strings(value: Variant) -> Array:
	var result: Array = []
	if not (value is Array):
		return result
	for item in (value as Array):
		var text: String = String(item).substr(0, 64)
		if not text.is_empty() and not result.has(text):
			result.append(text)
		if result.size() >= 32:
			break
	return result


## Solo acepta ramas del UPGRADE_TREE y niveles 0..MAX_UPGRADE_LEVEL.
func _sanitize_levels(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not (value is Dictionary):
		return result
	for key in (value as Dictionary):
		var branch: String = String(key).substr(0, 32)
		if not UPGRADE_TREE.has(branch):
			continue
		var level: int = clampi(int(_number((value as Dictionary)[key], 0.0)), 0, MAX_UPGRADE_LEVEL)
		if level > 0:
			result[branch] = level
	return result


# --- Utilidades de solo lectura -------------------------------------------

func _notify_unlock(title: String) -> void:
	call_deferred("_emit_unlock_notice", "Logro desbloqueado: %s" % title)


func _emit_unlock_notice(text: String) -> void:
	var bus: Node = _bus()
	if bus != null and bus.has_signal("notification"):
		bus.emit_signal("notification", text)


func _number(value: Variant, fallback: float) -> float:
	if not (value is float or value is int):
		return fallback
	var result: float = float(value)
	if is_nan(result) or is_inf(result):
		return fallback
	return result


func _bus() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("EventBus") as Node


func _game_state() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("GameState") as Node


func _inventory() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("Inventory") as Node


func _player() -> Node2D:
	if is_inside_tree():
		var found: Node = get_tree().get_first_node_in_group("player")
		if found is Node2D:
			return found as Node2D
	var parent: Node = get_parent()
	if parent != null:
		var local: Node = parent.get_node_or_null("Player")
		if local is Node2D:
			return local as Node2D
	return null


func _player_dead() -> bool:
	var player: Node2D = _player()
	if player == null:
		return true
	if bool(player.get("is_dead")):
		return true
	return _number(player.get("hp"), 1.0) <= 0.0


func _forest() -> Node2D:
	var parent: Node = get_parent()
	if parent != null:
		var local: Node = parent.get_node_or_null("Level/Forest")
		if local is Node2D:
			return local as Node2D
	if is_inside_tree():
		var found: Node = get_tree().get_first_node_in_group("forest")
		if found is Node2D:
			return found as Node2D
	return null


func _world_director() -> Node:
	if is_inside_tree():
		for group_name: String in ["world_director", "world_directors"]:
			var nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)
			if not nodes.is_empty():
				return nodes[0]
		var local: Node = get_tree().root.get_node_or_null("WorldDirector")
		if local != null:
			return local
	var parent: Node = get_parent()
	if parent != null:
		return parent.get_node_or_null("WaveManager")
	return null


func _solar_lighting() -> Node:
	var parent: Node = get_parent()
	if parent != null:
		var local: Node = parent.get_node_or_null("SolarLighting")
		if local != null:
			return local
	if is_inside_tree():
		var nodes: Array[Node] = get_tree().get_nodes_in_group("solar_lighting")
		if not nodes.is_empty():
			return nodes[0]
	return null


func _is_night() -> bool:
	var director: Node = _world_director()
	if director != null and is_instance_valid(director):
		if director.has_method("current_phase"):
			if String(director.call("current_phase")).to_lower() == "night":
				return true
		var flag: Variant = director.get("is_night")
		if flag is bool and bool(flag):
			return true
		if director.has_method("night_factor") \
				and _number(director.call("night_factor"), 0.0) >= 0.75:
			return true
	var solar: Node = _solar_lighting()
	if solar != null and is_instance_valid(solar):
		var energy: Variant = solar.get("ambient_energy")
		if energy is float or energy is int:
			return float(energy) <= 0.32
	return false


func _read_difficulty() -> float:
	var state: Node = _game_state()
	if state == null or not state.has_method("difficulty"):
		return 0.0
	return clampf(_number(state.call("difficulty"), 0.0), 0.0, 1.0)


func _clock_now() -> float:
	if not is_inside_tree():
		return 0.0
	# Reloj monotónico en segundos desde el arranque del motor. Sustituye al
	# autoload GameClock vestigial; conserva la semántica de "ahora" creciente
	# que _clock_start/_elapsed_seconds() diferencian. Time.get_ticks_msec() es
	# la API no obsoleta de Godot 4 (OS.get_ticks_msec() está deprecado) y ya se
	# usa en otras zonas del proyecto.
	return Time.get_ticks_msec() / 1000.0


func _elapsed_seconds() -> float:
	var clock_elapsed: float = _clock_now() - _clock_start
	if clock_elapsed > 0.0:
		return clock_elapsed
	return maxf(0.0, _run_elapsed)


func _signal_argc(bus: Node, signal_name: String) -> int:
	for info in bus.get_signal_list():
		if String(info.get("name", "")) == signal_name:
			return int((info.get("args", []) as Array).size())
	return -1
