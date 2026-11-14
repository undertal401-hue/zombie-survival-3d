class_name BaseZombie
extends CharacterBody3D

const ZombieStats := preload("res://03_zombies/ZombieStats.gd")
const ZombieAI := preload("res://03_zombies/ZombieAI.gd")
const ZombieLoot := preload("res://03_zombies/ZombieLoot.gd")
const HurtboxComponent := preload("res://05_combat/HurtboxComponent.gd")
const HitboxComponent := preload("res://05_combat/HitboxComponent.gd")
const DamageSystem := preload("res://05_combat/DamageSystem.gd")
const KnockbackSystem := preload("res://05_combat/KnockbackSystem.gd")
const DamageInfo := preload("res://05_combat/DamageInfo.gd")
const ZombieSpawner := preload("res://03_zombies/ZombieSpawner.gd")

## Entidad base de zombie: CharacterBody3D + componentes.
##
## Los 8 tipos concretos son subclases con comportamientos especificos
## (escupir, gritar, embestir). El dano, la muerte, el loot y el pooling son
## comunes a todos.
## Accesible globalmente via `BaseZombie` (class_name).

const ZOMBIE_LAYER: int = 2
const ZOMBIE_MASK: int = 1 | 4 | 8 | 64

@export var stats: ZombieStats = ZombieStats.new()
@export var apply_wave_scaling: bool = true

var ai: ZombieAI
var loot: ZombieLoot
var hurtbox: HurtboxComponent
var head_hurtbox: HurtboxComponent
var attack_hitbox: HitboxComponent
var _damage_system: DamageSystem
var _knockback: KnockbackSystem
var _target: Node3D = null
var _is_dead: bool = false
var current_wave: int = 1


func _ready() -> void:
	collision_layer = 1 << (ZOMBIE_LAYER - 1)
	collision_mask = ZOMBIE_MASK
	add_to_group("zombies")
	_build_components()
	_apply_scale()
	_damage_system = get_tree().get_first_node_in_group("damage_system") as DamageSystem
	if _damage_system == null:
		_damage_system = DamageSystem.new()
		_damage_system.name = "DamageSystem"
		add_child(_damage_system)
	_knockback = get_tree().get_first_node_in_group("knockback_system") as KnockbackSystem
	if _knockback == null:
		_knockback = KnockbackSystem.new()
		_knockback.name = "KnockbackSystem"
		add_child(_knockback)
	if stats.is_boss:
		add_to_group("bosses")
		EventBus.zombie_boss_spawned.emit(self)


## Construye los componentes hijos.
func _build_components() -> void:
	ai = ZombieAI.new()
	ai.name = "ZombieAI"
	ai.zombie = self
	add_child(ai)

	loot = ZombieLoot.new()
	loot.name = "ZombieLoot"
	loot.zombie = self
	add_child(loot)

	hurtbox = HurtboxComponent.new()
	hurtbox.name = "Hurtbox"
	hurtbox.part_name = &"torso"
	hurtbox.damage_multiplier = 1.0
	hurtbox.owner_entity = self
	add_child(hurtbox)

	head_hurtbox = HurtboxComponent.new()
	head_hurtbox.name = "HeadHurtbox"
	head_hurtbox.part_name = &"head"
	head_hurtbox.is_head = true
	head_hurtbox.damage_multiplier = stats.headshot_multiplier
	head_hurtbox.owner_entity = self
	add_child(head_hurtbox)

	attack_hitbox = HitboxComponent.new()
	attack_hitbox.name = "AttackHitbox"
	attack_hitbox.team = 2
	add_child(attack_hitbox)


## Aplica escala visual segun stats.
func _apply_scale() -> void:
	scale = stats.scale


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_custom_tick(delta)


## Punto de extension para los tipos concretos (runner, spitter, boss...).
## @param delta: delta escalado.
func _custom_tick(_delta: float) -> void:
	pass


## Recibe dano de cualquier fuente.
## @param info: DamageInfo con amount y origen.
func take_damage(info: DamageInfo) -> void:
	if _is_dead or info == null:
		return
	var applied: DamageInfo = info.duplicate_info()
	if applied.is_headshot:
		applied.amount *= stats.headshot_multiplier
	stats.current_hp = maxf(stats.current_hp - applied.amount, 0.0)
	if stats.current_hp <= 0.0:
		_die(applied)
	else:
		ai.on_damaged(applied)
		_apply_knockback(applied)
		EventBus.zombie_hit.emit(self, applied)


## Empleado por el sistema de dano cuando el golpe es letal.
func _die(info: DamageInfo) -> void:
	if _is_dead:
		return
	_is_dead = true
	set_physics_process(false)
	var killer: Node3D = info.source if info != null else null
	_spawn_loot(killer)
	_play_death_fx()
	EventBus.zombie_died.emit(self, killer, stats.coin_reward)
	_release_to_pool()


## Genera el botin del zombie.
func _spawn_loot(killer: Node3D) -> void:
	if loot != null:
		loot.drop_loot(killer)


## FX de muerte (sangre moderada PEGI 16).
func _play_death_fx() -> void:
	var fx: Node3D = get_node_or_null("../BloodSystem") as Node3D
	if fx != null and fx.has_method("spawn_blood"):
		fx.spawn_blood(global_position, Vector3.UP, 1.0)


## Knockback aplicado al zombie.
func _apply_knockback(info: DamageInfo) -> void:
	if _knockback == null or info.knockback_force <= 0.0:
		return
	var direction: Vector3 = global_position - info.source.global_position if info.source != null \
		else Vector3.UP
	direction.y = 0.0
	_knockback.apply(self, direction, info.knockback_force * stats.knockback_multiplier)


## Libera el zombie al pool si lo gestiona el spawner.
func _release_to_pool() -> void:
	var spawner: ZombieSpawner = get_tree().get_first_node_in_group("zombie_spawner") as ZombieSpawner
	if spawner != null and spawner.is_managed(self):
		spawner.release(self)
	else:
		queue_free()


## Multiplicador de masa para knockback (lo consume KnockbackSystem).
func get_knockback_multiplier() -> float:
	return stats.knockback_multiplier


## Objetivo actual del zombie.
func get_target() -> Node3D:
	return _target


## Contrato de pool: reactivacion.
func on_pool_acquired() -> void:
	_is_dead = false
	set_physics_process(true)
	visible = true


## Contrato de pool: desactivacion.
func on_pool_released() -> void:
	_is_dead = false
	visible = false


## Reinicio de estado al reciclar.
func reset_state() -> void:
	_is_dead = false
	if stats != null:
		stats.current_hp = stats.max_hp
	velocity = Vector3.ZERO


## Tipo del zombie.
func zombie_type() -> StringName:
	return stats.type_name
