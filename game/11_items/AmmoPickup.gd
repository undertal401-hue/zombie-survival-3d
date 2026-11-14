class_name AmmoPickup

extends ItemBase
## Municion recogible: rellenan el reserva del arma activa o de todas.

const ItemBase := preload("res://11_items/ItemBase.gd")
const Inventory := preload("res://02_player/Inventory.gd")
const BaseWeapon := preload("res://04_weapons/BaseWeapon.gd")

@export var ammo_amount: int = 30
@export var ammo_type: StringName = &"light"
@export var refill_all_weapons: bool = false

func _init() -> void:
	item_id = &"ammo_light"
	display_name = "Municion"
	description = "Restaura municion de reserva."
	value = 15

func apply(player: Node3D) -> bool:
	if player == null or not player.has_method("get_inventory"):
		return false
	var inventory: Inventory = player.get_inventory()
	if inventory == null:
		return false
	var total_added: int = 0
	if refill_all_weapons:
		for weapon: BaseWeapon in _all_weapons(inventory):
			total_added += weapon.add_reserve_ammo(ammo_amount)
	else:
		var active: BaseWeapon = inventory.active_weapon
		if active != null:
			total_added = active.add_reserve_ammo(ammo_amount)
	if total_added <= 0:
		return false
	if inventory.active_weapon != null:
		EventBus.ammo_changed.emit(inventory.active_weapon,
			inventory.active_weapon.magazine, inventory.active_weapon.reserve_ammo)
	EventBus.sfx_2d_requested.emit(&"pickup_ammo")
	return true

func get_interaction_prompt() -> String:
	return "Recoger municion (+%d)" % ammo_amount

func _all_weapons(inventory: Inventory) -> Array[BaseWeapon]:
	var result: Array[BaseWeapon] = []
	result.append_array(inventory.primary_slots)
	result.append_array(inventory.secondary_slots)
	result.append_array(inventory.melee_slots)
	return result
