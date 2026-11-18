class_name QuestDirector
extends Node

## Director de misiones secundarias dinámicas. Mantiene 2 o 3 misiones activas
## generadas con GameState.rng("world") de forma defensiva, progresan en tiempo
## real desde EventBus/Inventory y entregan recompensas al inventario.
## No toca HUD, Main, EventBus, GameState ni el mundo: solo emite notificaciones
## y expone datos para que el HUD los consuma en el futuro.
## Sin print, sin tabuladores y con comportamiento determinista.

signal quest_started(id: String, data: Dictionary)
signal quest_progress(id: String, progress: float)
signal quest_completed(id: String, reward: Dictionary)

const QUEST_SCRIPT := preload("res://14_quests/Quest.gd")

const TYPE_CLEAR_HORDE := "clear_horde"
const TYPE_SCAVENGE := "scavenge"
const TYPE_CRAFT_ITEM := "craft_item"
const TYPE_REACH_CLEARING := "reach_clearing"
const TYPE_REPAIR_VEHICLE := "repair_vehicle"
const TYPE_SURVIVE_NIGHT := "survive_night"

const TYPES: Array[String] = [
    TYPE_CLEAR_HORDE, TYPE_SCAVENGE, TYPE_CRAFT_ITEM,
    TYPE_REACH_CLEARING, TYPE_REPAIR_VEHICLE, TYPE_SURVIVE_NIGHT,
]
const TYPE_WEIGHTS: Array[int] = [18, 22, 16, 14, 14, 16]

## Solo estos ids pueden aparecer como recompensa. Nunca se usa "combustible".
const REWARD_POOL: Array[String] = [
    "scrap", "scrap", "scrap", "cloth", "cloth", "medkit", "vehicle_fuel",
]
const REWARD_MAX: Dictionary = {
    "scrap": 6, "cloth": 5, "medkit": 2, "vehicle_fuel": 1,
}

const REACH_RADIUS: float = 150.0
const POLL_SECONDS: float = 0.25
const NIGHT_MARK_SECONDS: float = 65.0
const FALLBACK_SEED: int = 20261117 + 404

@export var min_active: int = 2
@export var max_active: int = 3

var _active: Array[Quest] = []
var _pending_starts: Dictionary = {}
var _rng: Object = null
var _player: Node2D = null
var _forest: Node2D = null
var _inventory: Node = null
var _next_id: int = 1
var _poll_left: float = 0.0
var _night_mark_left: float = 0.0
var _terminated: bool = false

func _ready() -> void:
    _rng = _make_rng()
    _resolve_nodes()
    _connect_signals()
    _fill_active()

func _exit_tree() -> void:
    _disconnect_signals()

# --- API pública -----------------------------------------------------------

## Copias de las misiones activas. Cada Dictionary incluye id, tipo, objetivo,
## progreso absoluto, ratio 0..1, posición y recompensa.
func get_active_quests() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for quest in _active:
        result.append(quest.to_dict())
    return result

## Progreso normalizado 0..1 de una misión activa; 0.0 si el id no existe.
func get_progress(id: String) -> float:
    var quest: Quest = _find(id)
    if quest == null:
        return 0.0
    return quest.ratio()

## Datos completos de una misión activa; Dictionary vacío si no existe.
func get_quest_data(id: String) -> Dictionary:
    var quest: Quest = _find(id)
    if quest == null:
        return {}
    return quest.to_dict()

## Completa una misión de forma inmediata y entrega su recompensa.
func complete_quest(id: String) -> bool:
    var quest: Quest = _find(id)
    if quest == null:
        return false
    if quest.completed:
        return true
    _set_progress(quest, quest.target_amount)
    return quest.completed

## Descarta una misión sin recompensa y abre un hueco para otra.
func abandon_quest(id: String) -> bool:
    var quest: Quest = _find(id)
    if quest == null:
        return false
    _active.erase(quest)
    _pending_starts.erase(quest.id)
    _notify("Misión abandonada: %s" % quest.title)
    _fill_active()
    return true

func active_quest_count() -> int:
    return _active.size()

