extends CharacterBody2D

enum Kind { WALKER, RUNNER }

const ATTACK_RANGE := 34.0
const SEPARATION_RADIUS := 26.0
const SEPARATION_FORCE := 55.0
const ALERT_TIME := 5.0

@export var kind: Kind = Kind.WALKER
@export var speed: float = 80.0
@export var max_hp: float = 68.0
@export var attack_damage: float = 10.0
@export var attack_cooldown_time: float = 1.0
@export var detect_radius: float = 430.0
@export var lose_radius: float = 700.0

@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var body_visual: Polygon2D = $Body
@onready var nose: Polygon2D = $Nose
@onready var alert_label: Label = $Alert

var target: Node2D
var hp: float = 68.0
var attack_cooldown: float = 0.0

var _spawn_position: Vector2
var _last_known: Vector2
var _wander_target: Vector2
var _wander_timer: float = 0.0
var _alert_timer: float = 0.0
var _flash_timer: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _dead: bool = false

func _ready() -> void:
	add_to_group("zombies")
	_spawn_position = global_position
	_last_known = _spawn_position
	_apply_kind()
	hp = max_hp
	target = get_tree().get_first_node_in_group("player")
	alert_label.visible = false
	_pick_wander_target()

func _physics_process(delta: float) -> void:
	if _dead:
		return

	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	_update_flash(delta)

	if target == null or not is_instance_valid(target) or not target.is_in_group("player"):
		target = get_tree().get_first_node_in_group("player")

	var sees_player: bool = false
	var distance: float = INF
	if target != null:
		distance = global_position.distance_to(target.global_position)
		sees_player = distance <= detect_radius and _has_line_of_sight()
		if sees_player:
			_alert_timer = ALERT_TIME
			_last_known = target.global_position
		if distance > lose_radius and not sees_player:
			_alert_timer = 0.0

	if _alert_timer > 0.0:
		_alert_timer = maxf(_alert_timer - delta, 0.0)
		if sees_player and distance <= ATTACK_RANGE:
			velocity = Vector2.ZERO
			_attack()
		else:
			var destination: Vector2 = target.global_position if sees_player else _last_known
			_navigate_to(destination, speed)
			if not sees_player and global_position.distance_to(_last_known) < 28.0:
				_alert_timer = 0.0
	else:
		_wander(delta)

	_apply_separation()
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, 220.0 * delta)

	if velocity.length() > 8.0:
		var facing: float = lerp_angle(body_visual.rotation, velocity.angle(), minf(delta * 8.0, 1.0))
		body_visual.rotation = facing
		nose.rotation = facing

	move_and_slide()
	alert_label.visible = _alert_timer > 0.0

func take_damage(amount: float, from: Node2D = null) -> void:
	if _dead:
		return
	hp -= amount
	_flash_timer = 0.12
	modulate = Color(1.5, 0.65, 0.65, 1.0)

	if from != null:
		_alert_timer = ALERT_TIME + 2.0
		_last_known = from.global_position
		if from.is_in_group("player"):
			target = from
		var push: Vector2 = global_position - from.global_position
		if push.length() > 0.001:
			_knockback = push.normalized() * 120.0

	if hp <= 0.0:
		_die()

func _attack() -> void:
	if attack_cooldown > 0.0 or target == null:
		return
	attack_cooldown = attack_cooldown_time
	if target.has_method("receive_damage"):
		target.call("receive_damage", attack_damage)

func _navigate_to(destination: Vector2, move_speed: float) -> void:
	agent.target_position = destination
	var next_point: Vector2 = agent.get_next_path_position()
	var direction: Vector2 = next_point - global_position
	if direction.length() > 0.001:
		velocity = direction.normalized() * move_speed
	else:
		velocity = Vector2.ZERO

func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 20.0:
		_pick_wander_target()
	_navigate_to(_wander_target, speed * 0.35)

func _pick_wander_target() -> void:
	var angle: float = randf() * TAU
	var radius: float = randf_range(30.0, 100.0)
	_wander_target = _spawn_position + Vector2(cos(angle), sin(angle)) * radius
	_wander_timer = randf_range(2.5, 5.0)

func _apply_separation() -> void:
	var separation: Vector2 = Vector2.ZERO
	for other in get_tree().get_nodes_in_group("zombies"):
		if other == self:
			continue
		var away: Vector2 = global_position - other.global_position
		var gap: float = away.length()
		if gap > 0.001 and gap < SEPARATION_RADIUS:
			separation += (away / gap) * (1.0 - gap / SEPARATION_RADIUS)
	velocity += separation * SEPARATION_FORCE

func _update_flash(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		modulate = Color.WHITE

func _has_line_of_sight() -> bool:
	if target == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.collision_mask = 1
	query.exclude = [get_rid(), target.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _apply_kind() -> void:
	if kind == Kind.RUNNER:
		speed = 150.0
		max_hp = 30.0
		attack_damage = 7.0
		attack_cooldown_time = 0.8
		detect_radius = 560.0
		lose_radius = 800.0
		body_visual.color = Color(0.82, 0.58, 0.2)
		nose.color = Color(0.95, 0.8, 0.5)
		body_visual.scale = Vector2(0.82, 0.82)
		nose.scale = Vector2(0.82, 0.82)
	else:
		speed = 80.0
		max_hp = 68.0
		attack_damage = 10.0
		attack_cooldown_time = 1.0
		detect_radius = 430.0
		lose_radius = 700.0
		body_visual.color = Color(0.62, 0.22, 0.18)
		nose.color = Color(0.8, 0.5, 0.45)
	alert_label.text = "!" if kind == Kind.RUNNER else "?"

func _die() -> void:
	_dead = true
	remove_from_group("zombies")
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	alert_label.visible = false
	EventBus.zombie_died.emit(self)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_property(self, "scale", Vector2(0.6, 0.6), 0.3)
	tween.finished.connect(queue_free)
