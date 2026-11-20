extends Node
## CAPA 1 (TDD) — contrato del ÍTEM 5: hit-stop SOLO en kills/headshots.
## Se escribe ANTES de la implementación sobre beb9a1a: DEBE FALLAR.
##
## Introspección 100% dinámica (FileAccess / búsqueda de texto / get). No se
## referencian símbolos que aún no existen, así que este arnés no produce
## Parse Error aunque `hit_stop` todavía no esté implementado.
##
## El ADR-002 vive en docs/adr/ (fuera de res://), así que se lee resolviendo
## el directorio padre del proyecto con ProjectSettings.globalize_path().

const ADR_PATH: String = "docs/adr/0002-hit-stop.md"
const PLAYER_SCRIPT: String = "res://02_player/Player.gd"
const WEAPON_SCRIPT: String = "res://02_player/weapons/WeaponController.gd"
const EVENTBUS_SCRIPT: String = "res://01_core/EventBus.gd"

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

## docs/adr/ está un nivel por encima de game/ (res://).
func _read_adr(rel: String) -> String:
	var base: String = ProjectSettings.globalize_path("res://")
	var candidates: Array[String] = [
		base.path_join("..").path_join(rel),
		base.trim_suffix("/").get_base_dir().path_join(rel),
		"res://" + rel,
	]
	for c in candidates:
		if FileAccess.file_exists(c):
			return FileAccess.get_file_as_string(c)
	return ""

func _ready() -> void:
	await get_tree().process_frame
	_adr_checks()
	_implementation_checks()
	await _finish()

# --- 1. ADR-002 --------------------------------------------------------------

func _adr_checks() -> void:
	var text: String = _read_adr(ADR_PATH)
	_check(not text.is_empty(), "existe docs/adr/0002-hit-stop.md")
	_check(text.contains("accepted"), "ADR-002 está en estado accepted")
	_check(text.contains("0.05"), "ADR-002 documenta Engine.time_scale = 0.05")

# --- 2-6. Implementación -----------------------------------------------------

func _implementation_checks() -> void:
	var player: String = _read(PLAYER_SCRIPT)
	var weapon: String = _read(WEAPON_SCRIPT)
	var combined: String = player + "\n" + weapon

	# 2. Constante de duración del hit-stop.
	_check(combined.contains("HIT_STOP"),
		"Player.gd o WeaponController.gd declara constante de duración HIT_STOP*")

	# 3. Método de hit-stop (búsqueda dinámica en firmas `func`).
	var has_hit_stop_method: bool = _has_func_named(player, "hit_stop") \
		or _has_func_named(weapon, "hit_stop")
	_check(has_hit_stop_method,
		"existe método hit_stop(...) en Player.gd o WeaponController.gd")

	# 4. Timer no escalado.
	_check(combined.contains("process_always"),
		"SceneTreeTimer se crea con process_always = true")

	# 5. Restauración garantizada del escalado de tiempo.
	var restores: bool = combined.contains("Engine.time_scale = 1.0") \
		or combined.contains("Engine.time_scale=1.0") \
		or combined.contains("Engine.time_scale = 1")
	_check(restores,
		"se restaura Engine.time_scale a 1.0 (callback o _exit_tree)")

	# 6. El hit-stop NO se llama en el disparo normal: debe existir al menos
	# una llamada y estar cerca de un condicional de muerte/headshot.
	var occurrences: int = _count(weapon, "hit_stop(")
	var gated: bool = _gated_by_death(weapon, "hit_stop(")
	_check(occurrences >= 1 and gated,
		"hit_stop( solo en bloque de muerte/headshot (apariciones=%d, contexto_ok=%s)" \
			% [occurrences, str(gated)])

	# 7. No regresión: EventBus sigue sin signal `fired`.
	var bus: String = _read(EVENTBUS_SCRIPT)
	var has_fired: bool = _declares_signal(bus, "fired")
	_check(not has_fired, "EventBus sigue sin signal 'fired' (no regresión)")
	if has_fired:
		_info("REGRESIÓN: EventBus declara signal 'fired'")

# --- Helpers ------------------------------------------------------------------

func _has_func_named(src: String, needle: String) -> bool:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if s.begins_with("func ") and s.contains(needle):
			return true
	return false

func _count(text: String, needle: String) -> int:
	var n: int = 0
	var from: int = 0
	while true:
		var idx: int = text.find(needle, from)
		if idx == -1:
			break
		n += 1
		from = idx + needle.length()
	return n

func _gated_by_death(src: String, needle: String) -> bool:
	var keywords: Array[String] = ["zombie_died", "is_dead", "headshot"]
	var from: int = 0
	var found_any: bool = false
	while true:
		var idx: int = src.find(needle, from)
		if idx == -1:
			break
		found_any = true
		var start: int = maxi(0, idx - 500)
		var end: int = mini(src.length(), idx + needle.length() + 200)
		var window: String = src.substr(start, end - start)
		var ok: bool = false
		for kw in keywords:
			if window.contains(kw):
				ok = true
				break
		if not ok:
			return false
		from = idx + needle.length()
	return found_any

func _declares_signal(src: String, name: String) -> bool:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if not s.begins_with("signal "):
			continue
		var rest: String = s.substr(7).strip_edges()
		var token: String = rest
		var paren: int = token.find("(")
		if paren != -1:
			token = token.substr(0, paren)
		var space: int = token.find(" ")
		if space != -1:
			token = token.substr(0, space)
		if token == name:
			return true
	return false

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for i in range(6):
		await get_tree().process_frame
	print("HIT_STOP_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón NightGlareTest / ArtAnimTest).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Red de seguridad opcional: en fase roja se desactiva para no imprimir
	# "SCRIPT ERROR: Assertion failed". Habilitar con `-- --strict-assert`.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "HIT_STOP_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
