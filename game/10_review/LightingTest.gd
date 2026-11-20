extends Node
## ============================================================================
## LIGHTING TEST (R1) — contrato de la ILUMINACIÓN REAL.
## ============================================================================
## Verifica que la oscuridad y la luz son de verdad las de Godot 4 (luces 2D,
## sombras proyectadas, CanvasModulate) y no los trucos de C0-C3:
##
##   - El CanvasModulate tiene alpha 1.0 y su RGB multiplica la escena.
##     (Antes el alpha era la "energía": el canvas se desvanecía contra el
##     fondo plano y la noche salía lavada.)
##   - La tabla de fase real: day > dawn > dusk > night en oscuridad, y la
##     noche es AZUL mientras el crepúsculo es CÁLIDO.
##   - DirectionalLight2D con sombras proyectadas activadas.
##   - Flashlight (PointLight2D) con textura de cono y sombras propias.
##   - MuzzleLight para el fogonazo.
##   - Shader NightGrade (viñeta + grano) montado en pantalla.
##   - NO hay sombras falsas (grupo `pixel_shadows` / PixelShadowController).
## ============================================================================

const SOLAR_GD: String = "res://08_ui/SolarLighting.gd"
const SOLAR_SCENE: String = "res://08_ui/SolarLighting.tscn"
const PLAYER_SCENE: String = "res://02_player/Player.tscn"
const NIGHT_GRADE_SHADER: String = "res://assets/shaders/NightGrade.gdshader"
const NIGHT_GRADE_MATERIAL: String = "res://08_ui/NightGradeMaterial.tres"
const CONE_TEXTURE: String = "res://assets/art/lights/light_cone.png"
const HALO_TEXTURE: String = "res://assets/art/lights/light_halo.png"

var _failures: Array[String] = []
var _sandbox: Node
var _solar: Node

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
	_scene_checks()
	_shader_checks()
	await _phase_table_checks()
	_runtime_checks()
	await _finish()

# --- 1. Estructura de la escena ------------------------------------------------

func _scene_checks() -> void:
	var src: String = _read(SOLAR_SCENE)
	_check(src.contains("[node name=\"CanvasModulate\" type=\"CanvasModulate\""),
		"SolarLighting.tscn: existe el CanvasModulate")
	_check(src.contains("[node name=\"SunLight\" type=\"DirectionalLight2D\""),
		"SolarLighting.tscn: existe la DirectionalLight2D")
	_check(src.contains("shadow_enabled = true"),
		"SolarLighting.tscn: la DirectionalLight2D proyecta sombras")
	_check(src.contains("NightGradeRect"),
		"SolarLighting.tscn: montada la capa de acabado nocturna")
	_check(src.contains("light_mask = 0"),
		"SolarLighting.tscn: la capa de pantalla no recibe luces del mundo")

	var player_src: String = _read(PLAYER_SCENE)
	_check(player_src.contains("[node name=\"Flashlight\" type=\"PointLight2D\""),
		"Player.tscn: existe el faro (PointLight2D)")
	_check(player_src.contains("[node name=\"MuzzleLight\" type=\"PointLight2D\""),
		"Player.tscn: existe la luz de fogonazo")
	_check(player_src.contains("light_cone.png"),
		"Player.tscn: el faro usa la textura del cono")
	_check(player_src.contains("shadow_enabled = true"),
		"Player.tscn: el faro proyecta sombras propias")
	_check(player_src.contains("range_layer_max = 0"),
		"Player.tscn: el faro solo afecta al canvas del mundo (no al HUD)")

# --- 2. Shader de acabado nocturno --------------------------------------------

func _shader_checks() -> void:
	_check(FileAccess.file_exists(NIGHT_GRADE_SHADER),
		"existe assets/shaders/NightGrade.gdshader")
	_check(FileAccess.file_exists(NIGHT_GRADE_MATERIAL),
		"existe 08_ui/NightGradeMaterial.tres")
	var shader: Shader = load(NIGHT_GRADE_SHADER) as Shader
	var mat: ShaderMaterial = load(NIGHT_GRADE_MATERIAL) as ShaderMaterial
	_check(shader != null and mat != null and mat.shader == shader,
		"NightGradeMaterial.tres apunta a NightGrade.gdshader")
	var source: String = _read(NIGHT_GRADE_SHADER)
	_check(source.contains("night_amount"),
		"NightGrade.gdshader declara el uniform night_amount")
	_check(source.contains("vignette_strength"),
		"NightGrade.gdshader declara la viñeta")
	_check(source.contains("grain_strength"),
		"NightGrade.gdshader declara el grano")
	_check(FileAccess.file_exists(CONE_TEXTURE) and FileAccess.file_exists(HALO_TEXTURE),
		"existen los mapas de luz (cono + halo)")

# --- 3. Tabla de fase real -----------------------------------------------------

