class_name ReloadSystem


extends Node
## Gestiona el tiempo de recarga de un arma.
## Accesible globalmente via `ReloadSystem` (class_name).

signal reload_completed(duration: float)

var weapon: BaseWeapon
var duration: float = 1.5
var elapsed: float = 0.0
var is_active: bool = false


## Inicia una recarga.
## @param p_duration: segundos.
func start_reload(p_duration: float) -> void:
	if weapon == null:
		return
	duration = maxf(p_duration, 0.01)
	elapsed = 0.0
	is_active = true
	weapon.mark_reloading(duration)


func _process(delta: float) -> void:
	if not is_active:
		return
	elapsed += delta
	if elapsed >= duration:
		is_active = false
		if weapon != null:
			weapon.finish_reload()
		reload_completed.emit(duration)


## Progreso 0..1.
func progress() -> float:
	return clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)


## True si hay una recarga en curso.
func is_busy() -> bool:
	return is_active


## Cancela la recarga (cambio de arma).
func cancel() -> void:
	is_active = false
	elapsed = 0.0
