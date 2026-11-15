extends CharacterBody2D

const ATTACK_RANGE := 30.0
const ATTACK_DAMAGE := 10.0
const ATTACK_COOLDOWN := 1.0

@export var speed: float = 90.0

var target: Node2D
var attack_cooldown: float = 0.0

func _ready() -> void:
	add_to_group("zombies")
	speed += randf_range(-15.0, 15.0)
	target = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if target == null:
		target = get_tree().get_first_node_in_group("player")
		return

	attack_cooldown = max(attack_cooldown - delta, 0.0)

	var to_target: Vector2 = target.global_position - global_position
	var dist: float = to_target.length()

	if dist > ATTACK_RANGE:
		velocity = (to_target / dist) * speed
	else:
		velocity = Vector2.ZERO
		if attack_cooldown <= 0.0:
			attack_cooldown = ATTACK_COOLDOWN
			target.call("receive_damage", ATTACK_DAMAGE)

	for other in get_tree().get_nodes_in_group("zombies"):
		if other == self:
			continue
		var away: Vector2 = global_position - other.global_position
		var gap: float = away.length()
		if gap > 0.001 and gap < 24.0:
			velocity += (away / gap) * 60.0

	move_and_slide()
