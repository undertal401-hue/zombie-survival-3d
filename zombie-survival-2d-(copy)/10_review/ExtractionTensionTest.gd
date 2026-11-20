extends Node
## CAPA 2 (TDD) — contrato de los ÍTEMS 13 y 14: cuenta atrás de extracción,
## ruido de motor que atrae hordas, rareza visible del loot, SFX por rareza y
## contador de oleadas/reloj en el HUD.
## Se escribe ANTES de la implementación sobre 00afcb0: DEBE FALLAR.
##
## Introspección 100% dinámica (FileAccess / búsqueda de texto / get). No se
## referencian símbolos que aún no existen, así que este arnés no produce
## Parse Error aunque estos sistemas todavía no estén implementados.

const EXTRACTION: String = "res://04_items/ExtractionZone.gd"
const VEHICLE: String = "res://12_vehicles/DriveableVehicle.gd"
const WORLD_DIRECTOR: String = "res://01_core/WorldDirector.gd"
const LOOT_CONTAINER: String = "res://04_items/LootContainer.gd"
const AUDIO_DIRECTOR: String = "res://13_audio/AudioDirector.gd"
const HUD: String = "res://08_ui/HUD.gd"

var _failures: Array[String] = []

func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)

func _info(label: String) -> void:
	print("INFO " + label)

func _read(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	return ""

func _ready() -> void:
	await get_tree().process_frame
	var extraction: String = _read(EXTRACTION)
	var vehicle: String = _read(VEHICLE)
	var director: String = _read(WORLD_DIRECTOR)
	var loot: String = _read(LOOT_CONTAINER)
	var audio: String = _read(AUDIO_DIRECTOR)
	var hud: String = _read(HUD)
	_check(_declares(extraction, ["EXTRACTION_COUNTDOWN", "countdown", "COUNTDOWN"]), \
		"ExtractionZone.gd declara EXTRACTION_COUNTDOWN o countdown")
	_check(_countdown_progress_ok(extraction), \
		"ExtractionZone.gd emite/muestra progreso de cuenta atrás (countdown + EventBus/notification)")
	_check(_engine_noise_ok(vehicle), \
		"DriveableVehicle.gd emite ruido de motor que atrae hordas (engine_noise / zombie_alerted)")
	_check(_vehicle_noise_reaction_ok(director), \
		"WorldDirector.gd reacciona al ruido del vehículo (vehicle_state_changed / zombie_alerted cerca de hordas)")
	_check(_rarity_visible_ok(loot), \
		"LootContainer.gd tiene rareza visible (rarity_color / rarity_glow)")
	_check(_loot_rarity_sfx_ok(audio), \
		"AudioDirector.gd tiene SFX de loot por rareza (loot_rarity / rare en IDs)")
	_check(_wave_clock_ok(hud), \
		"HUD.gd muestra contador de oleadas/reloj (wave y clock/time)")
	await _finish()

# --- helpers de introspección ------------------------------------------------

func _declares(src: String, tokens: Array[String]) -> bool:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if not (s.begins_with("func ") or s.begins_with("var ") \
				or s.begins_with("const ") or s.begins_with("@export var ")):
			continue
		for tok in tokens:
			if s.contains(tok):
				return true
	return false

func _near(src: String, anchor: String, others: Array[String], window: int) -> bool:
	var idx: int = 0
	while true:
		var pos: int = src.find(anchor, idx)
		if pos == -1:
			break
		var a: int = maxi(0, pos - window)
		var b: int = mini(src.length(), pos + window)
		var block: String = src.substr(a, b - a)
		var all: bool = true
		for tok in others:
			if not block.contains(tok):
				all = false
		if all:
			return true
		idx = pos + anchor.length()
	return false

func _is_word_char(c: String) -> bool:
	return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".contains(c)

func _has_word(src: String, word: String) -> bool:
	if word.is_empty():
		return false
	var idx: int = 0
	while true:
		var pos: int = src.find(word, idx)
		if pos == -1:
			return false
		var before_ok: bool = pos == 0 or not _is_word_char(src.substr(pos - 1, 1))
		var after_pos: int = pos + word.length()
		var after_ok: bool = after_pos >= src.length() \
			or not _is_word_char(src.substr(after_pos, 1))
		if before_ok and after_ok:
			return true
		idx = pos + 1
	return false

func _countdown_progress_ok(src: String) -> bool:
	var low: String = src.to_lower()
	if not low.contains("countdown"):
		return false
	return _near(low, "countdown", \
		["eventbus", "notification", "emit_signal", "progress", "bar"], 1200)

func _engine_noise_ok(src: String) -> bool:
	var low: String = src.to_lower()
	if _near(low, "zombie_alerted", ["engine", "alert"], 1200):
		return true
	return _near(low, "engine_noise", ["zombie_alerted", "alert", "horde"], 1200)

func _vehicle_noise_reaction_ok(src: String) -> bool:
	var low: String = src.to_lower()
	if not (low.contains("horde") or low.contains("zombie")):
		return false
	if _near(low, "horde", \
			["zombie_alerted", "vehicle_state_changed", "noise", "ruido"], 1600):
		return true
	return _near(low, "zombie", \
		["zombie_alerted", "vehicle_state_changed", "noise"], 1600)

func _rarity_visible_ok(src: String) -> bool:
	var low: String = src.to_lower()
	return low.contains("rarity_color") or low.contains("rarity_glow") \
		or low.contains("rareza_color") or low.contains("rarity_colour")

func _loot_rarity_sfx_ok(src: String) -> bool:
	var low: String = src.to_lower()
	if low.contains("loot_rarity") or low.contains("rare_loot") \
			or low.contains("loot_rare"):
		return true
	return _has_word(low, "rare") or _has_word(low, "rarity")

func _wave_clock_ok(src: String) -> bool:
	var low: String = src.to_lower()
	if not _has_word(low, "wave") and not low.contains("oleada"):
		return false
	return _has_word(low, "clock") or _has_word(low, "time") \
		or low.contains("reloj") or low.contains("tiempo")

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for i in range(6):
		await get_tree().process_frame
	print("EXTRACTION_TENSION_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón ArtAnimTest / GameFeelTest).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Red de seguridad opcional: en fase roja se desactiva para no imprimir
	# "SCRIPT ERROR: Assertion failed". Habilitar con `-- --strict-assert`.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "EXTRACTION_TENSION_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
