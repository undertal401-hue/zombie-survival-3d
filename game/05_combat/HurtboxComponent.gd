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


## Aplica un modificador de parte al dano entrante.
## @param info: paquete de dano.
## @return paquete ajustado.
func modify_damage(info: DamageInfo) -> DamageInfo:
	var adjusted: DamageInfo = info.duplicate_info()
	adjusted.amount *= damage_multiplier
	adjusted.is_headshot = adjusted.is_headshot or is_head
	return adjusted
