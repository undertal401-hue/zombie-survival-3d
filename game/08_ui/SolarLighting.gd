extends Node2D

## Solar Lighting - 2D Survival Sandbox
## ============================================================================
## R1 (2026-11-20): iluminación REAL de Godot, no "grading" cosmético.
## ============================================================================
## Antes (C0-C3) la oscuridad salía de dos trucos flojos:
##   1. el CanvasModulate usaba su ALPHA como intensidad -> el canvas se
##      desvanecía contra el color de fondo plano y la "noche" salía lavada;
##   2. las sombras eran polígonos falsos (`pixel_shadows`) desplazados a mano.
## Ahora:
##   - la CanvasModulate tiene alpha SIEMPRE 1.0 y su RGB multiplica la
##     escena: la noche tiñe de azul oscuro de verdad;
##   - la DirectionalLight2D tiene energía real por fase y proyecta sombras
##     (LightOccluder2D del jugador, zombis y casa);
##   - el faro del jugador es una PointLight2D con textura de cono y sombras
##     propias: de día apagada, de noche al máximo;
##   - hay una capa de acabado (viñeta + grano) sobre la escena, bajo el HUD.
##
## Contrato que se conserva (no cambiar sin tocar los arneses):
##   - `ambient_energy` sigue siendo 0..1.5 y lo sigue mandando WorldDirector.
##     NO se usa como alpha del CanvasModulate; se usa como factor de ambiente
##     (con suelo) para que el clima y el bosque sigan oscureciendo.
##   - `apply_state(ambient, sun, angle, tint, duration)` conserva su firma.
##   - `solar_direction_changed` sigue emitiéndose.
## ============================================================================

class_name SolarLighting

## --- Tabla de iluminación por fase (R1) -----------------------------------
## Multiplicadores REALES de oscuridad aplicados al CanvasModulate.
##   day   -> la escena se ve tal cual.
##   dawn  -> amanecer cálido, aún legible.
##   dusk  -> atardecer rojo apagado.
##   night -> MEDIA luz azul (0.42-0.56 antes de normalizar): el mundo se
##            sigue leyendo sin faro y el cono del faro destaca sobre él.
const GRADE_DAWN: Color = Color(0.92, 0.82, 0.72)
const GRADE_DAY: Color = Color(1.00, 1.00, 1.00)
const GRADE_DUSK: Color = Color(0.68, 0.48, 0.40)
const GRADE_NIGHT: Color = Color(0.42, 0.46, 0.56)

## Ganancia del DirectionalLight2D por fase. WorldDirector manda una energía de
## sol muy baja (0.16-0.23) pensada para el grading antiguo: con sombras
## proyectadas esa energía no dibuja nada visible. Aquí se amplifica.
const PHASE_SUN_GAIN: Dictionary = {
	"dawn": 1.8,
	"day": 3.4,
	"dusk": 1.4,
	"night": 0.0,
}

## Energía del faro por fase: apagado de día, medio en crepúsculo, pleno de noche.
const PHASE_FLASHLIGHT: Dictionary = {
	"dawn": 0.45,
	"day": 0.0,
	"dusk": 1.05,
	"night": 1.60,
}

## Referencia de `ambient_energy` para el día claro (WorldDirector envía 0.86-0.95).
const AMBIENT_REFERENCE: float = 0.95
## Suelo del factor de ambiente: ni el clima ni el bosque hunden la escena más
## de un 28 %, para que la noche siga siendo legible sin faro.
const AMBIENT_FLOOR: float = 0.72

## Suavizado exponencial del grading (misma familia que WorldDirector).
const GRADE_SMOOTH_TAU: float = 0.6
const GRADE_CACHE_INTERVAL: float = 0.25
## Suavizado del faro (segundos): evita el salto brusco al anochecer.
const FLASHLIGHT_SMOOTH_TAU: float = 0.35

## --- Faro y fogonazo -------------------------------------------------------
const FLASHLIGHT_NODE: String = "Flashlight"
const MUZZLE_LIGHT_NODE: String = "MuzzleLight"
const MUZZLE_FLASH_TIME: float = 0.07
const MUZZLE_FLASH_ENERGY: float = 2.4

@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var sun_light: DirectionalLight2D = $SunLight
@onready var glare_rect: ColorRect = $GlareLayer/GlareRect
@onready var night_grade_rect: ColorRect = $GlareLayer/NightGradeRect
## Sombras solares ACOTADAS (R3 / ADR-006). Es opcional: si el nodo no esta
## en la escena, el juego sigue funcionando (solo se pierde la sombra diurna).
@onready var sun_shadows: Node2D = get_node_or_null("SunShadows") as Node2D

