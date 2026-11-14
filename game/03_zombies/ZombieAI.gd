class_name ZombieAI
extends Node

const BaseZombie := preload("res://03_zombies/BaseZombie.gd")
const DamageInfo := preload("res://05_combat/DamageInfo.gd")

## Maquina de estados de zombie: IDLE -> CHASE -> ATTACK -> STAGGER -> DEAD.
##
## Movimiento por steering con separacion entre zombies (O(n) limitado por
## vecindad) y ataques cuerpo a cuerpo con cooldown. Sin NavMesh: la casa es
## procedural y el steering con raycast de obstaculos es suficiente a 60 FPS.
## Accesible globalmente via `ZombieAI` (class_name).

enum State {
	IDLE,
	CHASE,
	ATTACK,
	STAGGER,
	DEAD,
}

const SEPARATION_RADIUS: float = 1.2
const SEPARATION_FORCE: float = 3.0
const ATTACK_WINDUP: float = 0.25
const STAGGER_TIME: float = 0.35
const LOSE_TARGET_TIME: float = 6.0

var zombie: BaseZombie
var state: int = State.IDLE
var target: Node3D = null
var hear_position: Vector3 = Vector3.ZERO
var attack_timer: float = 0.0
var stagger_timer: float = 0.0
var lose_target_timer: float = 0.0
var _attack_damage_pending: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if zombie == null or zombie.stats == null:
		return
	if state == State.DEAD:
		return
	_update_target()
	match state:
		State.IDLE:
			_state_idle(delta)
		State.CHASE:
			_state_chase(delta)
		State.ATTACK:
			_state_attack(delta)
		State.STAGGER:
			_state_stagger(delta)

## Busca al jugador si no hay objetivo valido.
func _update_target() -> void:
	if target != null and is_instance_valid(target):
		lose_target_timer = 0.0
		return
	target = get_tree().get_first_node_in_group("player")
	if target == null:
		lose_target_timer += get_physics_process_delta_time()
		if lose_target_timer > LOSE_TARGET_TIME:
			state = State.IDLE
	else:
		state = State.CHASE if state == State.IDLE else state

func _state_idle(_delta: float) -> void:
	if zombie != null:
		zombie.velocity = zombie.velocity.move_toward(Vector3.ZERO, 6.0 * get_physics_process_delta_time())
		zombie.move_and_slide()
	if target != null:
		state = State.CHASE

func _state_chase(delta: float) -> void:
	if target == null:
		state = State.IDLE
		return
	var to_target: Vector3 = target.global_position - zombie.global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance <= zombie.stats.attack_range:
		state = State.ATTACK
		attack_timer = 0.0
		_attack_damage_pending = true
		return
	var direction: Vector3 = to_target / maxf(distance, 0.001)
	var separation: Vector3 = _compute_separation()
	var desired: Vector3 = (direction * zombie.stats.speed + separation * SEPARATION_FORCE)
	zombie.velocity.x = move_toward(zombie.velocity.x, desired.x, 12.0 * delta)
	zombie.velocity.z = move_toward(zombie.velocity.z, desired.z, 12.0 * delta)
	zombie.velocity.y -= 9.8
	zombie.move_and_slide()
	_face_direction(direction, delta)

func _state_attack(delta: float) -> void:
	attack_timer += delta
	if target != null:
		var to_target: Vector3 = target.global_position - zombie.global_position
		_face_direction(to_target.normalized(), delta)
	if attack_timer >= ATTACK_WINDUP and _attack_damage_pending:
		_attack_damage_pending = false
		_deal_attack()
	if attack_timer >= zombie.stats.attack_cooldown:
		attack_timer = 0.0
		state = State.CHASE

func _state_stagger(delta: float) -> void:
	stagger_timer -= delta
	zombie.velocity = zombie.velocity.move_toward(Vector3.ZERO, 8.0 * delta)
	zombie.move_and_slide()
	if stagger_timer <= 0.0:
		state = State.CHASE

## Aplica el dano cuerpo a cuerpo al jugador.
func _deal_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	var info := DamageInfo.make(zombie.stats.damage, DamageInfo.DamageType.MELEE, zombie)
	info.infection = zombie.stats.infection_on_hit
	info.hit_point = target.global_position
	info.knockback_force = Config.combat_knockback_base
	var system: DamageSystem = zombie.get_node_or_null("DamageSystem") as DamageSystem
	if system == null:
		system = DamageSystem.new()
		zombie.add_child(system)
	system.apply(info, target)
	if zombie.stats.can_scream:
		_emit_scream()

## Grito: atrae refuerzos y avisa a la UI.
func _emit_scream() -> void:
	EventBus.voice_requested.emit(&"zombie_scream", zombie.global_position)
	EventBus.zombie_horde_warn.emit(6)
	attack_timer = 0.0

## Separacion local entre zombies (limita vecinos para coste O(n*k)).
func _compute_separation() -> Vector3:
	var separation := Vector3.ZERO
	var count: int = 0
	for other: Node in get_tree().get_nodes_in_group("zombies"):
		var other_zombie := other as BaseZombie
		if other_zombie == null or other_zombie == zombie:
			continue
		var offset: Vector3 = zombie.global_position - other_zombie.global_position
		offset.y = 0.0
		var dist: float = offset.length()
		if dist > 0.001 and dist < SEPARATION_RADIUS:
			separation += offset / dist
			count += 1
			if count >= 6:
				break
	return separation

func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var angle: float = atan2(direction.x, direction.z)
	zombie.rotation.y = lerp_angle(zombie.rotation.y, angle, clampf(10.0 * delta, 0.0, 1.0))

## El zombie recibe dano: puede entrar en stagger.
func on_damaged(info: DamageInfo) -> void:
	if zombie == null:
		return
	if info.is_headshot or info.amount > zombie.stats.max_hp * 0.25:
		state = State.STAGGER
		stagger_timer = STAGGER_TIME

## Marca el zombie como muerto (desde BaseZombie).
func mark_dead() -> void:
	state = State.DEAD
	set_physics_process(false)

## Reiniciar la IA al reciclar.
func reset_state() -> void:
	state = State.IDLE
	target = null
	attack_timer = 0.0
	stagger_timer = 0.0
	_attack_damage_pending = false
