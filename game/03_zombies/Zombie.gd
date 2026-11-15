extends CharacterBody2D

const ATTACK_RANGE := 30.0
const ATTACK_DAMAGE := 10.0
const ATTACK_COOLDOWN := 1.0
const SEPARATION_RADIUS := 24.0
const SEPARATION_FORCE := 60.0

@export var speed: float = 90.0

@onready var agent: NavigationAgent2D = $NavigationAgent2D

var target: Node2D
var attack_cooldown: float = 0.0

func _ready() -> void:
	add_to_group("zombies")
	speed += randf_range(-15.0, 15.0)
	target = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if target == null:
		target = get_tree().get_first_node_in_group("player")
		if target == null:
			return

	attack_cooldown = maxf(attack_cooldown - delta, 0.0)

	var to_target: Vector2 = target.global_position - global_position
	var dist: float = to_target.length()

	if dist <= ATTACK_RANGE and _has_line_of_sight():
		velocity = Vector2.ZERO
		if attack_cooldown <= 0.0:
			attack_cooldown = ATTACK_COOLDOWN
			target.call("receive_damage", ATTACK_DAMAGE)
	else:
		agent.target_position = target.global_position
		var next_point: Vector2 = agent.get_next_path_position()
		var direction: Vector2 = next_point - global_position
		if direction.length() > 0.001:
			velocity = direction.normalized() * speed
		else:
			velocity = Vector2.ZERO

	for other in get_tree().get_nodes_in_group("zombies"):
		if other == self:
			continue
		var away: Vector2 = global_position - other.global_position
		var gap: float = away.length()
		if gap > 0.001 and gap < SEPARATION_RADIUS:
			velocity += (away / gap) * SEPARATION_FORCE

	move_and_slide()

## Evita atacar a traves de las paredes: si hay un muro entre el zombi y el
## jugador, sigue navegando hasta la puerta.
func _has_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.collision_mask = 1
	query.exclude = [get_rid(), target.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()