## Parámetros ajustables (expuestos en inspector)
@export_group("Ambiente Base")
@export var ambient_color: Color = Color(0.95, 0.92, 0.85, 1.0)  # Pálido, cálido, sucio
@export var ambient_energy: float = 0.85  # Intensidad global (0-1)

@export_group("Sol Direccional (DirectionalLight2D)")
@export var sun_color: Color = Color(1.0, 0.95, 0.82, 1.0)  # Cálido, opaco
@export var sun_energy: float = 0.18
## R3 (ADR-006): sombras DIURNAS acotadas (manchas). La sombra direccional
## 2D de Godot NO tiene largo: llega hasta el borde de pantalla, asi que el
## sol deja de proyectarla y la sustituye `SunShadowController`.
@export var bounded_shadows_enabled: bool = true
@export var shadow_filter: int = 1  # 0=PCF3, 1=PCF5, 2=PCF7, 3=PCF13 (suavizado)

@export_group("Dirección Solar Global (+X = Este, +Y = Sur)")
@export var solar_angle: float = 0.0  # Rad: 0 = Este, PI/2 = Sur, PI = Oeste, -PI/2 = Norte

var _base_ambient_energy: float
var _base_sun_energy: float
## Tinte ambiental controlado por WorldDirector (clima / fase del día).
var _tint: Color = Color.WHITE
var _light_tween: Tween = null

## Estado del color grading por fase.
var _phase: String = "day"
var _phase_grade: Color = Color.WHITE
var _phase_grade_target: Color = Color.WHITE
var _grade_director: Node = null
var _grade_cache_t: float = 0.0
## Ultimo estado ya publicado al controlador de sombras acotadas.
var _shadow_phase_sent: String = ""
var _shadow_angle_sent: float = -999.0

## Faro del jugador (PointLight2D) y fogonazo de disparo.
var _player_node: Node2D = null
var _flashlight: PointLight2D = null
var _muzzle_light: PointLight2D = null
var _flashlight_energy: float = 0.0
var _flashlight_target: float = 0.0
var _muzzle_timer: float = 0.0

# Señal para notificar cambios de dirección solar a otros sistemas
signal solar_direction_changed(angle_rad: float, angle_deg: float)

func _ready() -> void:
	# Guardar valores base para posible reset
	_base_ambient_energy = ambient_energy
	_base_sun_energy = sun_energy
	_tint = Color.WHITE

	# Configurar nodos
	_setup_canvas_modulate()
	_setup_sun_light()

	# Posicionar sol según dirección actual
	_update_sun_position()

	# Resolver la fase real ANTES del primer apply para que el grading
	# inicial no arranque neutro durante el primer frame. No basta con
	# calcular el objetivo: el valor ACTUAL (`_phase_grade`) debe arrancar
	# ya en ese tinte, si no el primer fotograma es blanco de más y se ve
	# un destello al cargar de noche.
	_refresh_grade_target()
	_phase_grade = _phase_grade_target
	_apply_lighting()

	# El resplandor debe seguir circular si cambia el tamaño de la ventana.
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)

func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.disconnect(_on_viewport_resized)
	if _light_tween != null and _light_tween.is_valid():
		_light_tween.kill()

## Grading por fase: sondeo barato del director + suavizado exponencial.
## El Tween de apply_state sigue gobernando clima/energía/ángulo; aquí solo
## se matiza el CanvasModulate, sin tocar la API pública ni el glare.
func _process(delta: float) -> void:
	_grade_cache_t -= delta
	if _grade_cache_t <= 0.0:
		_grade_cache_t = GRADE_CACHE_INTERVAL
		_refresh_grade_target()
	var next_grade: Color = _phase_grade.lerp(
		_phase_grade_target, 1.0 - exp(-delta / GRADE_SMOOTH_TAU)
	)
	if not _grade_close(next_grade, _phase_grade):
		_phase_grade = next_grade
		_apply_lighting()

	_update_flashlight(delta)
	_update_muzzle(delta)
	_update_sun_shadows()

