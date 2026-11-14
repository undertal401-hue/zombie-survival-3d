class_name DamageInfo

extends Resource
## Paquete inmutable de datos de un golpe.
##
## Transporta toda la informacion relevante de un impacto para que el
## DamageSystem y los subsistemas (sangre, knockback, UI) reaccionen.
## Accesible globalmente via `DamageInfo` (class_name).

enum DamageType {
	NONE,
	BULLET,
	MELEE,
	EXPLOSION,
	FIRE,
	ACID,
	FALL,
	INFECTION,
}

@export var amount: float = 0.0
@export var damage_type: DamageType = DamageType.BULLET
@export var source: Variant = null
@export var infection: float = 0.0
@export var is_critical: bool = false
@export var is_headshot: bool = false
@export var hit_point: Vector3 = Vector3.ZERO
@export var hit_normal: Vector3 = Vector3.UP
@export var knockback_force: float = 0.0
@export var weapon_id: StringName = &""


## Fabrica un DamageInfo con valores por defecto coherentes.
static func make(p_amount: float, p_type: DamageType, p_source: Node3D) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = p_amount
	info.damage_type = p_type
	info.source = p_source
	return info


## Copia del paquete (para no mutar el original entre sistemas).
func duplicate_info() -> DamageInfo:
	var copy: DamageInfo = duplicate() as DamageInfo
	return copy