func debug_state() -> Dictionary:
    var ids: Array[String] = []
    for quest in _active:
        ids.append(quest.id)
    return {
        "active": _active.size(),
        "min_active": clampi(min_active, 0, maxi(max_active, 0)),
        "max_active": maxi(max_active, 0),
        "ids": ids,
        "night": _is_night(),
        "terminated": _terminated,
    }

# --- Generación determinista ----------------------------------------------

func _make_rng() -> Object:
    if not is_inside_tree():
        return _fallback_rng()
    var state: Node = get_tree().root.get_node_or_null("GameState")
    if state != null and state.has_method("rng"):
        var candidate: Object = state.call("rng", &"world") as Object
        if candidate != null and candidate.has_method("randi_range"):
            return candidate
    return _fallback_rng()

func _fallback_rng() -> Object:
    var generator := RandomNumberGenerator.new()
    generator.seed = FALLBACK_SEED
    return generator

func _randi(low: int, high: int) -> int:
    if low >= high:
        return maxi(low, 0)
    if _rng != null and _rng.has_method("randi_range"):
        return int(_rng.call("randi_range", low, high))
    return low

func _randf() -> float:
    if _rng != null and _rng.has_method("randf"):
        return clampf(float(_rng.call("randf")), 0.0, 1.0)
    return 0.0

func _fill_active() -> void:
    if _rng == null:
        _rng = _make_rng()
    var lower: int = clampi(min_active, 0, maxi(max_active, 0))
    var upper: int = maxi(max_active, lower)
    var guard: int = 0
    while _active.size() < lower and guard < TYPES.size() * 2:
        guard += 1
        if not _add_next_quest():
            break
    if _active.size() < upper and _active.size() > 0 and _randf() < 0.55:
        _add_next_quest()

func _add_next_quest() -> bool:
    var excluded: Array[String] = []
    for quest in _active:
        excluded.append(quest.kind)
    for _attempt in range(TYPES.size()):
        var kind: String = _roll_kind(excluded)
        var quest: Quest = _make_quest(kind)
        if quest == null:
            if not excluded.has(kind):
                excluded.append(kind)
            continue
        _active.append(quest)
        _announce_start(quest)
        return true
    return false

func _roll_kind(excluded: Array[String]) -> String:
    var pool: Array[String] = []
    for i in range(TYPES.size()):
        var kind: String = TYPES[i]
        if excluded.has(kind):
            continue
        for _weight in range(TYPE_WEIGHTS[i]):
            pool.append(kind)
    if pool.is_empty():
        for kind in TYPES:
            if not excluded.has(kind):
                pool.append(kind)
    if pool.is_empty():
        pool = TYPES.duplicate()
    return pool[_randi(0, pool.size() - 1)]

func _make_quest(kind: String) -> Quest:
    var quest := QUEST_SCRIPT.new() as Quest
    if quest == null:
        return null
    quest.id = "M%d" % _next_id
    _next_id += 1
    quest.kind = kind
    quest.title = QUEST_SCRIPT.label_for_type(kind)
    quest.reward = _make_reward(kind)

    match kind:
        TYPE_CLEAR_HORDE:
            quest.target_id = "zombie"
            quest.target_amount = float(_randi(3, 6))
            quest.description = "Reduce la amenaza eliminando zombies."
        TYPE_SCAVENGE:
            var item_id: String = "scrap" if _randi(0, 1) == 0 else "cloth"
            quest.target_id = item_id
            quest.target_amount = float(_randi(4, 8))
            quest.metadata["baseline"] = _scavenge_amount(item_id)
            quest.description = "Consigue materiales para el campamento."
        TYPE_CRAFT_ITEM:
            var recipes: Array[String] = _craftable_recipes()
            if recipes.is_empty():
                return null
            var recipe_id: String = recipes[_randi(0, recipes.size() - 1)]
            quest.target_id = recipe_id
            quest.target_amount = float(_randi(1, 2))
            quest.description = "Prepara suministros con la mesa de trabajo."
        TYPE_REACH_CLEARING:
            var points: Array[Vector2] = _clearing_points()
            if points.is_empty():
                return null
            var index: int = _randi(0, points.size() - 1)
            quest.target_position = points[index]
            quest.target_id = "claro_%d" % index
            quest.target_amount = 1.0
            quest.metadata["clearing_index"] = index
            quest.description = "Explora un claro del bosque marcado."
        TYPE_REPAIR_VEHICLE:
            var vehicle: Node = _pick_vehicle()
            if vehicle == null:
                return null
            var max_hp: float = _number(vehicle.get("max_hp"), 100.0)
            var hp: float = _number(vehicle.get("hp"), max_hp)
            quest.metadata["vehicle"] = vehicle
            quest.metadata["baseline_hp"] = hp
            quest.target_id = String(vehicle.get("vehicle_name"))
            quest.target_amount = float(_randi(1, 2) * 30)
            quest.description = "Devuelve resistencia a una camioneta."
            if max_hp <= 0.0:
                return null
        TYPE_SURVIVE_NIGHT:
            quest.target_id = "night"
            quest.target_amount = float(_randi(45, 70))
            quest.description = "Aguanta una noche o una horda sin morir."
        _:
            return null
    quest.objective = _objective(quest)
    return quest

