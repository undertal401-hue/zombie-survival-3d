extends Node2D

## Solar Lighting - 2D Survival Sandbox
## Luz diurna pálida, cálida y ligeramente contaminada para ambiente urbano deteriorado.
## Sombras direccionales basadas en posición solar global (+X = Este, +Y = Sur).
## El sol NO se dibuja; su posición se comunica via sombras y luz ambiental sutil.

class_name SolarLighting

@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var sun_light: DirectionalLight2D = $SunLight

## Parámetros ajustables (expuestos en inspector)
@export_group("Ambiente Base")
@export var ambient_color: Color = Color(0.95, 0.92, 0.85, 1.0)  # Pálido, cálido, sucio
@export var ambient_energy: float = 0.85  # Intensidad global (0-1)

@export_group("Sol Direccional (DirectionalLight2D) - Sombras Globales")
@export var sun_color: Color = Color(1.0, 0.95, 0.82, 0.35)  # Muy sutil
@export var sun_energy: float = 0.18
@export var sun_shadow_enabled: bool = true  # Sombras direccionales globales
@export var shadow_filter: int = 1  # 0=PCF3, 1=PCF5, 2=PCF7, 3=PCF13 (suavizado)

@export_group("Dirección Solar Global (+X = Este, +Y = Sur)")
@export var solar_angle: float = 0.0  # Rad: 0 = Este, PI/2 = Sur, PI = Oeste, -PI/2 = Norte

var _base_ambient_energy: float
var _base_sun_energy: float

# Señal para notificar cambios de dirección solar a otros sistemas
signal solar_direction_changed(angle_rad: float, angle_deg: float)

func _ready() -> void:
	# Guardar valores base para posible reset
	_base_ambient_energy = ambient_energy
	_base_sun_energy = sun_energy

	# Configurar nodos
	_setup_canvas_modulate()
	_setup_sun_light()

	# Posicionar sol según dirección actual
	_update_sun_position()

	# Aplicar estado inicial
	_apply_lighting()

func _setup_canvas_modulate() -> void:
	canvas_modulate.color = Color(ambient_color.r, ambient_color.g, ambient_color.b, ambient_energy)

func _setup_sun_light() -> void:
	sun_light.color = sun_color
	sun_light.energy = sun_energy
	sun_light.shadow_enabled = sun_shadow_enabled
	sun_light.shadow_filter = shadow_filter
	# light_mode ya configurado en la escena (0 = ADD)

func _apply_lighting() -> void:
	canvas_modulate.color = Color(ambient_color.r, ambient_color.g, ambient_color.b, ambient_energy)
	sun_light.energy = sun_energy

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

func reset_to_defaults() -> void:
	ambient_energy = _base_ambient_energy
	sun_energy = _base_sun_energy
	_apply_lighting()