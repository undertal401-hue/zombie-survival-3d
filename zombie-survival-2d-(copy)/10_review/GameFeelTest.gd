extends Node
## CAPA 1 (TDD) — contrato de los ÍTEMS 6-9: squash/stretch, telegrafía,
## números de daño flotantes y cámara (look-ahead / shake / punch).
## Se escribe ANTES de la implementación sobre beb9a1a: DEBE FALLAR.
##
## R1 (2026-11-20): el contrato de cámara CAMBIA. El usuario pidió quitar el
## movimiento de cámara con el ratón y conservar el seguimiento. La cámara
## vuelve a ser una Camera2D simple hija del jugador y el look-ahead con
## `get_global_mouse_position()` desaparece (se borró CameraController.gd).
## El resto del contrato (squash, telegrafía, números de daño) sigue igual.
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
const WEAPON_CONTROLLER: String = "res://02_player/weapons/WeaponController.gd"
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

# --- ÍTEM 9. Cámara (R1: sin movimiento por el ratón) -------------------------
#
# R1 (2026-11-20) cambió este contrato. El usuario pidió QUITAR el movimiento
# de cámara con el ratón y CONSERVAR el seguimiento de cámara. Por tanto:
#   - NO debe existir CameraController.gd (era el look-ahead con el ratón);
#   - la Camera2D sigue siendo hija del jugador (seguimiento intacto);
#   - la cámara NO lee la posición del ratón en ningún sitio;
#   - el shake de disparo lo conserva WeaponController (no la cámara).

func _camera_checks() -> void:
	_check(not FileAccess.file_exists(CAMERA_CONTROLLER),
		"R1: no existe game/02_player/CameraController.gd (look-ahead con el ratón eliminado)")
	_check(not _read(PLAYER_SCENE).contains("CameraController"),
		"R1: Player.tscn no asigna CameraController.gd al nodo Camera2D")

	# La cámara sigue al jugador: es hija del nodo Player.
	var scene: String = _read(PLAYER_SCENE)
	var cam_idx: int = scene.find("[node name=\"Camera2D\"")
	_check(cam_idx != -1, "R1: Player.tscn mantiene el nodo Camera2D")
	if cam_idx != -1:
		var next_node: int = scene.find("[node ", cam_idx + 1)
		var end: int = next_node if next_node != -1 else scene.length()
		var block: String = scene.substr(cam_idx, end - cam_idx)
		_check(block.contains("parent=\".\""),
			"R1: la Camera2D es hija del jugador (seguimiento intacto)")
		_check(block.contains("current = true"),
			"R1: la Camera2D es la cámara activa")

	# Ningún punto del proyecto mueve la cámara con el ratón.
	var offenders: Array[String] = []
	for path in _camera_sources():
		var src: String = _read(path)
		if src.contains("get_global_mouse_position"):
			offenders.append(path.get_file())
	_check(offenders.is_empty(),
		"R1: ningún script de cámara lee get_global_mouse_position (%s)" % str(offenders))

	# El shake de disparo lo conserva WeaponController, no la cámara.
	var weapons: String = _read(WEAPON_CONTROLLER)
	_check(weapons.contains("_apply_camera_shake"),
		"R1: WeaponController conserva el shake de cámara al disparar")
	_check(weapons.contains("_shake_base_offset"),
		"R1: WeaponController conserva el offset base del shake")

## Solo los scripts que pilotan la CÁMARA. El jugador y el arma sí apuntan con
## el ratón (eso es el control de apuntado, no el movimiento de cámara).
func _camera_sources() -> Array[String]:
	var out: Array[String] = []
	for path in [CAMERA_CONTROLLER, "res://02_player/Camera.gd",
			"res://02_player/CameraRig.gd", "res://02_player/CameraShake.gd"]:
		if FileAccess.file_exists(path):
			out.append(path)
	return out

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