func _make_reward(kind: String) -> Dictionary:
    var reward: Dictionary = {}
    var upper: int = 4
    if kind == TYPE_CLEAR_HORDE or kind == TYPE_SURVIVE_NIGHT or kind == TYPE_REPAIR_VEHICLE:
        upper = 6
    var picks: int = 1 + _randi(0, 1)
    for _i in range(picks):
        var item_id: String = REWARD_POOL[_randi(0, REWARD_POOL.size() - 1)]
        var item_max: int = maxi(int(REWARD_MAX.get(item_id, 3)), 1)
        var amount: int = _randi(1, item_max)
        reward[item_id] = int(reward.get(item_id, 0)) + amount
    if reward.is_empty():
        reward["scrap"] = 1
    return reward

func _craftable_recipes() -> Array[String]:
    var result: Array[String] = []
    var inventory: Node = _inventory_node()
    if inventory != null and inventory.has_method("get_recipes"):
        var recipes: Dictionary = inventory.call("get_recipes")
        for key in recipes:
            var entry: Variant = recipes[key]
            if not (entry is Dictionary):
                continue
            var data: Dictionary = entry
            if int(data.get("amount", 1)) != 1:
                continue
            var output: String = String(data.get("output", key))
            if output == "medkit" or output == "vehicle_fuel":
                result.append(String(key))
    if result.is_empty():
        result = ["medkit", "vehicle_fuel"]
    return result

# --- Resolución defensiva de nodos ----------------------------------------

func _resolve_nodes() -> void:
    if not is_inside_tree():
        return
    _player = get_tree().get_first_node_in_group("player") as Node2D
    var parent_node: Node = get_parent()
    if parent_node != null:
        _forest = parent_node.get_node_or_null("Level/Forest") as Node2D
    if _forest == null:
        _forest = get_tree().get_first_node_in_group("forest") as Node2D
    _inventory = get_tree().root.get_node_or_null("Inventory")

func _bus() -> Node:
    if not is_inside_tree():
        return null
    return get_tree().root.get_node_or_null("EventBus")

func _inventory_node() -> Node:
    if _inventory == null or not is_instance_valid(_inventory):
        _resolve_nodes()
    return _inventory

func _forest_node() -> Node2D:
    if _forest == null or not is_instance_valid(_forest):
        _resolve_nodes()
    return _forest

func _player_node() -> Node2D:
    if _player == null or not is_instance_valid(_player):
        _resolve_nodes()
    return _player

func _item_count(item_id: String) -> int:
    var inventory: Node = _inventory_node()
    if inventory == null or not inventory.has_method("count"):
        return 0
    return maxi(int(inventory.call("count", item_id)), 0)

func _scavenge_amount(item_id: String) -> int:
    if item_id == "scrap" or item_id == "cloth":
        return _item_count(item_id)
    return _item_count("scrap") + _item_count("cloth")

