class_name RangedWeapon
extends BaseWeapon
const BaseWeapon := preload("res://04_weapons/BaseWeapon.gd")
const DamageSystem := preload("res://05_combat/DamageSystem.gd")
const DamageInfo := preload("res://05_combat/DamageInfo.gd")
const ProjectilePool := preload("res://04_weapons/ProjectilePool.gd")
const BulletTracer := preload("res://04_weapons/BulletTracer.gd")
const RecoilComponent := preload("res://04_weapons/RecoilComponent.gd")
const ADSComponent := preload("res://04_weapons/ADSComponent.gd")

## Arma de fuego a distancia (hitscan o proyectil).
##
## Modos: SEMI, AUTO, PUMP, BOLT, PROJECTILE. Gestiona dispersion, retroceso,
## recarga y efectos. No conoce al zombie concreto: aplica dano por
## DamageSystem y notifica por EventBus.

const SPREAD_STEP: float = 0.05
const MAX_SPREAD_ACCUM: float = 3.0

var recoil: RecoilComponent
var ads: ADSComponent
var is_trigger_held: bool = false
var is_ads_active: bool = false
var fire_timer: float = 0.0
var spread_accumulator: float = 0.0
var _projectile_pool: ProjectilePool
var _tracers: BulletTracer
var _damage_system: DamageSystem

func _ready() -> void:
	super._ready()
	recoil = RecoilComponent.new()
	recoil.name = "Recoil"
	recoil.configure(data.spread_degrees, data.recoil)
	add_child(recoil)
	ads = ADSComponent.new()
	ads.name = "ADS"
	ads.configure(75.0, data.ads_fov)
	add_child(ads)
	_projectile_pool = ProjectilePool.new()
	_projectile_pool.name = "ProjectilePool"
	add_child(_projectile_pool)
	_tracers = BulletTracer.new()
	_tracers.name = "Tracers"
	add_child(_tracers)
	_damage_system = get_tree().get_first_node_in_group("damage_system") as DamageSystem
	if _damage_system == null:
		_damage_system = DamageSystem.new()
		_damage_system.name = "DamageSystem"
		add_child(_damage_system)

func _process(delta: float) -> void:
	fire_timer = maxf(fire_timer - delta, 0.0)
	spread_accumulator = maxf(spread_accumulator - SPREAD_STEP * delta, 0.0)
	ads.is_aiming = is_ads_active
	if is_trigger_held and data.fire_mode == WeaponData.FireMode.AUTO:
		_try_fire()

## Gatillo mantenido (para AUTO).
func set_trigger_held(held: bool) -> void:
	is_trigger_held = held

## Apuntado (ADS) mantenido.
func set_ads(active: bool) -> void:
	is_ads_active = active

## Gatillo pulsado: SEMI, PUMP, BOLT, PROJECTILE, CHARGE.
func trigger_pulled() -> void:
	if data == null:
		return
	match data.fire_mode:
		WeaponData.FireMode.AUTO:
			return
		WeaponData.FireMode.PUMP, WeaponData.FireMode.BOLT, \
				WeaponData.FireMode.SEMI, WeaponData.FireMode.PROJECTILE, \
				WeaponData.FireMode.CHARGE:
			_try_fire()

func _try_fire() -> void:
	if not can_fire() or fire_timer > 0.0:
		if magazine <= 0 and not is_reloading:
			reload()
		return
	fire_timer = data.shot_interval()
	if data.uses_projectile():
		_fire_projectile()
	else:
		_fire_hitscan()
	super.fire()
	recoil.add_shot()
	EventBus.weapon_fired.emit(self, get_muzzle_position(), get_fire_direction())
	_notify_camera_shake()

## Disparo hitscan con perdigones y dispersion.
func _fire_hitscan() -> void:
	var origin: Vector3 = _get_shot_origin()
	var base_direction: Vector3 = get_fire_direction()
	var spread: float = deg_to_rad(recoil.current_spread(is_ads_active) + spread_accumulator)
	for i: int in maxi(data.pellets, 1):
		var direction: Vector3 = _apply_spread(base_direction, spread)
		_raycast_shot(origin, direction)
	spread_accumulator = minf(spread_accumulator + 0.25, MAX_SPREAD_ACCUM)
	_spawn_muzzle_flash()

## Raycast individual contra zombies y entorno.
func _raycast_shot(origin: Vector3, direction: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var end: Vector3 = origin + direction * data.range
	var query := PhysicsRayQueryParameters3D.create(origin, end, (1 << 1) | (1 << 3))
	# La mascara del query ya excluye la capa del jugador: no hace falta exclude.
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		_tracers.spawn(origin, end)
		return
	var point: Vector3 = hit.get("position", end)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	_tracers.spawn(origin, point)
	var collider: Node = hit.get("collider") as Node
	if collider is Node3D:
		_apply_hit(collider as Node3D, point, normal, direction)

## Aplica dano a un impacto.
func _apply_hit(target: Node3D, point: Vector3, normal: Vector3, direction: Vector3) -> void:
	var distance: float = get_muzzle_position().distance_to(point)
	var info := DamageInfo.make(data.damage_at_distance(distance), DamageInfo.DamageType.BULLET, get_wielder())
	info.hit_point = point
	info.hit_normal = normal
	info.knockback_force = data.knockback
	info.weapon_id = data.weapon_id
	info.infection = data.infection
	if target.has_method("take_damage"):
		_damage_system.apply(info, target)
	elif target is Player:
		_damage_system.apply(info, target)

## Disparo de proyectil (ballesta, lanzagranadas, experimental).
func _fire_projectile() -> void:
	_projectile_pool.ensure_initialized(data.projectile_scene)
	var projectile: Projectile = _projectile_pool.acquire()
	if projectile == null:
		return
	var origin: Vector3 = get_muzzle_position()
	var direction: Vector3 = get_fire_direction()
	get_tree().current_scene.add_child(projectile)
	projectile.launch(origin, direction, data.projectile_speed, data.projectile_gravity,
		data.damage, data.headshot_multiplier, data.infection, data.knockback, get_wielder())
	match data.ammo_type:
		WeaponData.AmmoType.ROCKETS:
			projectile.set_explosive(4.5)
		WeaponData.AmmoType.EXPERIMENTAL:
			projectile.set_explosive(5.5)
	_spawn_muzzle_flash()

## Origen del disparo: camara si es el jugador, si no el arma.
func _get_shot_origin() -> Vector3:
	var owner_node := get_wielder()
	if owner_node is Player and (owner_node as Player).camera_rig != null:
		var camera: Camera3D = (owner_node as Player).camera_rig.camera
		if camera != null:
			return camera.global_position
	return get_muzzle_position()

## Aplica dispersion aleatoria dentro del cono.
func _apply_spread(direction: Vector3, spread_radians: float) -> Vector3:
	if spread_radians <= 0.0001:
		return direction
	var basis: Basis = Basis.from_euler(Vector3(
		randf_range(-spread_radians, spread_radians),
		randf_range(-spread_radians, spread_radians),
		0.0))
	return (basis * direction).normalized()

func _spawn_muzzle_flash() -> void:
	EventBus.sfx_requested.emit(&"muzzle_flash", get_muzzle_position())
	EventBus.weapon_trigger_pulled.emit(self)

func _notify_camera_shake() -> void:
	var owner_node := get_wielder()
	if owner_node is Player and (owner_node as Player).camera_rig != null:
		(owner_node as Player).camera_rig.add_shake(data.recoil * 0.25)

## Proyectil pool interno (expuesto para tests).
func get_projectile_pool() -> ProjectilePool:
	return _projectile_pool
