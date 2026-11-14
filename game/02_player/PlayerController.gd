extends Node
## Componente de movimiento del jugador.

const ACCELERATION: float = 42.0
const FRICTION: float = 14.0
const AIR_CONTROL: float = 0.35
const DODGE_COOLDOWN: float = 0.6
const GRAVITY: float = 9.8

var player
var is_sprinting: bool = false
var is_crouching: bool = false
var is_dodge_on_cooldown: bool = false
var _dodge_timer: float = 0.0
var _dodge_cooldown_timer: float = 0.0
var _move_direction: Vector3 = Vector3.ZERO
var _wish_direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(delta: float) -> void:
	if player == null or player.input_handler == null:
		return
	_read_input()
	_update_stance(delta)
	_update_dodge(delta)
	_apply_velocity(delta)
	_face_movement(delta)


func _read_input() -> void:
	var input = player.input_handler
	var forward = input.get_axis("move_back", "move_forward")
	var strafe = input.get_axis("move_left", "move_right")
	var basis = player.camera_rig.get_yaw_basis() if player.camera_rig != null \
		else player.global_transform.basis
	var forward_vec = -basis.z
	var right_vec = basis.x
	_wish_direction = (forward_vec * forward + right_vec * strafe).normalized()
	if _wish_direction.length_squared() > 1.0:
		_wish_direction = _wish_direction.normalized()
	is_sprinting = input.is_action_pressed("sprint") and forward > 0.1 and not is_crouching


func _update_stance(delta: float) -> void:
	if player.stats == null:
		return
	if is_sprinting and _wish_direction.length_squared() > 0.01:
		if not player.stats.try_consume_stamina(player.stats.stamina_sprint_drain * delta):
			is_sprinting = false
	else:
		is_sprinting = false
	if player.input_handler.is_action_just_pressed("jump") and player.is_on_floor():
		player.velocity.y = player.stats.jump_velocity * player.stats.permanent_jump_mult


func _update_dodge(delta: float) -> void:
	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)
	is_dodge_on_cooldown = _dodge_cooldown_timer > 0.0
	if not player.input_handler.is_action_just_pressed("dodge"):
		return
	var config = load("res://16_data/GameBalance.tres")
	if is_dodge_on_cooldown or not player.stats.try_consume_stamina(config.player_dodge_cost):
		return
	var direction = _wish_direction
	if direction.length_squared() < 0.01:
		direction = -player.global_transform.basis.z
	direction = direction.normalized()
	_dodge_timer = config.player_dodge_duration
	_dodge_cooldown_timer = DODGE_COOLDOWN
	player.is_dodging = true
	player.velocity = direction * player.stats.dodge_speed
	var event_bus = get_tree().root.get_node_or_null("EventBus")
	event_bus.player_dodge_started.emit(config.player_dodge_duration)


func _apply_velocity(delta: float) -> void:
	if _dodge_timer > 0.0:
		_dodge_timer -= delta
		if _dodge_timer <= 0.0:
			player.is_dodging = false
		return
	var target_speed = player.stats.crouch_speed if is_crouching else (
		player.stats.sprint_speed if is_sprinting else player.stats.move_speed)
	var target = _wish_direction * target_speed
	var control = 1.0 if player.is_on_floor() else AIR_CONTROL
	var accel = ACCELERATION * control
	if player.is_on_floor() and _wish_direction.length_squared() < 0.01:
		var horizontal = Vector3(player.velocity.x, 0.0, player.velocity.z)
		horizontal = horizontal.move_toward(Vector3.ZERO, FRICTION * delta)
		player.velocity.x = horizontal.x
		player.velocity.z = horizontal.z
	else:
		player.velocity.x = move_toward(player.velocity.x, target.x, accel * delta)
		player.velocity.z = move_toward(player.velocity.z, target.z, accel * delta)
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	player.move_and_slide()


func _face_movement(_delta: float) -> void:
	if _wish_direction.length_squared() < 0.01:
		return
	var target_angle = atan2(_wish_direction.x, _wish_direction.z)
	player.rotation.y = lerp_angle(player.rotation.y, target_angle, 0.2)


func get_horizontal_speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()