func _clearing_points() -> Array[Vector2]:
    var result: Array[Vector2] = []
    var forest: Node2D = _forest_node()
    if forest == null or not forest.has_method("clearing_points"):
        return result
    var raw: Array = forest.call("clearing_points")
    for point in raw:
        if not (point is Vector2):
            continue
        if forest.has_method("is_valid_event_point"):
            if not bool(forest.call("is_valid_event_point", point)):
                continue
        result.append(point)
    if result.is_empty():
        for point in raw:
            if point is Vector2:
                result.append(point)
    return result

func _pick_vehicle() -> Node:
    if not is_inside_tree():
        return null
    var candidates: Array[Node] = []
    for group_name: String in ["player_vehicle", "vehicles"]:
        for node in get_tree().get_nodes_in_group(group_name):
            if is_instance_valid(node) and not candidates.has(node):
                candidates.append(node)
    if candidates.is_empty():
        return null
    var damaged: Array[Node] = []
    for node in candidates:
        var max_hp: float = _number(node.get("max_hp"), 100.0)
        var hp: float = _number(node.get("hp"), max_hp)
        if hp < max_hp - 0.5:
            damaged.append(node)
    if not damaged.is_empty():
        candidates = damaged
    return candidates[_randi(0, candidates.size() - 1)]

func _number(value: Variant, fallback: float) -> float:
    if value is float or value is int:
        return float(value)
    return fallback

func _grant_reward(reward: Dictionary) -> void:
    var inventory: Node = _inventory_node()
    if inventory == null or not inventory.has_method("add_item"):
        return
    for item_id in reward:
        var key: String = String(item_id)
        if not REWARD_POOL.has(key):
            continue
        inventory.call("add_item", key, int(reward[item_id]), true)

# --- Conexiones defensivas -------------------------------------------------

func _connect_signals() -> void:
    var bus: Node = _bus()
    if bus != null:
        _connect_if_available(bus, "zombie_died", "_on_zombie_died")
        _connect_if_available(bus, "craft_completed", "_on_craft_completed")
        _connect_if_available(bus, "vehicle_state_changed", "_on_vehicle_state_changed")
        _connect_if_available(bus, "wave_started", "_on_wave_started")
        _connect_if_available(bus, "horde_started", "_on_horde_started")
        _connect_if_available(bus, "game_state_changed", "_on_game_state_changed")
        _connect_if_available(bus, "game_over", "_on_game_over")
    var inventory: Node = _inventory_node()
    if inventory != null:
        if bus == null or not bus.has_signal("craft_completed"):
            _connect_if_available(inventory, "crafting_completed", "_on_craft_completed")
        _connect_if_available(inventory, "inventory_changed", "_on_inventory_changed")

func _disconnect_signals() -> void:
    var bus: Node = _bus()
    if bus != null:
        _disconnect_if_available(bus, "zombie_died", "_on_zombie_died")
        _disconnect_if_available(bus, "craft_completed", "_on_craft_completed")
        _disconnect_if_available(bus, "vehicle_state_changed", "_on_vehicle_state_changed")
        _disconnect_if_available(bus, "wave_started", "_on_wave_started")
        _disconnect_if_available(bus, "horde_started", "_on_horde_started")
        _disconnect_if_available(bus, "game_state_changed", "_on_game_state_changed")
        _disconnect_if_available(bus, "game_over", "_on_game_over")
    var inventory: Node = _inventory_node()
    if inventory != null:
        _disconnect_if_available(inventory, "crafting_completed", "_on_craft_completed")
        _disconnect_if_available(inventory, "inventory_changed", "_on_inventory_changed")

func _connect_if_available(node: Node, signal_name: String, method_name: String) -> void:
    if node == null or not node.has_signal(signal_name):
        return
    var callback := Callable(self, method_name)
    if not node.is_connected(signal_name, callback):
        node.connect(signal_name, callback)

func _disconnect_if_available(node: Node, signal_name: String, method_name: String) -> void:
    if node == null or not node.has_signal(signal_name):
        return
    var callback := Callable(self, method_name)
    if node.is_connected(signal_name, callback):
        node.disconnect(signal_name, callback)

# --- Progreso en tiempo real -----------------------------------------------

