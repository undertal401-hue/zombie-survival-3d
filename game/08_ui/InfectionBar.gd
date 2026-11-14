class_name InfectionBar

extends Control
## Barra de infeccion: sube al recibir dano zombie, 100% = game over.
##
## Color: verde -> amarillo -> rojo. Pulso critico al 80%+.
## Accesible globalmente via `InfectionBar` (class_name).

@onready var bg: TextureRect = $BG
@onready var fill: TextureRect = $Fill
@onready var warning_pulse: TextureRect = $WarningPulse
@onready var critical_overlay: ColorRect = $CriticalOverlay

var _max: float = 100.0
var _value: float = 0.0
var _pulse_timer: float = 0.0
var _is_critical: bool = false


func _process(delta: float) -> void:
	fill.size = Vector2(bg.size.x * (_value / _max), fill.size.y)
	_update_color()
	_update_pulse(delta)
	_update_critical()


func set_max(max_value: float) -> void:
	_max = maxf(max_value, 1.0)


func set_value(value: float) -> void:
	_value = clampf(value, 0.0, _max)


func _update_color() -> void:
	var ratio: float = _value / _max
	if ratio < 0.4:
		fill.modulate = Color(0.2, 0.8, 0.3)
	elif ratio < 0.7:
		fill.modulate = Color(1.0, 0.85, 0.1)
	else:
		fill.modulate = Color(1.0, 0.2, 0.2)


func _update_pulse(delta: float) -> void:
	var ratio: float = _value / _max
	if ratio >= 0.8:
		_pulse_timer += delta
		var pulse: float = abs(sin(_pulse_timer * 8.0))
		warning_pulse.modulate.a = 0.3 + pulse * 0.5
	else:
		warning_pulse.modulate.a = 0.0


func _update_critical() -> void:
	var ratio: float = _value / _max
	_is_critical = ratio >= 1.0
	critical_overlay.visible = _is_critical
	if _is_critical:
		critical_overlay.color.a = 0.4 + abs(sin(Time.get_ticks_msec() * 0.01)) * 0.3