## La fase y el angulo del sol se mandan al controlador de sombras acotadas.
## De noche la mancha es invisible (alpha 0) y el sol no aporta energia: el
## unico cono de luz con sombras es el faro del jugador.
##
## Solo se manda cuando CAMBIA: si se reenviara cada frame, pisaria cualquier
## ajuste que otro sistema hiciese sobre el controlador.
func _update_sun_shadows() -> void:
	if sun_shadows == null or not is_instance_valid(sun_shadows):
		return
	if not sun_shadows.has_method("set_sun_state"):
		return
	if _phase == _shadow_phase_sent and is_equal_approx(solar_angle, _shadow_angle_sent):
		return
	_shadow_phase_sent = _phase
	_shadow_angle_sent = solar_angle
	sun_shadows.call("set_sun_state", _phase, solar_angle)

func _grade_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.0005 and absf(a.g - b.g) < 0.0005 and absf(a.b - b.b) < 0.0005

func _refresh_grade_target() -> void:
	if _grade_director == null or not is_instance_valid(_grade_director):
		_grade_director = _find_director()
	var phase: String = "day"
	if _grade_director != null and is_instance_valid(_grade_director) and _grade_director.has_method("current_phase"):
		phase = String(_grade_director.call("current_phase"))
	_phase = phase
	_phase_grade_target = _grade_for_phase(phase)

func _find_director() -> Node:
	var parent := get_parent()
	if parent != null:
		for node_name in ["WaveManager", "HordeManager", "WorldDirector"]:
			var candidate := parent.get_node_or_null(node_name)
			if candidate != null:
				return candidate
	for candidate in get_tree().get_nodes_in_group("world_director"):
		if is_instance_valid(candidate) and candidate.has_method("current_phase"):
			return candidate
	for path in ["/root/Main/WaveManager", "/root/WorldDirector"]:
		var candidate: Node = get_node_or_null(path)
		if candidate != null and candidate.has_method("current_phase"):
			return candidate
	return null

func _grade_for_phase(phase: String) -> Color:
	match phase:
		"dawn":
			return GRADE_DAWN
		"dusk":
			return GRADE_DUSK
		"night":
			return GRADE_NIGHT
		"day":
			return GRADE_DAY
		_:
			return Color.WHITE

## API pública: el arnés de iluminación consulta la tabla por fase.
func phase_grade_for(phase: String) -> Color:
	return _grade_for_phase(String(phase).to_lower())

## Ganancia del sol para la fase indicada (o la actual si se omite).
## 0 de noche: el sol no aporta nada y solo queda el faro.
func phase_sun_gain(phase: String = "") -> float:
	var key: String = String(phase).to_lower()
	if key == "":
		key = _phase
	return float(PHASE_SUN_GAIN.get(key, 1.0))

## Energía de faro objetivo para la fase indicada (o la actual si se omite).
## 0 de día, pleno de noche.
func phase_flashlight_energy(phase: String = "") -> float:
	var key: String = String(phase).to_lower()
	if key == "":
		key = _phase
	return float(PHASE_FLASHLIGHT.get(key, 0.0))

## Cuánta noche se aplica al acabado de pantalla (0..1).
func night_amount() -> float:
	match _phase:
		"night":
			return 1.0
		"dusk":
			return 0.55
		"dawn":
			return 0.25
		_:
			return 0.0

func _setup_canvas_modulate() -> void:
	# Alpha SIEMPRE 1.0: la oscuridad es un multiplicador de COLOR, no una
	# transparencia. Con alpha < 1 el canvas se fundía con el fondo plano.
	canvas_modulate.color = Color(ambient_color.r, ambient_color.g, ambient_color.b, 1.0)

func _setup_sun_light() -> void:
	sun_light.color = sun_color
	sun_light.energy = sun_energy
	# R3 (ADR-006): la sombra DIRECCIONAL 2D de Godot no tiene largo. En el
	# motor el `z_far` del atlas es `to_edge_distance * 2 + cull_distance` y el
	# fragmento queda en sombra si su profundidad supera la del oclusor: la
	# sombra se prolonga hasta el BORDE DE LA PANTALLA en la direccion opuesta
	# a la luz. `max_distance` NO la acorta (solo amplia el rect de oclusores
	# considerados y suma al z_far) y `Light2D.shadow_max_distance` no existe
	# en Godot 4. Por eso el sol deja de proyectar sombra y las sombras
	# DIURNAS las dibuja `SunShadowController` como manchas acotadas.
	#
	# El faro NOCTURNO (PointLight2D del jugador) NO se toca: conserva sus
	# sombras reales del motor, acotadas por la textura del cono.
	sun_light.shadow_enabled = false
	sun_light.shadow_filter = shadow_filter
	# light_mode ya configurado en la escena (0 = ADD)
	if sun_shadows != null and is_instance_valid(sun_shadows):
		if sun_shadows.has_method("set_bounded_shadows_enabled"):
			sun_shadows.call("set_bounded_shadows_enabled", bounded_shadows_enabled)