func _process(delta: float) -> void:
    if _terminated:
        return
    _night_mark_left = maxf(0.0, _night_mark_left - delta)
    _poll_left -= delta
    var poll_now: bool = _poll_left <= 0.0
    if poll_now:
        _poll_left = POLL_SECONDS
    for quest in _active.duplicate():
        match quest.kind:
            TYPE_REACH_CLEARING:
                _update_reach_clearing(quest)
            TYPE_SCAVENGE:
                if poll_now:
                    _refresh_scavenge(quest)
            TYPE_REPAIR_VEHICLE:
                if poll_now:
                    _refresh_repair(quest)
            TYPE_SURVIVE_NIGHT:
                _update_survive_night(quest, delta)

func _on_zombie_died(_zombie: Node2D) -> void:
    if _terminated:
        return
    for quest in _active.duplicate():
        if quest.kind == TYPE_CLEAR_HORDE:
            _set_progress(quest, quest.progress_value + 1.0)

func _on_craft_completed(item_id, amount) -> void:
    if _terminated:
        return
    var key: String = String(item_id)
    var units: float = maxf(float(amount), 1.0)
    for quest in _active.duplicate():
        if quest.kind == TYPE_CRAFT_ITEM and quest.target_id == key:
            _set_progress(quest, quest.progress_value + units)

func _on_vehicle_state_changed(_vehicle, _fuel, _hp) -> void:
    if _terminated:
        return
    _poll_left = 0.0
    for quest in _active.duplicate():
        if quest.kind == TYPE_REPAIR_VEHICLE:
            _refresh_repair(quest)

func _on_wave_started(_wave) -> void:
    _night_mark_left = maxf(_night_mark_left, NIGHT_MARK_SECONDS)

func _on_horde_started(_wave) -> void:
    _night_mark_left = maxf(_night_mark_left, NIGHT_MARK_SECONDS)

func _on_game_state_changed(phase) -> void:
    var name: String = String(phase).to_lower()
    if name.contains("death") or name.contains("victory") or name.contains("game_over"):
        _terminated = true

func _on_game_over() -> void:
    _terminated = true

func _on_inventory_changed() -> void:
    _poll_left = 0.0

func _update_reach_clearing(quest: Quest) -> void:
    var player: Node2D = _player_node()
    if player == null or quest.target_position == Vector2.ZERO:
        return
    if player.global_position.distance_to(quest.target_position) <= REACH_RADIUS:
        _set_progress(quest, quest.target_amount)

func _refresh_scavenge(quest: Quest) -> void:
    var baseline: float = float(quest.metadata.get("baseline", 0.0))
    var gained: float = float(_scavenge_amount(quest.target_id)) - baseline
    _set_progress(quest, maxf(quest.progress_value, gained))

func _refresh_repair(quest: Quest) -> void:
    var vehicle: Node = quest.metadata.get("vehicle") as Node
    if vehicle == null or not is_instance_valid(vehicle):
        return
    var max_hp: float = _number(vehicle.get("max_hp"), 100.0)
    var hp: float = _number(vehicle.get("hp"), max_hp)
    var baseline: float = float(quest.metadata.get("baseline_hp", hp))
    var healed: float = maxf(0.0, hp - baseline)
    _set_progress(quest, maxf(quest.progress_value, healed))

func _update_survive_night(quest: Quest, delta: float) -> void:
    if not _is_night():
        return
    var accumulated: float = float(quest.metadata.get("night_accum", 0.0)) + delta
    var whole: float = floor(accumulated)
    if whole <= 0.0:
        quest.metadata["night_accum"] = accumulated
        return
    quest.metadata["night_accum"] = accumulated - whole
    _set_progress(quest, minf(quest.target_amount, quest.progress_value + whole))

func _is_night() -> bool:
    if _terminated:
        return false
    var phase: String = _world_phase()
    if phase.contains("night") or phase.contains("noche"):
        return true
    return _night_mark_left > 0.0

