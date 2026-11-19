extends Node
## CAPA 1 (TDD) — contrato de los ÍTEMS 6-9: squash/stretch, telegrafía,
## números de daño flotantes y cámara (look-ahead / shake / punch).
## Se escribe ANTES de la implementación sobre beb9a1a: DEBE FALLAR.
##
## Introspección 100% dinámica (FileAccess / búsqueda de texto / get). No se
## referencian símbolos que aún no existen, así que este arnés no produce
## Parse Error aunque el game feel todavía no esté implementado.

const PLAYER_VISUAL: String = "res://02_player/PlayerVisual.gd"
const ZOMBIE_VISUAL: String = "res://03_zombies/ZombieVisual.gd"
const ZOMBIE: String = "res://03_zombies/Zombie.gd"
const PLAYER: String = "res://02_player/Player.gd"
const DAMAGE_NUMBER_GD: String = "res://08_ui/DamageNumber.gd"
const DAMAGE_NUMBER_TSCN: String = "res://08_ui/DamageNumber.tscn"
const PLAYER_SCENE: String = "res://02_player/Player.tscn"
const CAMERA_CONTROLLER: String = "res://02_player/CameraController.gd"
const PROJECT: String = "res://project.godot"

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
	_squash_checks()
	_telegraph_checks()
	_damage_number_checks()
	_camera_checks()
	_regression_checks()
	await _finish()

# --- ÍTEM 6. Squash / stretch -------------------------------------------------

func _squash_checks() -> void:
	_check(_has_squash_api(_read(PLAYER_VISUAL)),
		"PlayerVisual.gd expone método de squash/stretch/punch_scale")
	_check(_has_squash_api(_read(ZOMBIE_VISUAL)),
		"ZombieVisual.gd expone método de squash/stretch/punch_scale")

func _has_squash_api(src: String) -> bool:
	var tokens: Array[String] = ["squash", "stretch", "punch_scale"]
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if not (s.begins_with("func ") or s.begins_with("var ") \
				or s.begins_with("@export var ")):
			continue
		for tok in tokens:
			if s.contains(tok):
				return true
	return false

# --- ÍTEM 7. Telegrafía -------------------------------------------------------

func _telegraph_checks() -> void:
	var zv: String = _read(ZOMBIE_VISUAL)
	_check(_has_func_named(zv, "telegraph"),
		"ZombieVisual.gd expone telegraph(kind) o similar")
	_check(_read(ZOMBIE).contains("telegraph"),
		"Zombie.gd invoca telegraph(...) en el ataque")

func _has_func_named(src: String, needle: String) -> bool:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if s.begins_with("func ") and s.contains(needle):
			return true
	return false

# --- ÍTEM 8. Números de daño flotantes ---------------------------------------

func _damage_number_checks() -> void:
	var exists: bool = FileAccess.file_exists(DAMAGE_NUMBER_GD) \
		or FileAccess.file_exists(DAMAGE_NUMBER_TSCN)
	_check(exists, "existe game/08_ui/DamageNumber.gd o DamageNumber.tscn")
	_check(_headshot_near_damage_number(_read(PLAYER)),
		"Player.gd usa headshot cerca de un spawn de DamageNumber")

func _headshot_near_damage_number(src: String) -> bool:
	var head_idx: int = src.find("headshot")
	if head_idx == -1:
		return false
	var spawn_tokens: Array[String] = ["DamageNumber", "damage_number", "spawn_damage"]
	for tok in spawn_tokens:
		var idx: int = 0
		while true:
			var pos: int = src.find(tok, idx)
			if pos == -1:
				break
			if absi(pos - head_idx) <= 1200:
				return true
			idx = pos + tok.length()
	return false

# --- ÍTEM 9. Cámara -----------------------------------------------------------

func _camera_checks() -> void:
	_check(FileAccess.file_exists(CAMERA_CONTROLLER),
		"existe game/02_player/CameraController.gd")
	_check(_camera_assigned_in_scene(_read(PLAYER_SCENE)),
		"Player.tscn asigna CameraController.gd al nodo Camera2D")

	var cam: String = _read(CAMERA_CONTROLLER)
	for token in ["look_ahead", "shake", "punch"]:
		_check(_exposes(cam, token),
			"CameraController.gd expone '%s' (método o variable)" % token)
	_check(cam.contains("fire_requested"),
		"CameraController.gd se conecta a 'fire_requested'")
	_check(cam.contains("player_damaged"),
		"CameraController.gd se conecta a 'player_damaged'")

func _exposes(src: String, token: String) -> bool:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if not (s.begins_with("func ") or s.begins_with("var ") \
				or s.begins_with("@export var ")):
			continue
		if s.contains(token):
			return true
	return false

func _camera_assigned_in_scene(scene: String) -> bool:
	var node_idx: int = scene.find("[node name=\"Camera2D\"")
	if node_idx == -1:
		return false
	var next_node: int = scene.find("[node ", node_idx + 1)
	var end: int = next_node if next_node != -1 else scene.length()
	var block: String = scene.substr(node_idx, end - node_idx)
	if block.contains("CameraController"):
		return true
	# Resolver `script = ExtResource("N")` contra los ext_resource del header.
	var ids: Array[String] = []
	for line in block.split("\n"):
		var s: String = line.strip_edges()
		if s.begins_with("script = ExtResource("):
			ids.append(_between(s, "\"", "\""))
	if ids.is_empty():
		return false
	for id in ids:
		for hline in scene.split("\n"):
			var hs: String = hline.strip_edges()
			if hs.begins_with("[ext_resource") \
					and hs.contains("id=\"" + id + "\"") \
					and hs.contains("CameraController"):
				return true
	return false

func _between(text: String, open: String, close: String) -> String:
	var a: int = text.find(open)
	if a == -1:
		return ""
	a += open.length()
	var b: int = text.find(close, a)
	if b == -1:
		return ""
	return text.substr(a, b - a)

# --- No regresión Capa 0 ------------------------------------------------------

func _regression_checks() -> void:
	var proj: String = _read(PROJECT)
	var ok: bool = proj.contains("snap_2d_transforms_to_pixel=true") \
		and proj.contains("snap_2d_vertices_to_pixel=true")
	_check(ok, "project.godot conserva el snap a píxel de la Capa 0")
	if not ok:
		_info("REGRESIÓN: falta snap_2d_transforms/vertices_to_pixel=true")

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for i in range(6):
		await get_tree().process_frame
	print("GAME_FEEL_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón ArtAnimTest / FxDecalTest).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Red de seguridad opcional: en fase roja se desactiva para no imprimir
	# "SCRIPT ERROR: Assertion failed". Habilitar con `-- --strict-assert`.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "GAME_FEEL_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
