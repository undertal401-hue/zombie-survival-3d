extends Node
## CAPA 2 (TDD) — contrato del ÍTEM 12: zombie jefe (kind BOSS / is_boss),
## dos fases, ataque telegrafiado, spawn desde el director y barra de vida.
## Se escribe ANTES de la implementación sobre 00afcb0: DEBE FALLAR.
##
## Introspección 100% dinámica (FileAccess / búsqueda de texto / get). No se
## referencian símbolos que aún no existen, así que este arnés no produce
## Parse Error aunque el boss todavía no esté implementado.

const ZOMBIE: String = "res://03_zombies/Zombie.gd"
const ZOMBIE_VISUAL: String = "res://03_zombies/ZombieVisual.gd"
const WORLD_DIRECTOR: String = "res://01_core/WorldDirector.gd"
const MAIN: String = "res://07_house/Main.gd"
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
	var zombie: String = _read(ZOMBIE)
	var director: String = _read(WORLD_DIRECTOR)
	var main: String = _read(MAIN)
	var hud: String = _read(HUD)
	var visual: String = _read(ZOMBIE_VISUAL)
	_check(_boss_declared(zombie), \
		"Zombie.gd declara Kind.BOSS o KIND_BOSS / is_boss")
	_check(_two_phase_logic(zombie), \
		"existe lógica de 2 fases (phase / enraged en Zombie.gd)")
	_check(_boss_telegraph_ok(zombie), \
		"existe ataque telegrafiado del boss (boss_attack o charge cerca de telegraph)")
	_check(_boss_spawn_ok(director, main), \
		"WorldDirector.gd o Main.gd referencia el boss en el código de spawn")
	_check(_boss_bar_ok(hud, visual), \
		"existe barra de vida del boss en HUD o ZombieVisual (boss_health / boss_bar)")
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

func _has_func_any(src: String, tokens: Array[String]) -> bool:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if not s.begins_with("func "):
			continue
		for tok in tokens:
			if s.contains(tok):
				return true
	return false

func _enum_has(src: String, token: String) -> bool:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if s.begins_with("enum ") and s.contains(token):
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

func _boss_declared(src: String) -> bool:
	if src.contains("Kind.BOSS") or src.contains("KIND_BOSS"):
		return true
	if _enum_has(src, "BOSS"):
		return true
	return _declares(src, ["is_boss"])

func _two_phase_logic(src: String) -> bool:
	if _declares(src, ["enraged", "enrage", "phase", "_phase"]):
		return true
	return _has_func_any(src, ["phase", "enrage"])

func _boss_telegraph_ok(src: String) -> bool:
	if src.contains("boss_attack"):
		return true
	var boss_marker: bool = src.contains("BOSS") or src.contains("is_boss") \
		or src.contains("KIND_BOSS")
	if not boss_marker:
		return false
	return _near(src, "charge", ["telegraph"], 1200)

func _boss_spawn_ok(wd: String, main: String) -> bool:
	var src: String = (wd + "\n" + main).to_lower()
	if not src.contains("boss"):
		return false
	return _near(src, "boss", ["spawn", "horde", "wave", "kind"], 1500)

func _boss_bar_ok(hud: String, visual: String) -> bool:
	var src: String = (hud + "\n" + visual).to_lower()
	if src.contains("boss_health") or src.contains("boss_bar"):
		return true
	return _near(src, "boss", ["health", "bar", "hp"], 800)

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for i in range(6):
		await get_tree().process_frame
	print("BOSS_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón ArtAnimTest / GameFeelTest).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Red de seguridad opcional: en fase roja se desactiva para no imprimir
	# "SCRIPT ERROR: Assertion failed". Habilitar con `-- --strict-assert`.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "BOSS_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