func _world_phase() -> String:
    if not is_inside_tree():
        return ""
    var candidates: Array[Node] = []
    var parent_node: Node = get_parent()
    if parent_node != null:
        for path: String in ["WaveManager", "WorldDirector", "world/WorldDirector"]:
            var node: Node = parent_node.get_node_or_null(path)
            if node != null and not candidates.has(node):
                candidates.append(node)
    for group_name: String in ["world_director", "world_directors"]:
        for node in get_tree().get_nodes_in_group(group_name):
            if not candidates.has(node):
                candidates.append(node)
    var state: Node = get_tree().root.get_node_or_null("GameState")
    if state != null and not candidates.has(state):
        candidates.append(state)
    for node in candidates:
        if node == null or not is_instance_valid(node):
            continue
        if node.has_method("current_phase"):
            return String(node.call("current_phase")).to_lower()
        if node.has_method("phase"):
            return String(node.call("phase")).to_lower()
        var value: Variant = node.get("phase")
        if value is String or value is StringName:
            return String(value).to_lower()
    return ""

# --- Textos, señales y ciclo de vida ---------------------------------------

func _objective(quest: Quest) -> String:
    var done: int = int(round(quest.progress_value))
    var goal: int = int(round(quest.target_amount))
    match quest.kind:
        TYPE_CLEAR_HORDE:
            return "Abatir %d zombies (%d/%d)" % [goal, done, goal]
        TYPE_SCAVENGE:
            return "Recoger %d %s (%d/%d)" % [
                goal, QUEST_SCRIPT.label_for_item(quest.target_id), done, goal,
            ]
        TYPE_CRAFT_ITEM:
            return "Fabricar %s ×%d (%d/%d)" % [
                QUEST_SCRIPT.label_for_item(quest.target_id), goal, done, goal,
            ]
        TYPE_REACH_CLEARING:
            return "Llegar al claro marcado"
        TYPE_REPAIR_VEHICLE:
            var vehicle_name: String = "la camioneta"
            var vehicle: Node = quest.metadata.get("vehicle") as Node
            if vehicle != null and is_instance_valid(vehicle):
                vehicle_name = String(vehicle.get("vehicle_name"))
            return "Reparar %s (+%d resistencia; %d/%d)" % [vehicle_name, goal, done, goal]
        TYPE_SURVIVE_NIGHT:
            return "Sobrevivir la noche (%d/%d s)" % [done, goal]
    return quest.description

func _set_progress(quest: Quest, value: float) -> bool:
    if quest == null or quest.completed or _terminated:
        return false
    if not quest.set_progress(value):
        return false
    quest.objective = _objective(quest)
    quest_progress.emit(quest.id, quest.ratio())
    if quest.ratio() >= 1.0:
        _finish(quest)
    return true

func _finish(quest: Quest) -> bool:
    if quest == null or quest.completed:
        return false
    quest.completed = true
    quest.progress_value = quest.target_amount
    var index: int = _active.find(quest)
    if index >= 0:
        _active.remove_at(index)
    _pending_starts.erase(quest.id)
    var reward: Dictionary = quest.reward.duplicate(true)
    var title: String = quest.title
    _grant_reward(reward)
    quest_completed.emit(quest.id, reward)
    _notify("Misión completada: %s · Recompensa: %s" % [
        title, QUEST_SCRIPT.reward_text(reward),
    ])
    _fill_active()
    return true

func _find(id: String) -> Quest:
    for quest in _active:
        if quest.id == id:
            return quest
    return null

func _announce_start(quest: Quest) -> void:
    _pending_starts[quest.id] = quest
    call_deferred("_emit_pending_start", quest.id)
    call_deferred("_notify", "Nueva misión: %s · %s · Recompensa: %s" % [
        quest.title, quest.objective, QUEST_SCRIPT.reward_text(quest.reward),
    ])

func _emit_pending_start(id: String) -> void:
    var quest: Quest = _pending_starts.get(id) as Quest
    if quest == null:
        return
    _pending_starts.erase(id)
    quest_started.emit(quest.id, quest.to_dict())

func _notify(text: String) -> void:
    if text.is_empty():
        return
    var bus: Node = _bus()
    if bus != null and bus.has_signal("notification"):
        bus.emit_signal("notification", text)
