extends Node
## ============================================================================
## AUDIO POLICY TEST (R1) — contrato del AUDIO del juego.
## ============================================================================
## Sustituye a MusicTest.gd, que codificaba una decisión RECHAZADA por el
## usuario (música adaptativa obligatoria). R1 (2026-11-20):
##
##   - NO hay música: ni bus, ni pistas, ni crossfade, ni ducking, ni síntesis
##     musical. La música dañaba el ambiente de supervivencia.
##   - SÍ hay ambiente (viento/lluvia/noche/tensión/bosque) y SFX (disparos,
##     zombis, loot por rareza, UI).
##
## Este arnés es un GUARDIÁN DE DECISIÓN: si alguien reintroduce música sin que
## el usuario lo pida, el CI falla.
##
## Introspección 100% dinámica (FileAccess + búsqueda de texto): sin símbolos
## nuevos, por lo que no hay Parse Error aunque el contrato no esté implementado.
## ============================================================================

const AUDIO: String = "res://13_audio/AudioDirector.gd"
const AUDIO_SCENE: String = "res://13_audio/AudioDirector.tscn"

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
	_no_music_declaration()
	_no_music_api()
	_no_music_synthesis()
	_no_music_bus()
	_ambience_preserved()
	_sfx_preserved()
	await _finish()

# --- 1. No hay tabla de música ------------------------------------------------

func _no_music_declaration() -> void:
	var src: String = _read(AUDIO)
	_check(not src.contains("MUSIC_TRACKS"),
		"AudioDirector.gd: sin tabla MUSIC_TRACKS")
	_check(not src.contains("MUSIC_BUS"),
		"AudioDirector.gd: sin bus de música")
	_check(not src.contains("DUCK_SFX_IDS"),
		"AudioDirector.gd: sin tabla de ducking")
	var lower: String = src.to_lower()
	_check(not lower.contains("audio_directormusic"),
		"AudioDirector.gd: no nombra el bus 'AudioDirectorMusic'")

# --- 2. No hay API de música --------------------------------------------------

func _no_music_api() -> void:
	var src: String = _read(AUDIO)
	var offending: Array[String] = []
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if not s.begins_with("func "):
			continue
		if s.contains("play_music") or s.contains("set_music") \
				or s.contains("select_track") or s.contains("duck_for_sfx"):
			offending.append(s)
	_check(offending.is_empty(),
		"AudioDirector.gd: sin funciones de música/ducking (%d)" % offending.size())
	_check(not src.contains("music_volume"),
		"AudioDirector.gd: sin export music_volume")
	var scene: String = _read(AUDIO_SCENE)
	_check(not scene.contains("Music"),
		"AudioDirector.tscn: sin reproductores de música")

# --- 3. No hay síntesis musical ------------------------------------------------

func _no_music_synthesis() -> void:
	var src: String = _read(AUDIO)
	var offending: Array[String] = []
	for token in ["music_day", "music_explore", "music_combat", "music_night", "_music_"]:
		if src.contains(token):
			offending.append(token)
	_check(offending.is_empty(),
		"AudioDirector.gd: sin síntesis de pistas musicales (%s)" % str(offending))

# --- 4. No se crea el bus de música en runtime --------------------------------

func _no_music_bus() -> void:
	var src: String = _read(AUDIO)
	var creates: bool = false
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if s.begins_with("_add_bus(") and s.to_lower().contains("music"):
			creates = true
	_check(not creates,
		"AudioDirector.gd: _ensure_buses() no crea ningún bus de música")
	var bus_name: String = "AudioDirectorMusic"
	_check(AudioServer.get_bus_index(bus_name) < 0,
		"el bus '%s' no existe en el AudioServer" % bus_name)

# --- 5. El ambiente se conserva ------------------------------------------------

func _ambience_preserved() -> void:
	var src: String = _read(AUDIO)
	_check(src.contains("AMBIENCE_BUS"), "AudioDirector.gd: sigue el bus de ambiente")
	_check(src.contains("set_ambience"), "AudioDirector.gd: sigue set_ambience(kind)")
	var loops: Array[String] = ["wind_loop", "rain_loop", "night_loop",
		"tension_loop", "forest_loop"]
	var found: int = 0
	for token in loops:
		if src.contains(token):
			found += 1
	_check(found >= 4,
		"AudioDirector.gd: conserva los bucles de ambiente (%d/5)" % found)
	_check(src.contains("_refresh_ambience"),
		"AudioDirector.gd: sigue refrescando la capa de ambiente")
	_check(src.contains("_loop_wind") and src.contains("_loop_rain"),
		"AudioDirector.gd: conserva la síntesis de viento y lluvia")

# --- 6. Los SFX se conservan ----------------------------------------------------

func _sfx_preserved() -> void:
	var src: String = _read(AUDIO)
	_check(src.contains("TELEGRAPH_SFX"),
		"AudioDirector.gd: conserva el SFX de telegrafía por arquetipo")
	_check(src.contains("LOOT_RARITY_SFX"),
		"AudioDirector.gd: conserva el SFX de loot por rareza")
	_check(src.contains("play_telegraph") and src.contains("play_loot_rarity"),
		"AudioDirector.gd: conserva play_telegraph()/play_loot_rarity()")
	_check(src.contains("SFX_BUS"), "AudioDirector.gd: sigue el bus de SFX")
	_check(src.contains("UI_BUS"), "AudioDirector.gd: sigue el bus de UI")
	_check(src.contains("play_sfx"), "AudioDirector.gd: conserva play_sfx()")
	for fx in ["_fx_pistol", "_fx_shotgun", "_fx_rifle", "_fx_zombie_die"]:
		if not src.contains(fx):
			_check(false, "AudioDirector.gd: conserva el efecto %s" % fx)
			return
	_check(true, "AudioDirector.gd: conserva los efectos de arma y zombi")

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for i in range(6):
		await get_tree().process_frame
	print("AUDIO_POLICY_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón GameFeelTest).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Red de seguridad opcional: solo con `-- --strict-assert`.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "AUDIO_POLICY_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