func _apply_lighting() -> void:
	# El tinte del clima aporta el MATIZ; la tabla de fase decide la
	# OSCURIDAD. Sin normalizar el tinte la noche se oscurece dos veces
	# (tinte x grade) y el mundo queda negro en vez de "medio oscuro".
	var tint: Color = _hue_only(_tint)
	var factor: float = _ambient_factor()
	canvas_modulate.color = Color(
		ambient_color.r * tint.r * _phase_grade.r * factor,
		ambient_color.g * tint.g * _phase_grade.g * factor,
		ambient_color.b * tint.b * _phase_grade.b * factor,
		1.0
	)
	sun_light.energy = sun_energy * phase_sun_gain()
	_update_glare()
	_update_night_grade()

## Normaliza el tinte para conservar solo su matiz (sin oscurecer de más).
func _hue_only(tint: Color) -> Color:
	var peak: float = maxf(maxf(tint.r, tint.g), tint.b)
	if peak <= 0.001:
		return Color.WHITE
	return Color(tint.r / peak, tint.g / peak, tint.b / peak, 1.0)

## Factor de ambiente con suelo: el clima (lluvia/niebla) y el bosque bajan
## la escena, pero nunca la hunden hasta hacerla ilegible.
func _ambient_factor() -> float:
	var f: float = clampf(ambient_energy / AMBIENT_REFERENCE, 0.0, 1.0)
	return lerpf(AMBIENT_FLOOR, 1.0, f)

## El resplandor era un shader huérfano. Ahora sigue al sol en pantalla y
## se apaga con la energía solar, sin coste cuando no hay luz directa.
func _on_viewport_resized() -> void:
	_update_glare()

func _update_glare() -> void:
	if glare_rect == null or glare_rect.material == null:
		return
	var mat: Material = glare_rect.material
	if not (mat is ShaderMaterial):
		return
	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	var sun_uv: Vector2 = Vector2(
		0.5 + cos(solar_angle) * 0.45,
		0.5 + sin(solar_angle) * 0.35
	)
	var viewport_size: Vector2 = get_viewport_rect().size
	var viewport_aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	shader_mat.set_shader_parameter("sun_screen_pos", sun_uv)
	shader_mat.set_shader_parameter("glare_intensity", clampf(sun_energy * 0.9, 0.0, 0.30))
	shader_mat.set_shader_parameter("viewport_aspect", viewport_aspect)

## Viñeta + grano de la noche. El shader recibe la intensidad de noche; de
## día es completamente transparente.
func _update_night_grade() -> void:
	if night_grade_rect == null or night_grade_rect.material == null:
		return
	var mat: Material = night_grade_rect.material
	if not (mat is ShaderMaterial):
		return
	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	shader_mat.set_shader_parameter("night_amount", night_amount())

func _update_sun_position() -> void:
	# DirectionalLight2D en Godot 4 usa rotación para definir la dirección
	# La luz apunta en la dirección de su rotación (rotación 0 = hacia la derecha/Este)
	# solar_angle: 0 = Este, PI/2 = Sur, PI = Oeste, -PI/2 = Norte
	# Sol en Este (0) -> luz viaja hacia Este -> rotación = 0 -> sombras al Oeste
	# Sol en Oeste (PI) -> luz viaja hacia Oeste -> rotación = PI -> sombras al Este
	var light_rot := solar_angle  # La luz apunta en la dirección del sol
	sun_light.rotation = light_rot

	# Emitir señal de cambio de dirección
	solar_direction_changed.emit(solar_angle, rad_to_deg(solar_angle))

func _set_sun_rotation() -> void:
	# Variante silenciosa para interpolaciones (evita un signal por frame).
	sun_light.rotation = solar_angle

## --- Faro del jugador -----------------------------------------------------

## Localiza el jugador (y su faro) una sola vez; el faro vive en Player.tscn
## como hijo del jugador, así que rota con el apuntado y proyecta sombras.
func _resolve_player() -> void:
	if _player_node != null and is_instance_valid(_player_node):
		return
	var tree := get_tree()
	var found: Node = null
	if tree != null:
		found = tree.get_first_node_in_group("player")
	if found == null:
		found = get_node_or_null("../Player")
	if not (found is Node2D):
		return
	_player_node = found as Node2D
	_flashlight = _player_node.get_node_or_null(FLASHLIGHT_NODE) as PointLight2D
	_muzzle_light = _player_node.get_node_or_null(MUZZLE_LIGHT_NODE) as PointLight2D
	_connect_weapons(_player_node)

