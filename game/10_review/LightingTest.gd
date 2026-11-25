extends Node
## ============================================================================
## LIGHTING TEST (R1 + R3 / ADR-006) — contrato de la ILUMINACIÓN REAL.
## ============================================================================
## Verifica que la oscuridad y la luz son las de Godot 4 (luces 2D, sombras
## proyectadas, CanvasModulate) y no los trucos de C0-C3:
##
##   - El CanvasModulate tiene alpha 1.0 y su RGB multiplica la escena.
##     (Antes el alpha era la "energía": el canvas se desvanecía contra el
##     fondo plano y la noche salía lavada.)
##   - La tabla de fase real: day > dawn > dusk > night en oscuridad, y la
##     noche es AZUL mientras el crepúsculo es CÁLIDO.
##   - R3 (ADR-006): el SOL ya NO proyecta sombra direccional. La sombra 2D
##     direccional de Godot no tiene largo (llega hasta el borde de pantalla:
##     `z_far = 2*to_edge_distance + cull_distance` en el motor), asi que las
##     sombras DIURNAS son manchas ACOTADAS (`SunShadowController`). El faro
##     NOCTURNO conserva sus sombras proyectadas reales, que es la parte que
##     el usuario valora expresamente.
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

## Director falso: `SolarLighting` busca un nodo con `current_phase()`.
class FakeDirector extends Node:
	var phase_value: String = "night"

	func current_phase() -> String:
		return phase_value

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
	_initial_grade_checks()
	_cone_texture_checks()
	await _house_occluder_checks()
	_runtime_checks()
	await _finish()

# --- 1. Estructura de la escena ------------------------------------------------

func _scene_checks() -> void:
	var src: String = _read(SOLAR_SCENE)
	_check(src.contains("[node name=\"CanvasModulate\" type=\"CanvasModulate\""),
		"SolarLighting.tscn: existe el CanvasModulate")
	_check(src.contains("[node name=\"SunLight\" type=\"DirectionalLight2D\""),
		"SolarLighting.tscn: existe la DirectionalLight2D")
	_check(src.contains("shadow_enabled = false"),
		"SolarLighting.tscn: el sol NO proyecta la sombra direccional ilimitada")
	_check(src.contains("[node name=\"SunShadows\" type=\"Node2D\""),
		"SolarLighting.tscn: monta las sombras solares ACOTADAS")
	_check(not src.contains("max_distance"),
		"SolarLighting.tscn: fuera el limite ficticio max_distance")
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

# --- 4. Grading inicial (sin destello blanco al arrancar de noche) ------------
#
# El comentario del código decía "para que el grading inicial no arranque
# neutro durante el primer frame", pero `_phase_grade` seguía en WHITE: solo
# se calculaba `_phase_grade_target`. Si la escena arrancaba de noche, el
# primer fotograma era blanco de más.

func _initial_grade_checks() -> void:
	var night_luma: float = _initial_luma_for_phase("night")
	var day_luma: float = _initial_luma_for_phase("day")
	_check(night_luma >= 0.0,
		"grading inicial: se pudo medir el primer fotograma de noche (%.3f)" % night_luma)
	_check(night_luma < day_luma * 0.7,
		"grading inicial: de noche arranca OSCURO, no blanco (%.3f < %.3f)" % [
			night_luma, day_luma * 0.7])


## Color del PRIMER fotograma del CanvasModulate con la fase indicada.
## Se lee sin dejar pasar un frame: ese es el valor inicial.
func _initial_luma_for_phase(phase: String) -> float:
	var sandbox := Node.new()
	sandbox.name = "InitialGradeSandbox"
	get_tree().root.add_child(sandbox)

	# Director falso: `SolarLighting` busca un nodo con `current_phase()`.
	var director := FakeDirector.new()
	director.name = "WorldDirector"
	director.phase_value = phase
	sandbox.add_child(director)

	var solar: Node = load(SOLAR_SCENE).instantiate()
	sandbox.add_child(solar)
	var cm: CanvasModulate = solar.get_node_or_null("CanvasModulate") as CanvasModulate
	var luma: float = -1.0
	if cm != null:
		luma = _luma(cm.color)
		if absf(cm.color.a - 1.0) > 0.001:
			_check(false, "grading inicial: el alpha del CanvasModulate es 1.0")
		else:
			_check(true, "grading inicial: el alpha del CanvasModulate es 1.0")
	sandbox.queue_free()
	return luma

# --- 5. Geometría del cono del faro (validación por píxeles) ------------------
#
# El mapa de luz es un cono con el VÉRTICE en el centro que se abre hacia +X
# (la dirección de apuntado) y se desvanece con la distancia. Antes solo se
# comprobaban las dimensiones del fichero.

