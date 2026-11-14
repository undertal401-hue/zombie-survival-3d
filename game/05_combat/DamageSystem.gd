class_name DamageSystem


extends Node
## Servicio central de calculo y aplicacion de dano.
##
## Punto unico de entrada: cualquier arma, explosion o trampa crea un
## DamageInfo y lo envia aqui. Aqui se aplican criticos, multiplicadores,
## inflacion por oleada y se deriva infeccion.
## Accesible globalmente via `DamageSystem` (class_name).

signal damage_applied(info: DamageInfo, target: Node3D)
signal damage_absorbed(info: DamageInfo, target: Node3D, absorbed: float)
signal headshot_registered(info: DamageInfo)

var headshot_multiplier: float = 2.0
var crit_chance: float = 0.05
var crit_multiplier: float = 1.75
var wave_number: int = 1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("damage_system")
	_rng.randomize()
	headshot_multiplier = Config.combat_headshot_multiplier
	crit_chance = Config.combat_crit_chance
	crit_multiplier = Config.combat_crit_multiplier


## Calcula el dano final aplicando headshot y critico.
## @param info: paquete base.
## @return paquete duplicado y modificado.
func calculate(info: DamageInfo) -> DamageInfo:
	var result: DamageInfo = info.duplicate_info()
	if result.is_headshot:
		result.amount *= headshot_multiplier
		headshot_registered.emit(result)
	if _rng.randf() < crit_chance:
		result.is_critical = true
		result.amount *= crit_multiplier
		EventBus.critical_hit.emit(result)
	return result


## Aplica el dano a un objetivo (Player o BaseZombie).
## @param info: paquete de dano.
## @param target: nodo con `receive_damage` o `take_damage`.
## @return true si el dano fue aplicado.
func apply(info: DamageInfo, target: Node3D) -> bool:
	if info == null or target == null or info.amount <= 0.0:
		return false
	var processed: DamageInfo = calculate(info)
	if target is Player:
		(target as Player).receive_damage(processed)
	elif target.has_method("take_damage"):
		target.take_damage(processed)
	else:
		return false
	damage_applied.emit(processed, target)
	EventBus.damage_dealt.emit(processed)
	return true


## Dano radial con falloff lineal.
## @param origin: centro de la explosion.
## @param radius: radio maximo.
## @param max_damage: dano en el centro.
## @param source: origen del dano.
func apply_radial(origin: Vector3, radius: float, max_damage: float, source: Node3D) -> int:
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
	var hits: Array[Dictionary] = space.intersect_shape(query, 64)
	for hit: Dictionary in hits:
		var collider: Node = hit.get("collider") as Node
		var node3d: Node3D = collider as Node3D
		if node3d == null:
			continue
		var distance: float = origin.distance_to(node3d.global_position)
		var falloff: float = clampf(1.0 - distance / radius, 0.0, 1.0)
		var info := DamageInfo.make(max_damage * falloff, DamageInfo.DamageType.EXPLOSION, source)
		info.hit_point = node3d.global_position
		info.hit_normal = (node3d.global_position - origin).normalized()
		if apply(info, node3d):
			applied += 1
	return applied
