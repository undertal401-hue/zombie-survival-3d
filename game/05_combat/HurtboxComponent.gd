class_name HurtboxComponent


extends Area3D
## Hurtbox: marca una zona del cuerpo como danyable y redirige el dano.
##
## Permite hitboxes por parte (cabeza, torso, extremidades) con multiplicador
## propio. El dano se reenvia al nodo propietario (`take_damage`).
## Accesible globalmente via `HurtboxComponent` (class_name).

const HURTBOX_LAYER: int = 1

@export var part_name: StringName = &"torso"
@export var damage_multiplier: float = 1.0
@export var is_head: bool = false

var owner_entity: Node3D = null


func _ready() -> void:
	collision_layer = 1 << (HURTBOX_LAYER - 1)
	collision_mask = 0
	if owner_entity == null:
		owner_entity = owner as Node3D
	_build_shape()

func _build_shape() -> void:
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	if is_head:
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = 0.3
		shape_node.shape = sphere
		shape_node.position = Vector3(0.0, 1.0, 0.0)
	else:
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.2
		shape_node.shape = capsule
		shape_node.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape_node)


## Aplica un modificador de parte al dano entrante.
## @param info: paquete de dano.
## @return paquete ajustado.
func modify_damage(info: DamageInfo) -> DamageInfo:
	var adjusted: DamageInfo = info.duplicate_info()
	adjusted.amount *= damage_multiplier
	adjusted.is_headshot = adjusted.is_headshot or is_head
	return adjusted
