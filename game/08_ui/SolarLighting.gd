extends Node2D

## Solar Lighting - 2D Survival Sandbox
## Luz diurna pálida, cálida y ligeramente contaminada para ambiente urbano deteriorado.
## Sombras direccionales basadas en posición solar global (+X = Este, +Y = Sur).
## El sol NO se dibuja; su posición se comunica via sombras y luz ambiental sutil.
## Sombras limitadas a ~800px para evitar artefactos y mejorar rendimiento.

class_name SolarLighting

## --- Color grading por fase (ART_BIBLE.md §2, paleta de 16 colores) -------
## Multiplicadores suaves sobre el tinte que ya envía WorldDirector via
## apply_state(). No sustituyen ese tinte: solo matizan la fase del ciclo.
## Dusk deriva de AMBER (#d2a867)/BLOOD (#b52b20); night de
## STEEL_DARK/STEEL_LIGHT (#55626d/#9aabb6); day es BONE neutro (#efe4bd).
const GRADE_DAWN: Color = Color(0.99, 0.94, 0.90)
const GRADE_DAY: Color = Color(1.00, 1.00, 1.00)
const GRADE_DUSK: Color = Color(1.00, 0.93, 0.82)
const GRADE_NIGHT: Color = Color(0.84, 0.90, 1.00)
## Suavizado exponencial del grading (misma familia que WorldDirector).
const GRADE_SMOOTH_TAU: float = 0.6
const GRADE_CACHE_INTERVAL: float = 0.25

@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var sun_light: DirectionalLight2D = $SunLight
@onready var glare_rect: ColorRect = $GlareLayer/GlareRect

## Parámetros ajustables (expuestos en inspector)
@export_group("Ambiente Base")
@export var ambient_color: Color = Color(0.95, 0.92, 0.85, 1.0)  # Pálido, cálido, sucio
@export var ambient_energy: float = 0.85  # Intensidad global (0-1)

@export_group("Sol Direccional (DirectionalLight2D) - Sombras Globales")
@export var sun_color: Color = Color(1.0, 0.95, 0.82, 0.35)  # Muy sutil
@export var sun_energy: float = 0.18
@export var sun_shadow_enabled: bool = true  # Sombras direccionales globales
@export var shadow_filter: int = 1  # 0=PCF3, 1=PCF5, 2=PCF7, 3=PCF13 (suavizado)
## Los objetos a más de esta distancia del centro de la cámara no proyectan sombra.
## 800px cubre la pantalla (1280x720) con margen y evita sombras de todo el mapa.
@export var shadow_max_distance: float = 800.0

@export_group("Dirección Solar Global (+X = Este, +Y = Sur)")
@export var solar_angle: float = 0.0  # Rad: 0 = Este, PI/2 = Sur, PI = Oeste, -PI/2 = Norte

var _base_ambient_energy: float
var _base_sun_energy: float
## Tinte ambiental controlado por WorldDirector (clima / fase del día).
var _tint: Color = Color.WHITE
var _light_tween: Tween = null

## Estado del color grading por fase.
var _phase_grade: Color = Color.WHITE
var _phase_grade_target: Color = Color.WHITE
var _grade_director: Node = null
var _grade_cache_t: float = 0.0
var _shadow_controller: PixelShadowController = null

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
	# inicial no arranque neutro durante el primer frame.
	_refresh_grade_target()
	_apply_lighting()

	# Nodo hijo sin gameplay: mantiene las sombras del grupo `pixel_shadows`
	# desplazadas según el sol. No forma parte del gameplay ni del combate.
	_shadow_controller = PixelShadowController.new(self)
	_shadow_controller.name = "PixelShadowController"
	add_child(_shadow_controller)

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

func _grade_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.0005 and absf(a.g - b.g) < 0.0005 and absf(a.b - b.b) < 0.0005

func _refresh_grade_target() -> void:
	if _grade_director == null or not is_instance_valid(_grade_director):
		_grade_director = _find_director()
	var phase: String = "day"
	if _grade_director != null and is_instance_valid(_grade_director) and _grade_director.has_method("current_phase"):
		phase = String(_grade_director.call("current_phase"))
	_phase_grade_target = _grade_for_phase(phase)