## Conecta el fogonazo al disparo real del arma (no a un temporizador guesses).
func _connect_weapons(player: Node2D) -> void:
	var weapons: Node = player.get_node_or_null("WeaponController")
	if weapons == null or not is_instance_valid(weapons):
		return
	if weapons.has_signal("fire_requested"):
		var callback := Callable(self, "_on_weapon_fired")
		if not weapons.is_connected("fire_requested", callback):
			weapons.connect("fire_requested", callback)

func _on_weapon_fired(_weapon = null, _from = null, _to = null) -> void:
	_muzzle_timer = MUZZLE_FLASH_TIME

func _update_flashlight(delta: float) -> void:
	_resolve_player()
	_flashlight_target = phase_flashlight_energy()
	var k: float = 1.0 - exp(-delta / FLASHLIGHT_SMOOTH_TAU)
	_flashlight_energy = lerpf(_flashlight_energy, _flashlight_target, k)
	if _flashlight == null or not is_instance_valid(_flashlight):
		return
	_flashlight.energy = _flashlight_energy

func _update_muzzle(delta: float) -> void:
	if _muzzle_timer > 0.0:
		_muzzle_timer = maxf(_muzzle_timer - delta, 0.0)
	if _muzzle_light == null or not is_instance_valid(_muzzle_light):
		return
	if _muzzle_timer > 0.0:
		_muzzle_light.energy = MUZZLE_FLASH_ENERGY * (_muzzle_timer / MUZZLE_FLASH_TIME)
	else:
		_muzzle_light.energy = 0.0

## API pública para control externo

func set_ambient_energy(e: float) -> void:
	ambient_energy = clampf(e, 0.0, 1.5)
	_apply_lighting()

func set_sun_energy(e: float) -> void:
	sun_energy = clampf(e, 0.0, 1.0)
	_apply_lighting()

func set_solar_angle(angle_rad: float) -> void:
	solar_angle = angle_rad
	_update_sun_position()
	_apply_lighting()

## API usada por WorldDirector: aplica energía ambiente, energía solar, ángulo
## y tinte de clima en una única transición suave. Los setters anteriores siguen
## disponibles para Main.gd y no se han eliminado.
func apply_state(ambient: float, sun: float, angle_rad: float,
		tint: Color = Color.WHITE, duration: float = 0.8) -> void:
	var target_amb: float = clampf(ambient, 0.0, 1.5)
	var target_sun: float = clampf(sun, 0.0, 1.0)
	var target_tint := Color(tint.r, tint.g, tint.b, 1.0)
	if _light_tween != null and _light_tween.is_valid():
		_light_tween.kill()
	if duration <= 0.01:
		_set_state(target_amb, target_sun, angle_rad, target_tint)
		_emit_solar_direction()
		return
	var from_amb: float = ambient_energy
	var from_sun: float = sun_energy
	var from_angle: float = solar_angle
	var from_tint: Color = _tint
	_light_tween = create_tween()
	_light_tween.tween_method(
		_interpolate_state.bind(from_amb, from_sun, from_angle, from_tint,
			target_amb, target_sun, angle_rad, target_tint),
		0.0, 1.0, duration
	)
	_light_tween.tween_callback(_emit_solar_direction)

func _interpolate_state(t: float, a0: float, s0: float, ang0: float, tint0: Color,
		a1: float, s1: float, ang1: float, tint1: Color) -> void:
	ambient_energy = lerpf(a0, a1, t)
	sun_energy = lerpf(s0, s1, t)
	solar_angle = lerpf(ang0, ang1, t)
	_tint = tint0.lerp(tint1, t)
	_apply_lighting()
	_set_sun_rotation()

func _set_state(ambient: float, sun: float, angle_rad: float, tint: Color) -> void:
	ambient_energy = ambient
	sun_energy = sun
	solar_angle = angle_rad
	_tint = tint
	_apply_lighting()
	_set_sun_rotation()

func _emit_solar_direction() -> void:
	solar_direction_changed.emit(solar_angle, rad_to_deg(solar_angle))

func reset_to_defaults() -> void:
	if _light_tween != null and _light_tween.is_valid():
		_light_tween.kill()
	_tint = Color.WHITE
	ambient_energy = _base_ambient_energy
	sun_energy = _base_sun_energy
	_apply_lighting()
