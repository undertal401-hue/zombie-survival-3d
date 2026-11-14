class_name PlayerCamera

extends Node3D
## Rig de camara en tercera persona con ADS, shake y FOV dinamico.
##
## El yaw se aplica sobre este nodo; el pitch sobre la Camera3D hija.
## El controlador de movimiento usa `get_yaw_basis()` para orientar al jugador.
## Accesible globalmente via `PlayerCamera` (class_name).

const PITCH_MIN: float = -80.0
const PITCH_MAX: float = 75.0
const MOUSE_SENSITIVITY: float = 0.0025
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


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	add_child(camera)
	camera.fov = NORMAL_FOV
	camera.far = 200.0
	camera.current = true
	_base_position = Vector3(0.0, 0.6, camera_arm_length)
	camera.position = _base_position


func _process(delta: float) -> void:
	_apply_look()
	_apply_fov(delta)
	_apply_shake(delta)


## Aplica el yaw/pitch desde el input.
func _apply_look() -> void:
	var player: Player = owner as Player
	var input: InputHandler = player.input_handler if player != null else null
	if input == null:
		return
	var delta_mouse: Vector2 = input.consume_aim_delta()
	var sens: float = MOUSE_SENSITIVITY
	if input.is_aiming:
		sens *= ADS_SENSITIVITY_SCALE
	rotation.y -= delta_mouse.x * sens
	pitch = clampf(pitch - delta_mouse.y * sens, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))
	camera.rotation.x = pitch


## Interpola el FOV entre el valor normal y el de apuntado.
func _apply_fov(delta: float) -> void:
	var player: Player = owner as Player
	var input: InputHandler = player.input_handler if player != null else null
	_target_fov = ADS_FOV if (input != null and input.is_aiming) else NORMAL_FOV
	camera.fov = lerpf(camera.fov, _target_fov, FOV_LERP_SPEED * delta)


## Aplicar shake decaiente.
func _apply_shake(delta: float) -> void:
	if _shake_amount > 0.0:
		_shake_amount = maxf(_shake_amount - SHAKE_DECAY * delta, 0.0)
		_shake_offset = Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amount * 0.1
		camera.position = _base_position + _shake_offset
	else:
		camera.position = _base_position


## Anade shake (disparos, explosiones, impactos).
## @param amount: intensidad 0..1.
func add_shake(amount: float) -> void:
	_shake_amount = clampf(_shake_amount + amount, 0.0, 1.5)


## Base de orientacion del yaw (sin pitch), util para movimiento y armas.
func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, rotation.y)


## Direccion de mirada en world space.
func get_aim_direction() -> Vector3:
	return -camera.global_transform.basis.z
