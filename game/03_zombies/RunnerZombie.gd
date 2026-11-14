class_name RunnerZombie
extends BaseZombie
## Zombie rapido: alterna carrera y embestida (lunge) cuando esta cerca.

const BaseZombie := preload("res://03_zombies/BaseZombie.gd")

const LUNGE_RANGE: float = 5.0
const LUNGE_COOLDOWN: float = 2.2
const LUNGE_SPEED: float = 9.5
const LUNGE_TIME: float = 0.35

var _lunge_timer: float = 0.0
var _lunge_cooldown: float = 0.0
var _lunge_direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	super._ready()
	if stats != null and stats.type_name == &"":
		stats.type_name = &"runner"


func _custom_tick(delta: float) -> void:
	_lunge_cooldown = maxf(_lunge_cooldown - delta, 0.0)
	if _lunge_timer > 0.0:
		_apply_lunge(delta)
		return
	if ai == null or ai.target == null or _lunge_cooldown > 0.0:
		return
	var distance: float = global_position.distance_to(ai.target.global_position)
	if distance <= LUNGE_RANGE and distance > 1.2:
		_start_lunge()


func _start_lunge() -> void:
	_lunge_direction = (ai.target.global_position - global_position).normalized()
	_lunge_direction.y = 0.0
	_lunge_timer = LUNGE_TIME
	_lunge_cooldown = LUNGE_COOLDOWN
	EventBus.voice_requested.emit(&"zombie_runner_screech", global_position)


func _apply_lunge(delta: float) -> void:
	_lunge_timer -= delta
	velocity = _lunge_direction * LUNGE_SPEED
	velocity.y -= 9.8
	move_and_slide()
	if _lunge_timer <= 0.0:
		velocity.x *= 0.3
		velocity.z *= 0.3