func _cone_texture_checks() -> void:
	var tex: Texture2D = load(CONE_TEXTURE) as Texture2D
	if tex == null:
		_check(false, "cono del faro: se puede cargar light_cone.png")
		return
	var img: Image = tex.get_image()
	if img == null:
		_check(false, "cono del faro: la textura tiene imagen")
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	_check(w == 512 and h == 256,
		"cono del faro: 512x256 (%dx%d)" % [w, h])
	if w != 512 or h != 256:
		return
	var cx: int = w / 2
	var cy: int = h / 2
	var alpha_at := func(x: int, y: int) -> float:
		return img.get_pixel(clampi(x, 0, w - 1), clampi(y, 0, h - 1)).a
	# Detrás del vértice no hay luz.
	_check(alpha_at.call(cx - 12, cy) <= 0.001,
		"cono del faro: transparente DETRÁS del vértice")
	# Justo delante del vértice sí hay haz.
	_check(alpha_at.call(cx + 12, cy) > 0.5,
		"cono del faro: haz justo por delante del vértice (a %.2f)" % alpha_at.call(cx + 12, cy))
	# Se abre hacia +X: el MISMO desvío lateral está iluminado lejos del
	# vértice (cono ancho) pero no cerca de él (cono estrecho).
	var lit_near: bool = alpha_at.call(cx + 30, cy + 20) > 0.001
	var lit_far: bool = alpha_at.call(cx + 170, cy + 20) > 0.001
	_check(lit_far and not lit_near,
		"cono del faro: se ABRE hacia +X (mismo desvío: cerca %.3f, lejos %.3f)" % [
			alpha_at.call(cx + 30, cy + 20), alpha_at.call(cx + 170, cy + 20)])
	# Simetría vertical respecto al eje del haz.
	var up: float = alpha_at.call(cx + 60, cy - 18)
	var down: float = alpha_at.call(cx + 60, cy + 18)
	_check(absf(up - down) < 0.01,
		"cono del faro: simetría vertical (%.3f vs %.3f)" % [up, down])
	# El borde del haz se desvanece: nada de escalones duros.
	_check(alpha_at.call(cx + 60, cy) > alpha_at.call(cx + 60, cy - 60),
		"cono del faro: el borde se desvanece")

# --- 6. Oclusores de la casa: la puerta debe dejar pasar el faro -------------
#
# La casa usaba UN LightOccluder2D con el rectángulo completo: el haz del faro
# no entraba por la puerta y las sombras no correspondían a la geometría
# visible. Ahora hay un oclusor por segmento de muro, con el hueco de la
# puerta ABIERTO.

func _house_occluder_checks() -> void:
	var house_script: Script = load("res://05_house/House.gd") as Script
	if house_script == null:
		_check(false, "casa: se puede cargar House.gd")
		return
	var house: Node = house_script.new()
	house.name = "OccluderProbeHouse"
	add_child(house)
	await get_tree().process_frame

	# Solo verificar oclusores de Floor0 (planta exterior) para el hueco de puerta.
	# Las plantas superiores (Floor1, Floor2) son interiores y tienen muros completos.
	var floor0: Node = house.get_node_or_null("Floor0")
	_check(floor0 != null, "casa: Floor0 existe")
	
	var occluders: Array[LightOccluder2D] = []
	_collect_occluders(floor0, occluders)
	_check(occluders.size() >= 3,
		"casa: Floor0 tiene oclusor por segmento de muro (%d)" % occluders.size())

	var size: Vector2 = house.get("size")
	# Puerta por defecto: BOTTOM -> el hueco está en el borde inferior.
	var door_point: Vector2 = Vector2(0.0, size.y * 0.5)
	_check(not _point_in_any_occluder(occluders, door_point),
		"casa: el hueco de la PUERTA deja pasar la luz (Floor0)")
	# Un muro sí debe bloquear.
	var wall_point: Vector2 = Vector2(size.x * 0.5, 0.0)
	_check(_point_in_any_occluder(occluders, wall_point),
		"casa: un MURO sí bloquea la luz (Floor0)")
	
	# Verificar que Floor1/Floor2 existen pero no se les exige hueco de puerta
	var floor1: Node = house.get_node_or_null("Floor1")
	var floor2: Node = house.get_node_or_null("Floor2")
	_check(floor1 != null, "casa: Floor1 existe")
	_check(floor2 != null, "casa: Floor2 existe")
	
	house.queue_free()

func _collect_occluders(node: Node, out: Array[LightOccluder2D]) -> void:
	for child in node.get_children():
		if child is LightOccluder2D:
			out.append(child as LightOccluder2D)
		_collect_occluders(child, out)

func _point_in_any_occluder(occluders: Array[LightOccluder2D], point: Vector2) -> bool:
	for occ in occluders:
		if occ == null or not is_instance_valid(occ):
			continue
		var poly: OccluderPolygon2D = occ.occluder
		if poly == null:
			continue
		var local: Vector2 = occ.to_local(point)
		if Geometry2D.is_point_in_polygon(local, poly.polygon):
			return true
	return false

# --- 7. Comportamiento en runtime ---------------------------------------------

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
	_check(sun != null and not sun.shadow_enabled,
		"runtime: el sol NO proyecta la sombra direccional ilimitada (R3)")
	if sun != null:
		_check(is_equal_approx(sun.color.a, 1.0),
			"runtime: el color del sol es opaco (alpha 1.0)")
	# El faro NOCTURNO es intocable: conserva sus sombras reales.
	var player_scene: String = _read(PLAYER_SCENE)
	_check(player_scene.contains("shadow_enabled = true"),
		"runtime: el faro del jugador conserva sus sombras reales")
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
