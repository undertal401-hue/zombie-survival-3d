extends CanvasLayer

## Solar Lighting Test - 2D Survival Sandbox
## Luz diurna pálida, cálida y ligeramente contaminada para ambiente urbano deteriorado.
## Sombras direccionales basadas en posición solar global (+X = Este, +Y = Sur).
## El sol NO se dibuja; su posición se comunica via sombras y luz ambiental sutil.

class_name SolarLighting

@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var sun_light: Light2D = $SunLight
@onready var glare_quad: ColorRect = $GlareQuad
var glare_material: CanvasItemMaterial

## Parámetros ajustables (expuestos en inspector)
@export_group("Ambiente Base")
@export var ambient_color: Color = Color(0.95, 0.92, 0.85, 1.0)  # Pálido, cálido, sucio
@export var ambient_energy: float = 0.85  # Intensidad global (0-1)

@export_group("Sol Direccional (Light2D) - Sombras Globales")
@export var sun_color: Color = Color(1.0, 0.95, 0.82, 0.35)  # Muy sutil
@export var sun_energy: float = 0.18
@export var sun_height: float = 400.0  # Altura virtual sobre el mapa
@export var sun_shadow_enabled: bool = true  # Sombras direccionales globales
@export var sun_distance: float = 6000.0  # Distancia del sol al centro del mapa (simula sol en el infinito)
@export var shadow_filter: int = 1  # 0=PCF3, 1=PCF5, 2=PCF7, 3=PCF13 (suavizado)

@export_group("Dirección Solar Global (+X = Este, +Y = Sur)")
@export var solar_angle: float = 0.0  # Rad: 0 = Este, PI/2 = Sur, PI = Oeste, -PI/2 = Norte
@export var solar_angle_deg: float = 0.0  # Grados (solo inspector, se sincroniza)

@export_group("Resplandor (Glare) - Shader sencillo")
@export var glare_enabled: bool = true
@export var glare_intensity: float = 0.08
@export var glare_color: Color = Color(1.0, 0.92, 0.75, 1.0)
@export var glare_radius: float = 0.75  # Radio normalizado (0-1) del foco central
@export var glare_falloff: float = 2.2   # Suavidad del borde

@export_group("Transición Demo (opcional)")
@export var demo_transition: bool = false
@export var transition_speed: float = 0.02  # Unidades por segundo
@export var transition_min_energy: float = 0.6
@export var transition_max_energy: float = 1.0

var _transition_dir: float = 1.0
var _base_ambient_energy: float
var _base_sun_energy: float

# Señal para notificar cambios de dirección solar a otros sistemas
signal solar_direction_changed(angle_rad: float, angle_deg: float)

func _ready() -> void:
	# Guardar valores base para transición
	_base_ambient_energy = ambient_energy
	_base_sun_energy = sun_energy

	# Sincronizar grados/radianes
	_solar_deg_to_rad()

	# Configurar nodos
	_setup_canvas_modulate()
	_setup_sun_light()
	_setup_glare_quad()

	# Posicionar sol según dirección actual
	_update_sun_position()

	# Aplicar estado inicial
	_apply_lighting()

	# Conectar señal de transición si está activada
	if demo_transition:
		set_process(true)
	else:
		set_process(false)

func _solar_deg_to_rad() -> void:
	solar_angle = deg_to_rad(solar_angle_deg)

func _solar_rad_to_deg() -> void:
	solar_angle_deg = rad_to_deg(solar_angle)

func _setup_canvas_modulate() -> void:
	canvas_modulate.color = Color(ambient_color.r, ambient_color.g, ambient_color.b, ambient_energy)

func _setup_sun_light() -> void:
	sun_light.color = sun_color
	sun_light.energy = sun_energy
	sun_light.height = sun_height
	sun_light.shadow_enabled = sun_shadow_enabled
	sun_light.shadow_filter = shadow_filter
	# light_mode ya configurado en la escena (0 = ADD)
	# Configurar máscara de sombras para capa 1 (objetos del mundo)
	sun_light.item_cull_mask = 1
	sun_light.item_shadow_cull_mask = 1

func _get_glare_shader_code() -> String:
	return """
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glare_color : source_color = vec4(1.0, 0.92, 0.75, 1.0);
uniform float glare_intensity : hint_range(0.0, 1.0) = 0.08;
uniform float glare_radius : hint_range(0.0, 1.0) = 0.75;
uniform float glare_falloff : hint_range(0.5, 5.0) = 2.2;
uniform vec2 sun_screen_pos = vec2(0.5, 0.3);

void fragment() {
	vec2 to_sun = sun_screen_pos - UV;
	float dist = length(to_sun);
	float glow = 1.0 - smoothstep(0.0, glare_radius, dist);
	glow = pow(glow, glare_falloff) * glare_intensity;
	COLOR = glare_color * glow;
}
"""

