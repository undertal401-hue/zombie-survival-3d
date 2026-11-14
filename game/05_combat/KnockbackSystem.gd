class_name KnockbackSystem


extends Node
## Servicio de empuje (knockback).
##
## Aplica impulso a CharacterBody3D y a zombies, escalando por masa y por el
## multiplicador de knockback del arma. Respeta la capa de fisicas.
## Accesible globalmente via `KnockbackSystem` (class_name).

const MIN_IMPULSE: float = 1.0
const MAX_IMPULSE: float = 18.0


func _ready() -> void:
	add_to_group("knockback_system")


## Aplica un impulso a un objetivo.
## @param target: nodo fisico (CharacterBody3D o RigidBody3D).
## @param direction: direccion normalizada.
## @param force: fuerza base del impacto.
## @return true si se aplico.
func apply(target: Node3D, direction: Vector3, force: float) -> bool:
	if target == null:
		return false
	var impulse: Vector3 = direction.normalized() * clampf(force, MIN_IMPULSE, MAX_IMPULSE)
	if target is CharacterBody3D:
		var body := target as CharacterBody3D
		var mass: float = 1.0
		if body.has_method("get_knockback_multiplier"):
			mass = body.get_knockback_multiplier()
		body.velocity += impulse / maxf(mass, 0.2)
		if body.is_inside_tree():
			body.move_and_slide()
	elif target is RigidBody3D:
		var rigid := target as RigidBody3D
		rigid.apply_impulse(impulse / maxf(rigid.mass, 0.2))
	else:
		return false
	EventBus.knockback_applied.emit(target, impulse)
	return true


## Aplica un impulso radial desde un origen.
## @param origin: centro.
## @param radius: radio de efecto.
## @param force: fuerza maxima en el centro.
func apply_radial(origin: Vector3, radius: float, force: float) -> int:
	if not is_inside_tree():
		return 0
	var applied: int = 0
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = (1 << 0) | (1 << 1)
	for hit: Dictionary in space.intersect_shape(query, 64):
		var node3d: Node3D = hit.get("collider") as Node3D
		if node3d == null:
			continue
		var dir: Vector3 = (node3d.global_position - origin).normalized()
		var falloff: float = clampf(1.0 - origin.distance_to(node3d.global_position) / radius, 0.2, 1.0)
		if apply(node3d, dir, force * falloff):
			applied += 1
	return applied
