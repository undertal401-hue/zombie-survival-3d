class_name MeleeWeapon
extends BaseWeapon
const BaseWeapon := preload("res://04_weapons/BaseWeapon.gd")
const DamageSystem := preload("res://05_combat/DamageSystem.gd")
const KnockbackSystem := preload("res://05_combat/KnockbackSystem.gd")
const DamageInfo := preload("res://05_combat/DamageInfo.gd")

## Arma cuerpo a cuerpo: arco de golpe, carga y consumo de stamina.
##
## El dano se aplica en un arco frontal. Mantener el gatillo carga un golpe
## potenciado que cuesta stamina (20 por defecto).

const SWING_COOLDOWN_BUFFER: float = 0.05
const CHARGE_STAMINA_COST: float = 20.0

var swing_timer: float = 0.0
var charge_time: float = 0.0
var is_charging: bool = false
var is_trigger_held: bool = false
var _damage_system: DamageSystem
var _knockback: KnockbackSystem

func _ready() -> void:
	super._ready()
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

func _process(delta: float) -> void:
	swing_timer = maxf(swing_timer - delta, 0.0)
	if is_trigger_held:
		charge_time = minf(charge_time + delta, data.melee_charge_time)
		if data.fire_mode == WeaponData.FireMode.AUTO and swing_timer <= 0.0:
			_swing(1.0)

## Gatillo pulsado: inicia carga.
func trigger_pulled() -> void:
	if data == null:
		return
	is_trigger_held = true
	if data.fire_mode == WeaponData.FireMode.AUTO:
		return
	if swing_timer <= 0.0:
		_swing(1.0)

## Gatillo liberado: golpe cargado.
func trigger_released() -> void:
	if data == null:
		return
	is_trigger_held = false
	if data.fire_mode == WeaponData.FireMode.AUTO:
		return
	var multiplier: float = 1.0
	if charge_time >= data.melee_charge_time:
		multiplier = data.melee_charge_multiplier
		_spend_charge_stamina()
	charge_time = 0.0
	if swing_timer <= 0.0:
		_swing(multiplier)

## Ejecuta el arco de golpe.
## @param multiplier: multiplicador por carga.
func _swing(multiplier: float) -> void:
	swing_timer = 1.0 / maxf(data.fire_rate, 0.01) + SWING_COOLDOWN_BUFFER
	var hits: int = _arc_hit(multiplier)
	EventBus.melee_swing_started.emit(self)
	if hits > 0:
		EventBus.melee_hit_registered.emit(self, hits)
	EventBus.sfx_requested.emit(&"melee_swing", global_position)

## Detecta zombies dentro del arco frontal.
## @return numero de impactos.
func _arc_hit(multiplier: float) -> int:
	var owner_node := get_wielder()
	if owner_node == null:
		return 0
	var forward: Vector3 = -owner_node.global_transform.basis.z
	var hits: int = 0
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as BaseZombie
		if zombie == null:
			continue
		var to_zombie: Vector3 = zombie.global_position - owner_node.global_position
		to_zombie.y = 0.0
		var distance: float = to_zombie.length()
		if distance > data.melee_range:
			continue
		var angle: float = rad_to_deg(forward.angle_to(to_zombie / maxf(distance, 0.001)))
		if angle > data.melee_arc_degrees * 0.5:
			continue
		var info := DamageInfo.make(data.damage * multiplier, DamageInfo.DamageType.MELEE, owner_node)
		info.hit_point = zombie.global_position
		info.hit_normal = to_zombie.normalized()
		info.knockback_force = data.knockback * multiplier
		info.weapon_id = data.weapon_id
		info.infection = data.infection
		if _damage_system.apply(info, zombie):
			hits += 1
	return hits

## Consume stamina por golpe cargado.
func _spend_charge_stamina() -> void:
	var owner_node := get_wielder()
	if owner_node is Player:
		(owner_node as Player).stats.try_consume_stamina(CHARGE_STAMINA_COST)

## Progreso de carga 0..1 (UI).
func charge_ratio() -> float:
	return clampf(charge_time / maxf(data.melee_charge_time, 0.001), 0.0, 1.0)
