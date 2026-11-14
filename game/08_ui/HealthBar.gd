class_name HealthBar

extends Control
## Barra de vida con animacion de dano y regeneracion.
## Accesible globalmente via `HealthBar` (class_name).

@onready var bg: TextureRect = $BG
@onready var fill: TextureRect = $Fill
@onready var damage_flash: TextureRect = $DamageFlash
@onready var regen_glow: TextureRect = $RegenGlow

var _max: float = 100.0
var _value: float = 100.0
var _target_value: float = 100.0
var _flash_timer: float = 0.0
var _regen_timer: float = 0.0


func _process(delta: float) -> void:
	_animate(delta)
	_animate_flash(delta)
	_animate_regen(delta)


func set_max(max_value: float) -> void:
	_max = maxf(max_value, 1.0)
	_update_fill()


func set_value(value: float) -> void:
	var old: float = _value
	_value = clampf(value, 0.0, _max)
	_target_value = _value
	if _value < old:
		_flash_timer = 0.3
		damage_flash.modulate.a = 1.0
	elif _value > old and _value < _max:
		_regen_timer = 0.5
		regen_glow.modulate.a = 0.6
	_update_fill()


func _animate(delta: float) -> void:
	# Suavizado visual
	var current: float = fill.size.x / bg.size.x * _max
	if abs(current - _target_value) > 0.5:
		var new_val: float = lerpf(current, _target_value, 8.0 * delta)
		fill.size = Vector2(bg.size.x * (new_val / _max), fill.size.y)


func _animate_flash(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		damage_flash.modulate.a = lerpf(damage_flash.modulate.a, 0.0, 6.0 * delta)
	else:
		damage_flash.modulate.a = 0.0


func _animate_regen(delta: float) -> void:
	if _regen_timer > 0.0:
		_regen_timer -= delta
		regen_glow.modulate.a = lerpf(regen_glow.modulate.a, 0.0, 4.0 * delta)
	else:
		regen_glow.modulate.a = 0.0


func _update_fill() -> void:
	fill.size = Vector2(bg.size.x * (_value / _max), fill.size.y)
