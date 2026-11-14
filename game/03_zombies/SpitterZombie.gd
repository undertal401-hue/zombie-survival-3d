class_name SpitterZombie
extends BaseZombie
## Zombie escupidor: ataque a distancia con proyectil acido.

const BaseZombie := preload("res://03_zombies/BaseZombie.gd")

const SPIT_RANGE: float = 14.0
const SPIT_COOLDOWN: float = 3.0
const SPIT_DAMAGE: float = 12.0
const SPIT_INFECTION: float = 14.0
const PROJECTILE_SPEED: float = 16.0

var _spit_cooldown: float = 0.0


func _ready() -> void:
	super._ready()
	if stats != null and stats.type_name == &"":
		stats.type_name = &"spitter"


func _custom_tick(delta: float) -> void:
	_spit_cooldown = maxf(_spit_cooldown - delta, 0.0)
	if _spit_cooldown > 0.0 or ai == null or ai.target == null:
		return
	var distance: float = global_position.distance_to(ai.target.global_position)
	if distance > SPIT_RANGE or distance < 2.5:
		return
	_spit_cooldown = SPIT_COOLDOWN
	_spit(ai.target)


## Escupe un proyectil acido hacia el objetivo.
func _spit(target: Node3D) -> void:
	var scene: PackedScene = load("res://10_effects/AcidProjectile.tscn") as PackedScene
	if scene == null:
		return
	var projectile: Node3D = scene.instantiate() as Node3D
	get_tree().current_scene.add_child(projectile)
	var origin: Vector3 = global_position + Vector3.UP * 1.4
	var direction: Vector3 = (target.global_position + Vector3.UP * 1.0 - origin).normalized()
	projectile.global_position = origin
	if projectile.has_method("launch"):
		projectile.launch(direction, PROJECTILE_SPEED, SPIT_DAMAGE, SPIT_INFECTION, self)
	EventBus.sfx_requested.emit(&"spit_shot", global_position)
