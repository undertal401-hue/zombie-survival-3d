extends CharacterBody3D

var target: Node3D
var speed: float = 2.5
var hp: float = 30.0

func _ready() -> void:
	target = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if target == null:
		return

	var dir := target.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	if global_position.distance_to(target.global_position) < 1.5:
		target.call("receive_damage", 10.0)
