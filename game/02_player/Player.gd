extends CharacterBody3D

const SPEED := 6.0
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 6.0
const GRAVITY := 18.0
const MOUSE_SENSITIVITY := 0.0025

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

var input_handler: InputHandler
var yaw: float = 0.0
var pitch: float = 0.0
var hp: float = 100.0

func receive_damage(amount: float) -> void:
	# El zombi ataca aqui; el sistema de vida completo aun no existe.
	hp -= amount

func _ready() -> void:
	input_handler = InputHandler.new()
	add_child(input_handler)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	_process_movement(delta)
	_process_camera(delta)

func _process_movement(delta: float) -> void:
	var move := input_handler.get_move_vector()
	var basis := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO).basis
	var direction := Vector3.ZERO

	direction = (-basis.z * move.y) + (basis.x * move.x)
	direction = direction.normalized()

	var speed := SPEED
	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED

	if direction.length() > 0.0:
		velocity.x = move_toward(velocity.x, direction.x * speed, 12.0 * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)

	if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = JUMP_VELOCITY

	velocity.y -= GRAVITY * delta
	move_and_slide()

func _process_camera(delta: float) -> void:
	var look := input_handler.consume_look_delta()
	yaw -= look.x * MOUSE_SENSITIVITY
	pitch = clamp(pitch - look.y * MOUSE_SENSITIVITY, -1.2, 1.2)
	camera_pivot.rotation.y = yaw
	camera.rotation.x = pitch
