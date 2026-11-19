extends Node
## CAPA 3 / TDD — contrato del ÍTEM 16: música adaptativa con crossfade,
## ducking de SFX y reacción a fase/clima.
## Escrito ANTES de la implementación sobre a7ceeb7: DEBE FALLAR.
## Introspección 100% dinámica (FileAccess + búsqueda de texto): sin símbolos
## nuevos, por lo que no hay Parse Error aunque la música no exista aún.

const AUDIO: String = "res://13_audio/AudioDirector.gd"

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

func _positions(src: String, needle: String) -> Array[int]:
	var out: Array[int] = []
	var idx: int = 0
	while true:
		var pos: int = src.find(needle, idx)
		if pos == -1:
			break
		out.append(pos)
		idx = pos + needle.length()
	return out

func _ready() -> void:
	await get_tree().process_frame
	_declaration()
	_states()
	_selection()
	_crossfade()
	_ducking()
	_reactivity()
	await _finish()

# --- ÍTEM 16.1: tabla de música declarada ------------------------------------

func _declaration() -> void:
	var ok: bool = false
	for line in _read(AUDIO).split("\n"):
		var s: String = line.strip_edges().to_lower()
		if not (s.begins_with("var ") or s.begins_with("const ") \
				or s.begins_with("@export var ")):
			continue
		if s.contains("music") or s.contains("music_tracks") or s.contains("tracks"):
			ok = true
	_check(ok, "ÍTEM 16.1 AudioDirector.gd declara MUSIC/music_tracks/TRACKS")

# --- ÍTEM 16.2: al menos cuatro estados --------------------------------------

func _states() -> void:
	var lower: String = _read(AUDIO).to_lower()
	var required: Array[String] = ["day", "explore", "combat", "night"]
	var found: Array[String] = []
	for token in required:
		if lower.contains(token):
			found.append(token)
	_check(found.size() >= 4,
		"ÍTEM 16.2 existen 4 pistas/estados (day, explore, combat, night) — %d/4" % found.size())

# --- ÍTEM 16.3: selección por estado -----------------------------------------

func _selection() -> void:
	var ok: bool = false
	for line in _read(AUDIO).split("\n"):
		var s: String = line.strip_edges().to_lower()
		if not s.begins_with("func "):
			continue
		if s.contains("play_music") or s.contains("set_music_state") \
				or s.contains("select_track"):
			ok = true
	_check(ok, "ÍTEM 16.3 método de selección por estado (play_music/set_music_state/select_track)")

# --- ÍTEM 16.4: crossfade / fade de volumen cerca de la música ---------------

func _crossfade() -> void:
	var lower: String = _read(AUDIO).to_lower()
	var cross: bool = lower.contains("crossfade") or lower.contains("cross_fade")
	var music_mentions: Array[int] = _positions(lower, "music")
	for pos in _positions(lower, "track"):
		music_mentions.append(pos)
	var fade_near: bool = false
	for pos in music_mentions:
		var window: String = lower.substr(maxi(0, pos - 900), 1800)
		if window.contains("tween") or window.contains("fade"):
			fade_near = true
	_check(cross or fade_near,
		"ÍTEM 16.4 crossfade/fade/Tween sobre volumen cerca de la música")

# --- ÍTEM 16.5: ducking del bus SFX al entrar música --------------------------

func _ducking() -> void:
	var lower: String = _read(AUDIO).to_lower()
	var duck: bool = lower.contains("duck")
	var sfx_gain_near_music: bool = false
	var music_mentions: Array[int] = _positions(lower, "music")
	for pos in _positions(lower, "track"):
		music_mentions.append(pos)
	for pos in music_mentions:
		var window: String = lower.substr(maxi(0, pos - 1000), 2000)
		if window.contains("sfx") \
				and (window.contains("volume") or window.contains("gain") \
				or window.contains("db")):
			sfx_gain_near_music = true
	_check(duck or sfx_gain_near_music,
		"ÍTEM 16.5 ducking de SFX al entrar la música (duck o reducción de ganancia)")

# --- ÍTEM 16.6: reacción a fase / clima --------------------------------------

func _reactivity() -> void:
	var lower: String = _read(AUDIO).to_lower()
	var ok: bool = lower.contains("game_state_changed") \
		or lower.contains("weather_changed")
	if not ok:
		_info("AudioDirector.gd sin game_state_changed ni weather_changed")
	_check(ok, "ÍTEM 16.6 la música reacciona a game_state_changed/weather_changed")

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for i in range(6):
		await get_tree().process_frame
	print("MUSIC_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón GameFeelTest).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Red de seguridad opcional: solo con `-- --strict-assert`.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "MUSIC_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
