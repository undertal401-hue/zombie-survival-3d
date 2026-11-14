class_name InputHandler
extends Node
## Componente de input: expone estado de acciones y ejes normalizados.

const ACTIONS = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"sprint", &"jump", &"dodge", &"fire", &"aim", &"reload",
	&"interact", &"melee", &"switch_primary", &"switch_secondary",
	&"switch_melee", &"switch_consumable", &"pause", &"inventory", &"shop",
]
var move_vector: Vector2 = Vector2.ZERO
var aim_delta: Vector2 = Vector2.ZERO
var is_firing: bool = false
var is_aiming: bool = false
var _just_pressed: Dictionary = {}
var _just_released: Dictionary = {}
var _pressed: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for action in ACTIONS:
		_pressed[action] = false
		_just_pressed[action] = false
		_just_released[action] = false


func _process(_delta: float) -> void:
	aim_delta = Input.get_last_mouse_velocity()
	is_firing = Input.is_action_pressed("fire")
	is_aiming = Input.is_action_pressed("aim")
	move_vector = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	for action in ACTIONS:
		var state = Input.is_action_pressed(action)
		_just_pressed[action] = state and not _pressed[action]
		_just_released[action] = _pressed[action] and not state
		_pressed[action] = state


## Limpia las pulsaciones "just" de este frame.
func flush() -> void:
	for action in ACTIONS:
		_just_pressed[action] = false
		_just_released[action] = false


## Devuelve -1/0/1 segun el eje negativo y positivo indicados.
func get_axis(negative, positive) -> float:
	return Input.get_action_strength(positive) - Input.get_action_strength(negative)


func is_action_pressed(action):
	return _pressed.get(action, Input.is_action_pressed(action))


func is_action_just_pressed(action):
	return _just_pressed.get(action, Input.is_action_just_pressed(action))


func is_action_just_released(action):
	return _just_released.get(action, Input.is_action_just_released(action))


func get_move_vector() -> Vector2:
	return move_vector


## Devuelve y consume el delta de aim acumulado.
func consume_aim_delta() -> Vector2:
	var delta = aim_delta
	aim_delta = Vector2.ZERO
	return delta
