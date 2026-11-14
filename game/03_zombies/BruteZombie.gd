class_name BruteZombie
extends BaseZombie
## Zombie bruto: embestida pesada con gran knockback.

const BaseZombie := preload("res://03_zombies/BaseZombie.gd")

const CHARGE_RANGE: float = 9.0
const CHARGE_COOLDOWN: float = 4.0
const CHARGE_WINDUP: float = 0.5
const CHARGE_SPEED: float = 8.0
const CHARGE_FORCE: float = 16.0

var _cooldown: float = 0.0
var _windup: float = 0.0
var _charge_time: float = 0.0
var _direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	super._ready()
	if stats != null and stats.type_name == &"":
		stats.type_name = &"brute"


func _custom_tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _charge_time > 0.0:
		_apply_charge(delta)
		return
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			_begin_charge()
		return
	if ai == null or ai.target == null or _cooldown > 0.0:
		return
	var distance: float = global_position.distance_to(ai.target.global_position)
	if distance <= CHARGE_RANGE and distance > 2.0:
		_direction = (ai.target.global_position - global_position).normalized()
		_windup = CHARGE_WINDUP
		EventBus.voice_requested.emit(&"zombie_brute_roar", global_position)


func _begin_charge() -> void:
	_charge_time = 0.9
	_cooldown = CHARGE_COOLDOWN
	velocity = _direction * CHARGE_SPEED


func _apply_charge(delta: float) -> void:
	_charge_time -= delta
	velocity = _direction * CHARGE_SPEED
	velocity.y -= 9.8
	move_and_slide()
	if _charge_time <= 0.0:
		velocity.x *= 0.2
		velocity.z *= 0.2
