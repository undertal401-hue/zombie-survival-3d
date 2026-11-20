extends Node
## ============================================================================
## CUBE FX LIFECYCLE TEST (R1-polish) — contrato del ciclo de vida de los FX.
## ============================================================================
## Cubre los riesgos latentes que encontró la revisión de código de R1:
##
## 1. ESCALA BASE ATÓMICA. Antes, `_cube_base_scales` era una INSTANTÁNEA y
##    el orden "asignar escala → set_type()" era un protocolo implícito entre
##    `Zombie.gd` y `ZombieVisual.gd`. Si la escala del arquetipo cambiaba
##    después, el FX restauraba la instantánea vieja. Ahora existe UNA
##    operación (`set_cube_base_scales`) que fija escala y base a la vez.
##
## 2. UN SOLO DUEÑO DEL CICLO DE VIDA. `telegraph()` creaba un tween por
##    polígono y conectaba `finished` solo al ÚLTIMO: si uno acababa más
##    tarde, podía escribir escala/tinte mientras otro FX ya hab��a empezado.
##    Ahora hay un tween maestro único por efecto.
##
## 3. CANCELACIÓN COMPLETA. `set_type()` mataba los tweens pero no
##    restauraba `_is_telegraphing` ni el tinte: el cubo se quedaba teñido.
##
## Mezcla introspección determinista (el API existe y `Zombie.gd` lo usa) y
## comprobación en runtime (el cubo vuelve a la escala base, el tinte se
## restaura y solo queda un tween vivo).
## ============================================================================

const ZOMBIE_VISUAL: String = "res://03_zombies/ZombieVisual.gd"
const ZOMBIE: String = "res://03_zombies/Zombie.gd"
const ZOMBIE_SCENE: String = "res://03_zombies/Zombie.tscn"

var _failures: Array[String] = []
var _zombie: Node
var _visual: Node
var _body: Polygon2D


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


func _func_body(src: String, header: String, span: int = 30) -> String:
	var start: int = src.find(header)
	if start == -1:
		return ""
	var lines: PackedStringArray = src.substr(start, span * 80).split("\n")
	return "\n".join(lines.slice(0, span))


func _ready() -> void:
	await get_tree().process_frame
	_api_checks()
	await _runtime_checks()
	print("CUBE_FX_LIFECYCLE_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
	_asserts()


## ---------------------------------------------------------------------------
## 1. Introspección: existe la operación atómica y `Zombie.gd` la usa.
## ---------------------------------------------------------------------------
func _api_checks() -> void:
	var zv: String = _read(ZOMBIE_VISUAL)
	_check(zv.contains("func set_cube_base_scales("),
		"ZombieVisual expone set_cube_base_scales(...)")
	var setter_body: String = _func_body(zv, "func set_cube_base_scales(", 30)
	_check(setter_body.contains("_cube_base_scales.clear()")
			or setter_body.contains("_capture_cube_base_scales()"),
		"ZombieVisual.set_cube_base_scales actualiza la base del cubo")

	var zombie_src: String = _read(ZOMBIE)
	var apply_kind: String = _func_body(zombie_src, "func _apply_kind(", 140)
	_check(apply_kind.contains("_apply_cube_scale("),
		"Zombie.gd:_apply_kind() fija la escala del cubo con la operación atómica")
	_check(not apply_kind.contains("body_visual.scale ="),
		"Zombie.gd:_apply_kind() ya no asigna body_visual.scale directamente")
	_check(not apply_kind.contains("nose.scale ="),
		"Zombie.gd:_apply_kind() ya no asigna nose.scale directamente")
	_check(zombie_src.contains("set_cube_base_scales("),
		"Zombie.gd usa set_cube_base_scales(...) (escala + base en una operación)")


## ---------------------------------------------------------------------------
## 2. Runtime: base atómica, un solo tween y cancelación completa.
## ---------------------------------------------------------------------------
func _runtime_checks() -> void:
	_zombie = load(ZOMBIE_SCENE).instantiate()
	add_child(_zombie)
	for i in range(5):
		await get_tree().process_frame
	_visual = _zombie.get_node_or_null("ZombieVisual")
	_body = _zombie.get_node_or_null("Body") as Polygon2D
	if _visual == null or _body == null:
		_check(false, "Runtime: Zombie.tscn expone ZombieVisual y Body")
		return
	_check(true, "Runtime: Zombie.tscn expone ZombieVisual y Body")

	# --- Base atómica: la escala del arquetipo se fija con UNA operación ---
	var has_api: bool = _visual.has_method("set_cube_base_scales")
	_check(has_api, "Runtime: el ZombieVisual instanciado responde set_cube_base_scales")
	if has_api:
		_visual.call("set_cube_base_scales", Vector2(2.0, 2.0), Vector2(2.0, 2.0))
		await get_tree().process_frame
		_check(is_equal_approx(_body.scale.x, 2.0),
			"Runtime: la escala del arquetipo se aplica (%.3f)" % _body.scale.x)

		_visual.call("squash", 0.8, 0.12)
		await _settle(0.45)
		_check(absf(_body.scale.x - 2.0) < 0.002,
			"Runtime: el FX restaura la base NUEVA (%.4f, esperado 2.0)" % _body.scale.x)

	# --- Un solo dueño del ciclo de vida -----------------------------------
	_visual.call("telegraph", 2)
	await get_tree().process_frame
	var live: int = _visual.get("_cube_tweens").size()
	_check(live == 1,
		"Runtime: la telegrafía usa UN tween maestro (%d vivos)" % live)

	# --- Cancelación completa: set_type() restaura tinte y estado ---------
	_visual.call("telegraph", 2)
	await get_tree().process_frame
	_visual.call("set_type", 0)
	await get_tree().process_frame
	var tint: Color = _body.modulate
	_check(absf(tint.r - 1.0) < 0.01 and absf(tint.g - 1.0) < 0.01 \
			and absf(tint.b - 1.0) < 0.01,
		"Runtime: set_type() restaura el tinte del cubo (%s)" % str(tint))
	var telegraphing: bool = bool(_visual.get("_is_telegraphing"))
	_check(not telegraphing,
		"Runtime: set_type() cancela el estado de telegrafía")
	var base_now: Array = _visual.get("_cube_base_scales")
	var expected_base: float = float(base_now[0].x) if base_now.size() > 0 else 1.0
	_check(absf(_body.scale.x - expected_base) < 0.002,
		"Runtime: set_type() restaura la escala base del cubo (%.4f, esperado %.4f)" % [
			_body.scale.x, expected_base])

	# --- Tras el efecto, nada sigue escribiendo la escala -------------------
	await _settle(0.6)
	var settled: float = _body.scale.x
	await _settle(0.3)
	_check(absf(_body.scale.x - settled) < 0.0005,
		"Runtime: ningún tween residual escribe la escala (%.4f -> %.4f)" % [
			settled, _body.scale.x])


func _settle(seconds: float) -> void:
	var frames: int = int(seconds * 60.0)
	for i in range(frames):
		await get_tree().process_frame


func _asserts() -> void:
	if not ("--strict-assert" in OS.get_cmdline_user_args()):
		return
	assert(_failures.is_empty(), "CUBE_FX_LIFECYCLE_TEST: hay fallos")