func _phase_table_checks() -> void:
	var solar_script: Script = load(SOLAR_GD) as Script
	if solar_script == null:
		_check(false, "carga SolarLighting.gd")
		return
	_sandbox = Node.new()
	_sandbox.name = "LightingSandbox"
	get_tree().root.add_child(_sandbox)
	_solar = load(SOLAR_SCENE).instantiate()
	_sandbox.add_child(_solar)
	await get_tree().process_frame

	var day: Color = _grade("day")
	var dawn: Color = _grade("dawn")
	var dusk: Color = _grade("dusk")
	var night: Color = _grade("night")
	_check(_luma(day) > 0.99, "fase day: sin oscurecer (luma %.3f)" % _luma(day))
	_check(_luma(night) < _luma(day) * 0.6,
		"fase night: claramente más oscura que day (%.3f < %.3f)" % [_luma(night), _luma(day)])
	_check(_luma(night) > 0.15,
		"fase night: MEDIA luz, no negro (luma %.3f > 0.15)" % _luma(night))
	_check(_luma(dusk) > _luma(night),
		"fase dusk: más luminosa que night (%.3f > %.3f)" % [_luma(dusk), _luma(night)])
	_check(night.b > night.r,
		"fase night: tinte AZUL (b %.2f > r %.2f)" % [night.b, night.r])
	_check(dusk.r > dusk.b,
		"fase dusk: tinte CÁLIDO (r %.2f > b %.2f)" % [dusk.r, dusk.b])

	# Ganancia de sol: de noche el sol no debe proyectar nada.
	_check(_float_call("phase_sun_gain", "night") <= 0.0,
		"fase night: el sol no aporta energía (0)")
	_check(_float_call("phase_sun_gain", "day") > 1.0,
		"fase day: el sol aporta energía real (%.2f)" % _float_call("phase_sun_gain", "day"))
	# Faro: apagado de día, encendido de noche.
	_check(_float_call("phase_flashlight_energy", "day") <= 0.0,
		"fase day: el faro está apagado")
	_check(_float_call("phase_flashlight_energy", "night") >= 1.0,
		"fase night: el faro está al máximo (%.2f)" % _float_call("phase_flashlight_energy", "night"))

func _grade(phase: String) -> Color:
	if _solar == null or not is_instance_valid(_solar):
		return Color.WHITE
	if not _solar.has_method("phase_grade_for"):
		return Color.WHITE
	var value: Variant = _solar.call("phase_grade_for", phase)
	if value is Color:
		return value as Color
	return Color.WHITE

func _float_call(method: String, phase: String) -> float:
	if _solar == null or not is_instance_valid(_solar):
		return -1.0
	if not _solar.has_method(method):
		return -1.0
	var value: Variant = _solar.call(method, phase)
	if value is float or value is int:
		return float(value)
	return -1.0

func _luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

# --- 4. Comportamiento en runtime ---------------------------------------------

func _runtime_checks() -> void:
	if _solar == null or not is_instance_valid(_solar):
		_check(false, "SolarLighting instanciado")
		return
	var cm: CanvasModulate = _solar.get_node_or_null("CanvasModulate") as CanvasModulate
	_check(cm != null, "runtime: CanvasModulate accesible")
	if cm != null:
		_check(is_equal_approx(cm.color.a, 1.0),
			"runtime: el alpha del CanvasModulate es 1.0 (la oscuridad es COLOR)")
		var luma: float = _luma(cm.color)
		_check(luma < 0.95,
			"runtime: el CanvasModulate atenúa la escena (luma %.3f)" % luma)
	var sun: DirectionalLight2D = _solar.get_node_or_null("SunLight") as DirectionalLight2D
	_check(sun != null and sun.shadow_enabled,
		"runtime: la DirectionalLight2D tiene sombras activadas")
	if sun != null:
		_check(is_equal_approx(sun.color.a, 1.0),
			"runtime: el color del sol es opaco (alpha 1.0)")
	var grade_rect: ColorRect = _solar.get_node_or_null("GlareLayer/NightGradeRect") as ColorRect
	_check(grade_rect != null, "runtime: la capa NightGradeRect existe")
	if grade_rect != null:
		var mat: ShaderMaterial = grade_rect.material as ShaderMaterial
		_check(mat != null, "runtime: NightGradeRect usa un ShaderMaterial")
		if mat != null:
			var amount: Variant = mat.get_shader_parameter("night_amount")
			_check(amount is float,
				"runtime: el uniform night_amount está disponible para el shader")

	# Sin sombras falsas en ninguna escena.
	for path in ["res://02_player/Player.tscn", "res://03_zombies/Zombie.tscn"]:
		_check(not _read(path).contains("pixel_shadows"),
			"runtime: %s sin grupo 'pixel_shadows'" % path.get_file())
	_check(not _read(SOLAR_GD).contains("PixelShadowController"),
		"runtime: SolarLighting.gd sin PixelShadowController")

# --- Cierre --------------------------------------------------------------------

func _finish() -> void:
	if is_instance_valid(_solar):
		_solar.queue_free()
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	for i in range(6):
		await get_tree().process_frame
	print("LIGHTING_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "LIGHTING_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
