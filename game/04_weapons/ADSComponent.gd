class_name ADSComponent


extends Node
## Componente de apuntado (ADS): interpolacion de FOV y sensibilidad.
## Accesible globalmente via `ADSComponent` (class_name).

const ADS_LERP_SPEED: float = 14.0

var is_aiming: bool = false
var progress: float = 0.0
var ads_fov: float = 50.0
var normal_fov: float = 75.0


## Configura el componente.
## @param p_normal_fov: FOV normal.
## @param p_ads_fov: FOV apuntando.
func configure(p_normal_fov: float, p_ads_fov: float) -> void:
	normal_fov = p_normal_fov
	ads_fov = p_ads_fov


func _process(delta: float) -> void:
	var target: float = 1.0 if is_aiming else 0.0
	progress = move_toward(progress, target, ADS_LERP_SPEED * delta)


## FOV interpolado segun progreso.
func current_fov() -> float:
	return lerpf(normal_fov, ads_fov, progress)


## Escala de sensibilidad (menor al apuntar).
func sensitivity_scale() -> float:
	return lerpf(1.0, 0.6, progress)
