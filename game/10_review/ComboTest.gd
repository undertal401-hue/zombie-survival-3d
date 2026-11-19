extends Node
## CAPA 2 (TDD) — contrato del ÍTEM 10: sistema de combos (multiplicador,
## ventana temporal, HUD ligado, headshot/melee y aviso de cambio).
## Se escribe ANTES de la implementación sobre 00afcb0: DEBE FALLAR.
##
## Introspección 100% dinámica (FileAccess / búsqueda de texto / get). No se
## referencian símbolos que aún no existen, así que este arnés no produce
## Parse Error aunque el sistema de combos todavía no esté implementado.

const GAME_STATE: String = "res://01_core/GameState.gd"
const EVENT_BUS: String = "res://01_core/EventBus.gd"
const HUD: String = "res://08_ui/HUD.gd"
const COMBO_SYSTEM: String = "res://01_core/ComboSystem.gd"

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
	var gs: String = _read(GAME_STATE)
	var bus: String = _read(EVENT_BUS)
	var hud: String = _read(HUD)
	var calc: String = _calc_source()
	_check(_declares(gs, ["combo_multiplier", "register_combo"]), \
		"GameState.gd expone combo_multiplier o register_combo (método/variable)")
	_check(_has_combo_window(gs), \
		"GameState.gd declara COMBO_WINDOW o similar (~2,5 s)")
	_check(_hud_combo_ok(hud), \
		"HUD.gd contiene 'combo' ligado al multiplicador")
	_check((FileAccess.file_exists(COMBO_SYSTEM) \
			or _has_func_with(gs, "combo")) and _combo_calc_ok(calc), \
		"existe ComboSystem.gd o cálculo en GameState.gd con headshot y melee cerca de combo")
	_check(_combo_cap_ok(calc), \
		"multiplicador máximo de combo >= 3.0 (3.0 / x3 cerca del cálculo)")
	_check(_combo_signal_ok(gs, bus), \
		"EventBus o GameState emite combo_changed/notification al cambiar el combo")
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

func _has_func_with(src: String, token: String) -> bool:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if s.begins_with("func ") and s.contains(token):
			return true
	return false

func _number_after_equal(s: String) -> float:
	var eq: int = s.find("=")
	if eq == -1:
		return -1.0
	var raw: String = s.substr(eq + 1).strip_edges()
	var end: int = 0
	while end < raw.length():
		var c: String = raw.substr(end, 1)
		if "0123456789.-+eE".contains(c):
			end += 1
		else:
			break
	if end == 0:
		return -1.0
	return raw.substr(0, end).to_float()

func _has_combo_window(src: String) -> bool:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if not s.begins_with("const "):
			continue
		var low: String = s.to_lower()
		if not (low.contains("combo_window") or low.contains("combo_timeout") \
				or low.contains("combo_duration")):
			continue
		var value: float = _number_after_equal(s)
		if value >= 1.5 and value <= 4.0:
			return true
	return false

func _hud_combo_ok(hud: String) -> bool:
	var low: String = hud.to_lower()
	if not low.contains("combo"):
		return false
	return low.contains("multiplier") or low.contains("combo_mult") \
		or low.contains("multiplicador")

func _calc_source() -> String:
	var src: String = ""
	if FileAccess.file_exists(COMBO_SYSTEM):
		src += _read(COMBO_SYSTEM) + "\n"
	src += _read(GAME_STATE)
	return src

func _combo_calc_ok(src: String) -> bool:
	var idx: int = 0
	while true:
		var pos: int = src.find("combo", idx)
		if pos == -1:
			break
		var a: int = maxi(0, pos - 1500)
		var b: int = mini(src.length(), pos + 1500)
		var block: String = src.substr(a, b - a)
		if block.contains("headshot") and block.contains("melee"):
			return true
		idx = pos + 5
	return false

func _combo_cap_ok(src: String) -> bool:
	var idx: int = 0
	while true:
		var pos: int = src.find("combo", idx)
		if pos == -1:
			break
		var a: int = maxi(0, pos - 1200)
		var b: int = mini(src.length(), pos + 1200)
		var block: String = src.substr(a, b - a)
		if block.contains("3.0") or block.contains("x3") \
				or block.contains("MAX_COMBO"):
			return true
		idx = pos + 5
	return false

func _combo_signal_ok(gs: String, bus: String) -> bool:
	if bus.contains("combo_changed") or gs.contains("combo_changed"):
		return true
	var idx: int = 0
	while true:
		var pos: int = gs.find("combo", idx)
		if pos == -1:
			break
		var a: int = maxi(0, pos - 1000)
		var b: int = mini(gs.length(), pos + 1000)
		var block: String = gs.substr(a, b - a)
		if block.contains("notification") or block.contains("emit_signal"):
			return true
		idx = pos + 5
	return false

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for i in range(6):
		await get_tree().process_frame
	print("COMBO_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón ArtAnimTest / GameFeelTest).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Red de seguridad opcional: en fase roja se desactiva para no imprimir
	# "SCRIPT ERROR: Assertion failed". Habilitar con `-- --strict-assert`.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "COMBO_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
