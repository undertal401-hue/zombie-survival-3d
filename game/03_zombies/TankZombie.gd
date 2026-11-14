class_name TankZombie
extends BaseZombie
## Zombie tanque: armadura que reduce dano de bala y mucha vida.

const BaseZombie := preload("res://03_zombies/BaseZombie.gd")

const BULLET_REDUCTION: float = 0.35
const EXPLOSION_REDUCTION: float = 0.15


func _ready() -> void:
	super._ready()
	if stats != null and stats.type_name == &"":
		stats.type_name = &"tank"


## Reduce el dano de proyectiles y explosiones (armadura).
func take_damage(info: DamageInfo) -> void:
	if info == null:
		return
	var adjusted: DamageInfo = info.duplicate_info()
	match info.damage_type:
		DamageInfo.DamageType.BULLET:
			adjusted.amount *= (1.0 - BULLET_REDUCTION)
		DamageInfo.DamageType.EXPLOSION:
			adjusted.amount *= (1.0 - EXPLOSION_REDUCTION)
	super.take_damage(adjusted)
