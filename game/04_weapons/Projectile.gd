class_name Projectile


extends Node3D
## Proyectil de bala/granada/rayo con raycast por frame.
##
## Mas barato que un RigidBody3D: sin simulacion de fisicas, solo raycast
## movimiento. Se recicla desde ProjectilePool.
## Accesible globalmente via `Projectile` (class_name).

const DEFAULT_LIFE: float = 4.0
const RAYCAST_MASK: int = (1 << 1) | (1 << 3) | (1 << 4)

var velocity: Vector3 = Vector3.ZERO
var gravity: float = 0.0
var damage: float = 0.0
var headshot_multiplier: float = 2.0
var infection: float = 0.0
var knockback: float = 0.0
var source: Node3D = null
var lifetime: float = DEFAULT_LIFE
var is_explosive: bool = false
var explosion_radius: float = 0.0
var _damage_system: DamageSystem
var _previous_position: Vector3 = Vector3.ZERO
var _alive: bool = false


func _ready() -> void:
	_damage_system = get_tree().get_first_node_in_group("damage_system") as DamageSystem
	if _damage_system == null:
		_damage_system = DamageSystem.new()
		_damage_system.name = "DamageSystem"
		add_child(_damage_system)


## Lanza el proyectil.
## @param origin: posicion inicial.
## @param direction: direccion normalizada.
## @param speed: velocidad m/s.
## @param p_gravity: gravedad aplicada.
## @param p_damage: dano base.
## @param p_headshot_mult: multiplicador de cabeza.
## @param p_infection: infeccion asociada.
## @param p_knockback: fuerza de empuje.
## @param p_source: origen del disparo.
func launch(origin: Vector3, direction: Vector3, speed: float, p_gravity: float,
		p_damage: float, p_headshot_mult: float, p_infection: float,
		p_knockback: float, p_source: Node3D) -> void:
	global_position = origin
	_previous_position = origin
	velocity = direction.normalized() * maxf(speed, 0.1)
	gravity = p_gravity
	damage = p_damage
	headshot_multiplier = p_headshot_mult
	infection = p_infection
	knockback = p_knockback
	source = p_source
	lifetime = DEFAULT_LIFE
	_alive = true


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_explode_or_release()
		return
	velocity.y -= gravity * delta
	var target: Vector3 = global_position + velocity * delta
	_raycast_step(global_position, target)
	global_position = target


## Raycast del paso y resolucion de impacto.
func _raycast_step(from: Vector3, to: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, RAYCAST_MASK)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return
	var point: Vector3 = hit.get("position", to)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var collider: Node = hit.get("collider") as Node
	if collider is Node3D and (collider is BaseZombie or collider is Player):
		_impact_creature(collider as Node3D, point, normal)
	else:
		_impact_surface(point, normal)


## Impacto en criatura: aplica dano.
func _impact_creature(creature: Node3D, point: Vector3, normal: Vector3) -> void:
	var info := DamageInfo.make(damage, DamageInfo.DamageType.EXPLOSION if is_explosive
		else DamageInfo.DamageType.BULLET, source)
	info.hit_point = point
	info.hit_normal = normal
	info.infection = infection
	info.knockback_force = knockback
	_damage_system.apply(info, creature)
	_explode_or_release()


## Impacto en superficie: chispa y posible explosion.
func _impact_surface(point: Vector3, normal: Vector3) -> void:
	if is_explosive:
		_explode(point)
	else:
		_spawn_spark(point, normal)
		_release()


func _explode_or_release() -> void:
	if is_explosive:
		_explode(global_position)
	else:
		_release()


## Explosion con dano radial.
func _explode(point: Vector3) -> void:
	var system: ExplosionSystem = get_tree().get_first_node_in_group("explosion_system") as ExplosionSystem
	if system == null:
		system = ExplosionSystem.new()
		add_child(system)
	system.detonate(point, maxf(explosion_radius, 3.0), damage, source)
	_release()


func _spawn_spark(point: Vector3, normal: Vector3) -> void:
	EventBus.sfx_requested.emit(&"bullet_impact", point)
	# El ImpactSystem global genera el decal/chispa.
	EventBus.hit_registered.emit(DamageInfo.make(0.0, DamageInfo.DamageType.BULLET, source))


## Contrato de pool: reactivacion.
func on_pool_acquired() -> void:
	_alive = false
	velocity = Vector3.ZERO
	visible = false


## Contrato de pool: desactivacion.
func on_pool_released() -> void:
	_alive = false
	visible = false


## Reinicio de estado.
func reset_state() -> void:
	_alive = false
	velocity = Vector3.ZERO
	lifetime = DEFAULT_LIFE


## Libera el proyectil a su pool.
func _release() -> void:
	_alive = false
	var pool: ProjectilePool = get_parent() as ProjectilePool
	if pool != null:
		pool.release(self)
	else:
		queue_free()


## Configura explosion (granadas/experimental).
## @param radius: radio de explosion.
func set_explosive(radius: float) -> void:
	is_explosive = radius > 0.0
	explosion_radius = radius
