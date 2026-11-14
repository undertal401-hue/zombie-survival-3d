extends Node
## Sistema de guardado: checkpoints, progreso, ajustes, mejoras permanentes.
##
## Usa JSON en user://save_%d.json. Autoload para acceso global.
## Accesible globalmente como `SaveSystem` (autoload singleton).

const SAVE_SLOTS: int = 3
const CURRENT_VERSION: int = 1

var current_slot: int = 0
var permanent_upgrades: Array[Dictionary] = []
var _wave_manager: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_permanent_upgrades()


## Guarda la partida completa en un slot.
## @param slot: 0..2.
## @return true si se guardo correctamente.
func save_game(slot: int = 0) -> bool:
	if slot < 0 or slot >= SAVE_SLOTS:
		return false
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	var pos: Vector3 = player.global_position
	var data: Dictionary = {
		"version": CURRENT_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"player": player.get_stats().to_dict(),
		"inventory": player.inventory.to_dict(),
		"wave": _current_wave(),
		"wave_state": _current_state(),
		"currency": Currency.to_dict(),
		"position": {"x": pos.x, "y": pos.y, "z": pos.z},
		"permanent_upgrades": permanent_upgrades,
		"settings": _get_settings(),
	}
	var path: String = "user://save_%d.json" % slot
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	EventBus.save_written.emit(slot)
	return true


## Carga la partida desde un slot.
## @param slot: 0..2.
## @return true si se cargo correctamente.
func load_game(slot: int = 0) -> bool:
	if slot < 0 or slot >= SAVE_SLOTS:
		return false
	var path: String = "user://save_%d.json" % slot
	if not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var json_str: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != CURRENT_VERSION:
		data = _migrate(data)
	_apply_save(data)
	current_slot = slot
	EventBus.save_loaded.emit(slot)
	return true


## Aplica los datos cargados al estado actual.
func _apply_save(data: Dictionary) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player != null:
		if data.has("player"):
			player.get_stats().from_dict(data["player"])
		if data.has("inventory"):
			_restore_inventory(player, data["inventory"])
		if data.has("position"):
			var pos_data: Dictionary = data["position"]
			player.global_position = Vector3(
				float(pos_data.get("x", 0.0)),
				float(pos_data.get("y", 0.0)),
				float(pos_data.get("z", 0.0)),
			)
	var wm := _get_wave_manager()
	if wm != null:
		if data.has("wave"):
			wm.current_wave = int(data["wave"])
		if data.has("wave_state"):
			wm.state = int(data["wave_state"])
	if data.has("currency"):
		Currency.from_dict(data["currency"])
	if data.has("permanent_upgrades"):
		permanent_upgrades = data["permanent_upgrades"]
		_apply_permanent_upgrades()
	if data.has("settings"):
		_apply_settings(data["settings"])
	EventBus.checkpoint_loaded.emit("save_slot_%d" % current_slot)


## Migra guardados de versiones anteriores.
func _migrate(data: Dictionary) -> Dictionary:
	return data


## Registra una mejora permanente (drop raro).
## @param upgrade: PermanentUpgrade resource.
func record_permanent_upgrade(upgrade) -> void:
	var entry: Dictionary = upgrade.to_dict()
	entry["kind"] = str(entry["kind"])
	if not _has_upgrade(entry["kind"], float(entry["amount"])):
		permanent_upgrades.append(entry)
	_save_permanent_upgrades()


## Evita duplicados de la misma mejora.
func _has_upgrade(kind: String, amount: float) -> bool:
	for entry: Dictionary in permanent_upgrades:
		if str(entry["kind"]) == kind and float(entry["amount"]) == amount:
			return true
	return false


## Aplica todas las mejoras permanentes al jugador actual.
func _apply_permanent_upgrades() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var PermanentUpgrade = load("res://11_items/PermanentUpgrade.gd")
	for entry: Dictionary in permanent_upgrades:
		var upg = PermanentUpgrade.new()
		upg.kind = StringName(entry.get("kind", "damage"))
		upg.amount = float(entry.get("amount", 0.05))
		upg.apply_to(player.get_stats())


## Lookup runtime del autoload WaveManager (evita ciclo de carga).
func _get_wave_manager() -> Node:
	if _wave_manager != null and is_instance_valid(_wave_manager):
		return _wave_manager
	_wave_manager = get_tree().root.get_node_or_null("WaveManager")
	return _wave_manager


## Oleada actual, o 0 si WaveManager no esta disponible.
func _current_wave() -> int:
	var wm := _get_wave_manager()
	if wm == null:
		return 0
	return int(wm.current_wave)


## Estado actual de oleada, o 0 si WaveManager no esta disponible.
func _current_state() -> int:
	var wm := _get_wave_manager()
	if wm == null:
		return 0
	return int(wm.state)


## Persiste mejoras permanentes en archivo separado.
func _save_permanent_upgrades() -> void:
	var path: String = "user://permanent_upgrades.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(permanent_upgrades))
		file.close()


func _load_permanent_upgrades() -> void:
	var path: String = "user://permanent_upgrades.json"
	if FileAccess.file_exists(path):
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file != null:
			var json: String = file.get_as_text()
			file.close()
			var parsed: Variant = JSON.parse_string(json)
			if typeof(parsed) == TYPE_ARRAY:
				permanent_upgrades = parsed


## Restaura el inventario desde datos serializados.
func _restore_inventory(player, inv_data: Dictionary) -> void:
	if player.inventory == null:
		return
	if inv_data.has("consumables"):
		var ItemFactory = load("res://11_items/ItemFactory.gd")
		for item_id: String in inv_data["consumables"]:
			var item = ItemFactory.new().create(item_id)
			if item != null:
				player.inventory.add_consumable(item)


func _get_settings() -> Dictionary:
	return {
		"master_volume": get_tree().root.get_node("AudioManager").get_master_volume_db(),
		"music_volume": get_tree().root.get_node("AudioManager").get_music_volume_db(),
		"sfx_volume": get_tree().root.get_node("AudioManager").get_sfx_volume_db(),
		"mouse_sensitivity": Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED,
	}


func _apply_settings(data: Dictionary) -> void:
	if data.has("master_volume"):
		get_tree().root.get_node("AudioManager").set_master_volume_db(float(data["master_volume"]))
	if data.has("music_volume"):
		get_tree().root.get_node("AudioManager").set_music_volume_db(float(data["music_volume"]))
	if data.has("sfx_volume"):
		get_tree().root.get_node("AudioManager").set_sfx_volume_db(float(data["sfx_volume"]))


## Elimina un slot de guardado.
func delete_slot(slot: int) -> bool:
	var path: String = "user://save_%d.json" % slot
	if FileAccess.file_exists(path):
		return DirAccess.remove_absolute(path)
	return false


## Lista slots con info basica.
func list_saves() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i: int in SAVE_SLOTS:
		var path: String = "user://save_%d.json" % i
		if FileAccess.file_exists(path):
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file != null:
				var json: String = file.get_as_text()
				file.close()
				var parsed: Variant = JSON.parse_string(json)
				if typeof(parsed) == TYPE_DICTIONARY:
					result.append({
						"slot": i,
						"wave": parsed.get("wave", 0),
						"time": parsed.get("timestamp", 0),
						"coins": parsed.get("currency", {}).get("balance", 0),
					})
		else:
			result.append({"slot": i, "empty": true})
	return result
