class_name StaminaBar

extends Control
## Barra de stamina con vaciado/llenado suave.
## Accesible globalmente via `StaminaBar` (class_name).

@onready var bg: TextureRect = $BG
@onready var fill: TextureRect = $Fill
@onready var sprint_indicator: TextureRect = $SprintIndicator

var _max: float = 100.0
var _value: float = 100.0
var _is_sprinting: bool = false


func _process(_delta: float) -> void:
	fill.size = Vector2(bg.size.x * (_value / _max), fill.size.y)
	sprint_indicator.visible = _is_sprinting


func set_max(max_value: float) -> void:
	_max = maxf(max_value, 1.0)


func set_value(value: float) -> void:
	_value = clampf(value, 0.0, _max)


func set_sprinting(sprinting: bool) -> void:
	_is_sprinting = sprinting