func _find_director() -> Node:
	var parent := get_parent()
	if parent != null:
		for node_name in ["WaveManager", "HordeManager", "WorldDirector"]:
			var candidate: Node = parent.get_node_or_null(node_name)
			if candidate != null and candidate.has_method("current_phase"):
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

func _setup_canvas_modulate() -> void:
	canvas_modulate.color = Color(ambient_color.r, ambient_color.g, ambient_color.b, ambient_energy)

func _setup_sun_light() -> void:
	sun_light.color = sun_color
	sun_light.energy = sun_energy
	sun_light.shadow_enabled = sun_shadow_enabled
	sun_light.shadow_filter = shadow_filter
	sun_light.max_distance = shadow_max_distance
	# light_mode ya configurado en la escena (0 = ADD)

func _apply_lighting() -> void:
	# El tinte del clima multiplica el color base; el alpha de CanvasModulate
	# sigue siendo la energía ambiente, igual que en la configuración original.
	canvas_modulate.color = Color(
		ambient_color.r * _tint.r * _phase_grade.r,
		ambient_color.g * _tint.g * _phase_grade.g,
		ambient_color.b * _tint.b * _phase_grade.b,
		ambient_energy
	)
	sun_light.energy = sun_energy
	_update_glare()

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


## --- Sombras pixeladas ----------------------------------------------------
## Nodo Node2D hijo, sin gameplay: lee el grupo `pixel_shadows` solo cada
## 0,25 s y coloca cada sombra en la posición global de su padre, desplazada
## en dirección opuesta al sol. El ángulo da la dirección; la energía solar
## da la longitud y la opacidad (sol bajo = sombra larga y tenue).
class PixelShadowController extends Node2D:
	const CACHE_INTERVAL: float = 0.25
	const OFFSET_LOW_SUN: float = 14.0
	const OFFSET_HIGH_SUN: float = 3.0
	## La energía solar típica de día ronda 0.18-0.23 -> alpha ~0.41-0.49,
	## cercano al 0.5 del .tscn; amanecer/atardecer/noche desvanecen la sombra.
	const ALPHA_BASE: float = 0.12
	const ALPHA_PER_SUN: float = 1.6
	const ALPHA_MAX: float = 0.62

	var _solar: Node2D
	var _entries: Array = []
	var _cache_t: float = 0.0

	func _init(solar: Node2D) -> void:
		_solar = solar

	func _process(delta: float) -> void:
		if not is_instance_valid(_solar):
			return
		_cache_t -= delta
		if _cache_t <= 0.0:
			_cache_t = CACHE_INTERVAL
			_recache()
		if _entries.is_empty():
			return
		var sun: float = clampf(float(_solar.get("sun_energy")), 0.0, 1.0)
		var angle: float = float(_solar.get("solar_angle"))
		# Sol en `angle`; la sombra cae en dirección opuesta.
		var dir := -Vector2.from_angle(angle)
		var offset: Vector2 = dir * lerpf(OFFSET_LOW_SUN, OFFSET_HIGH_SUN, sun)
		var alpha: float = minf(ALPHA_BASE + sun * ALPHA_PER_SUN, ALPHA_MAX)
		for entry in _entries:
			var node := entry["node"] as Node2D
			var parent := entry["parent"] as Node2D
			if not is_instance_valid(node) or not is_instance_valid(parent):
				continue
			node.global_position = parent.global_position + offset
			var base: Color = entry["color"]
			node.modulate = Color(base.r, base.g, base.b, alpha)

	func _recache() -> void:
		_entries.clear()
		var tree := get_tree()
		if tree == null:
			return
		for candidate in tree.get_nodes_in_group("pixel_shadows"):
			if not is_instance_valid(candidate) or not (candidate is Node2D):
				continue
			var node := candidate as Node2D
			var parent := node.get_parent() as Node2D
			if parent == null:
				continue
			_entries.append({
				"node": node,
				"parent": parent,
				"color": node.modulate,
			})