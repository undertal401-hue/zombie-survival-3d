class_name Player
extends CharacterBody3D

const SPEED: float = 5.0
const GRAVITY: float = 20.0
const MOUSE_SENS: float = 0.0022
const LOOK_MIN_X: float = -1.5
const LOOK_MAX_X: float = 1.5

const KEYMAP := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
}

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_register_actions()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _register_actions() -> void:
	for action: StringName in KEYMAP:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.keycode = KEYMAP[action]
		InputMap.action_add_event(action, ev)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotation.x = clamp(camera.rotation.x - event.relative.y * MOUSE_SENS, LOOK_MIN_X, LOOK_MAX_X)

func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	if dir:
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	move_and_slide()
