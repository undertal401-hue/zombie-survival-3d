class_name WeaponManager


extends Node
## Gestor de armas del jugador: cambio de slot, disparo, apuntado y recarga.
##
## Componente de composicion (hijo de Player). No conoce armas concretas:
## trabaja con BaseWeapon y delega el comportamiento.
## Accesible globalmente via `WeaponManager` (class_name).

const SLOTS: int = 4

var player: Player
var weapons: Array[BaseWeapon] = []
var active_index: int = 0
var active_weapon: BaseWeapon = null


func _ready() -> void:
	var owner_node := owner
	if owner_node is Player:
		player = owner_node as Player


func _process(_delta: float) -> void:
	if player == null or player.input_handler == null:
		return
	_handle_switching()
	_handle_fire()
	_handle_reload()
	_sync_inventory()


## Cambio de slot con las acciones de switching.
func _handle_switching() -> void:
	var input: InputHandler = player.input_handler
	if input.is_action_just_pressed("switch_primary"):
		switch_to(active_index if active_index != 0 else 1)
	elif input.is_action_just_pressed("switch_secondary"):
		switch_to(2)
	elif input.is_action_just_pressed("switch_melee"):
		switch_to(3)
	elif input.is_action_just_pressed("switch_consumable"):
		switch_to(0)


## Disparo/golpe y apuntado.
func _handle_fire() -> void:
	var input: InputHandler = player.input_handler
	if active_weapon is RangedWeapon:
		var ranged := active_weapon as RangedWeapon
		ranged.set_ads(input.is_action_pressed("aim"))
		ranged.set_trigger_held(input.is_firing)
		if input.is_action_just_pressed("fire"):
			ranged.trigger_pulled()
		elif input.is_action_just_released("fire"):
			ranged.trigger_released()
	elif active_weapon is MeleeWeapon:
		var melee := active_weapon as MeleeWeapon
		if input.is_action_just_pressed("fire") or input.is_action_just_pressed("melee"):
			melee.trigger_pulled()
		elif input.is_action_just_released("fire"):
			melee.trigger_released()


## Recarga.
func _handle_reload() -> void:
	if active_weapon == null:
		return
	if player.input_handler.is_action_just_pressed("reload"):
		active_weapon.reload()


## Sincroniza el estado del inventario con el activo.
func _sync_inventory() -> void:
	if player.inventory == null:
		return
	var target: BaseWeapon = player.inventory.get_weapon_at(active_index)
	if target != active_weapon:
		switch_to(active_index)


## Registra un arma y la cuelga del jugador.
## @param weapon: arma a registrar.
## @return true si se pudo.
func register_weapon(weapon: BaseWeapon) -> bool:
	if weapon == null:
		return false
	weapon.set_wielder(player)
	add_child(weapon)
	weapons.append(weapon)
	weapon.set_equipped(false)
	return true


## Cambia al slot indicado.
## @param slot_index: 0..3.
func switch_to(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= SLOTS:
		return
	var target: BaseWeapon = player.inventory.get_weapon_at(slot_index) if player.inventory != null else null
	if target == null:
		return
	if active_weapon != null:
		active_weapon.set_equipped(false)
	active_weapon = target
	active_index = slot_index
	active_weapon.set_equipped(true)
	EventBus.weapon_equipped.emit(active_weapon)


## Recarga el arma activa.
func reload_active() -> void:
	if active_weapon != null:
		active_weapon.reload()


## Arsenal actual (telemetria/tests).
func arsenal_report() -> Dictionary:
	var report := {}
	for i: int in weapons.size():
		var weapon: BaseWeapon = weapons[i]
		report[weapon.data.weapon_id] = {
			"magazine": weapon.magazine,
			"reserve": weapon.reserve_ammo,
			"equipped": weapon.is_equipped,
		}
	return report
