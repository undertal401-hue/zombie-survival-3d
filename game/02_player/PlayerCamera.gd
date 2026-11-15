class_name PlayerCamera

extends Node3D
## Rig de camara en primera persona con ADS, shake y FOV dinamico.

const PITCH_MIN: float = -80.0
const PITCH_MAX: float = 75.0
const MOUSE_SENSITIVITY: float = 0.0015
const ADS_SENSITIVITY_SCALE: float = 0.6
const NORMAL_FOV: float = 75.0
const ADS_FOV: float = 50.0
const FOV_LERP_SPEED: float = 12.0
const SHAKE_DECAY: float = 6.0

@export var camera_arm_length: float = 3.2
@export var aim_arm_length: float = 1.4

var camera: Camera3D
var pitch: float = 0.0
var _shake_amount: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO
var _base_position: Vector3 = Vector3.ZERO
var _target_fov: float = NORMAL_FOV
var player: Player = null


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	add_child(camera)
	camera.fov = NORMAL_FOV
	camera.far = 200.0
	camera.current = true

	# Primera persona
	_base_position = Vector3(0.0, 0.65, 0.0)
	camera.position = _base_position

	if player == null:
		player = get_parent() as Player


func _process(delta: float) -> void:
	_apply_look()
	_apply_fov(delta)
	_apply_shake(delta)


func _apply_look() -> void:
	if player == null or player.input_handler == null:
		return

	var input: InputHandler = player.input_handler
	var delta_mouse: Vector2 = input.consume_aim_delta()
	var sens: float = MOUSE_SENSITIVITY

	if input.is_aiming:
		sens *= ADS_SENSITIVITY_SCALE

	rotation.y -= delta_mouse.x * sens
	pitch = clampf(pitch - delta_mouse.y * sens, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))
	camera.rotation.x = pitch


func _apply_fov(delta: float) -> void:
	if player == null or player.input_handler == null:
		_target_fov = NORMAL_FOV
	else:
		_target_fov = ADS_FOV if player.input_handler.is_aiming else NORMAL_FOV

	camera.fov = lerpf(camera.fov, _target_fov, FOV_LERP_SPEED * delta)


func _apply_shake(delta: float) -> void:
	if _shake_amount > 0.0:
		_shake_amount = maxf(_shake_amount - SHAKE_DECAY * delta, 0.0)
		_shake_offset = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amount * 0.1
		camera.position = _base_position + _shake_offset
	else:
		camera.position = _base_position


func add_shake(amount: float) -> void:
	_shake_amount = clampf(_shake_amount + amount, 0.0, 1.5)


func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, rotation.y)


func get_aim_direction() -> Vector3:
	return -camera.global_transform.basis.z
