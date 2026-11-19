extends Node2D

## Solar Lighting - 2D Survival Sandbox
## Luz diurna pálida, cálida y ligeramente contaminada para ambiente urbano deteriorado.
## Sombras direccionales basadas en posición solar global (+X = Este, +Y = Sur).
## El sol NO se dibuja; su posición se comunica via sombras y luz ambiental sutil.
## Sombras limitadas a ~800px para evitar artefactos y mejorar rendimiento.

class_name SolarLighting

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

	# Aplicar estado inicial
	_apply_lighting()

func _exit_tree() -> void:
	if _light_tween != null and _light_tween.is_valid():
		_light_tween.kill()

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
		ambient_color.r * _tint.r,
		ambient_color.g * _tint.g,
		ambient_color.b * _tint.b,
		ambient_energy
	)
	sun_light.energy = sun_energy
	_update_glare()

## El resplandor era un shader huérfano. Ahora sigue al sol en pantalla y
## se apaga con la energía solar, sin coste cuando no hay luz directa.
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
	shader_mat.set_shader_parameter("sun_screen_pos", sun_uv)
	shader_mat.set_shader_parameter("glare_intensity", clampf(sun_energy * 0.9, 0.0, 0.30))

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