func _setup_glare_quad() -> void:
	# Cuadrícula a pantalla completa para el shader de resplandor
	glare_quad.anchors_preset = Control.PRESET_FULL_RECT
	glare_quad.offset_left = 0
	glare_quad.offset_top = 0
	glare_quad.offset_right = 0
	glare_quad.offset_bottom = 0
	glare_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glare_quad.z_index = 100  # Sobre el mundo, bajo HUD
	glare_quad.visible = glare_enabled

	# Crear ShaderMaterial en código (evita problemas de recursos)
	var shader = Shader.new()
	shader.code = _get_glare_shader_code()
	var shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	glare_quad.material = shader_material
	_set_sun_screen_pos(Vector2(0.5, 0.3))

func _set_sun_screen_pos(pos: Vector2) -> void:
	if glare_quad and glare_quad.material:
		(glare_quad.material as ShaderMaterial).set_shader_parameter("sun_screen_pos", pos)

func _apply_lighting() -> void:
	canvas_modulate.color = Color(ambient_color.r, ambient_color.g, ambient_color.b, ambient_energy)
	sun_light.energy = sun_energy
	if glare_quad and glare_quad.material:
		var mat = glare_quad.material as ShaderMaterial
		mat.set_shader_parameter("glare_intensity", glare_intensity if glare_enabled else 0.0)
		mat.set_shader_parameter("glare_color", glare_color)
		mat.set_shader_parameter("glare_radius", glare_radius)
		mat.set_shader_parameter("glare_falloff", glare_falloff)

func _update_sun_position() -> void:
	# Posicionar Light2D lejos en la dirección del sol
	# +X = Este, +Y = Sur
	# solar_angle: 0 = Este, PI/2 = Sur, PI = Oeste, -PI/2 = Norte
	# Sol en ángulo -> luz en esa dirección -> sombras apuntan dirección opuesta
	var light_pos := Vector2(cos(solar_angle), sin(solar_angle)) * sun_distance
	sun_light.global_position = light_pos
	
	# Actualizar posición del resplandor en pantalla (para el shader glare)
	var viewport_size := get_viewport().get_visible_rect().size
	var map_half := Vector2(2400.0, 1500.0)
	var screen_pos := (light_pos + map_half) / (map_half * 2.0)
	screen_pos.y = 1.0 - screen_pos.y  # Invertir Y para UV
	_set_sun_screen_pos(screen_pos)

	# Emitir señal de cambio de dirección
	solar_direction_changed.emit(solar_angle, solar_angle_deg)

func _process(delta: float) -> void:
	if not demo_transition:
		return

	# Transición simple de energía ambiental (simula paso de nubes / hora)
	ambient_energy += _transition_dir * transition_speed * delta
	sun_energy += _transition_dir * transition_speed * delta * 0.5

	if ambient_energy >= transition_max_energy:
		ambient_energy = transition_max_energy
		_transition_dir = -1.0
	elif ambient_energy <= transition_min_energy:
		ambient_energy = transition_min_energy
		_transition_dir = 1.0

	# Demo: rotar sol lentamente (ciclo completo ~ 5 min)
	var time = Time.get_ticks_msec() / 1000.0
	solar_angle = fmod(time * 0.02, TAU)
	_solar_rad_to_deg()
	_update_sun_position()
	_apply_lighting()

func _solar_rad_to_deg() -> void:
	solar_angle_deg = rad_to_deg(solar_angle)

## API pública para control externo

func set_ambient_energy(e: float) -> void:
	ambient_energy = clampf(e, 0.0, 1.5)
	_apply_lighting()

func set_sun_energy(e: float) -> void:
	sun_energy = clampf(e, 0.0, 1.0)
	_apply_lighting()

func set_glare_enabled(enabled: bool) -> void:
	glare_enabled = enabled
	glare_quad.visible = enabled
	_apply_lighting()

func set_time_of_day(t: float) -> void:
	"""t en [0,1]: 0=amanecer, 0.5=mediodía, 1=anochecer (demo simple)"""
	# Mapear a energías
	ambient_energy = lerpf(0.6, 1.0, 1.0 - abs(t - 0.5) * 2.0)
	sun_energy = lerpf(0.05, 0.25, 1.0 - abs(t - 0.5) * 2.0)
	_apply_lighting()

func reset_to_defaults() -> void:
	ambient_energy = _base_ambient_energy
	sun_energy = _base_sun_energy
	_apply_lighting()