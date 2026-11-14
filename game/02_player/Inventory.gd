class_name Inventory

extends Resource
## Inventario del jugador (componente de composicion).
##
## 4 slots de arma: 2 primarias, 1 secundaria, 1 cuerpo a cuerpo.
## Ademas, una cola de consumibles. Notifica cambios por senales.
## Accesible globalmente via `Inventory` (class_name).

signal slot_changed(slot_index: int, weapon: BaseWeapon)
signal consumable_added(consumable: ItemBase)
signal consumable_removed(consumable: ItemBase)
signal inventory_full

const MAX_PRIMARY_SLOTS: int = 2
const MAX_SECONDARY_SLOTS: int = 1
const MAX_MELEE_SLOTS: int = 1
const MAX_CONSUMABLES: int = 8

var primary_slots: Array[BaseWeapon] = []
var secondary_slots: Array[BaseWeapon] = []
var melee_slots: Array[BaseWeapon] = []
var consumables: Array[ItemBase] = []
var active_slot: int = 0
var active_weapon: BaseWeapon = null


## Anade un arma al slot correspondiente segun sus datos.
## @param weapon: arma a anadir.
## @return true si hubo espacio.
func add_weapon(weapon: BaseWeapon) -> bool:
	if weapon == null:
		return false
	var data: WeaponData = weapon.data
	match data.slot_type:
		WeaponData.SlotType.PRIMARY:
			if primary_slots.size() >= MAX_PRIMARY_SLOTS:
				emit_signal("inventory_full")
				return false
			primary_slots.append(weapon)
		WeaponData.SlotType.SECONDARY:
			if secondary_slots.size() >= MAX_SECONDARY_SLOTS:
				emit_signal("inventory_full")
				return false
			secondary_slots.append(weapon)
		WeaponData.SlotType.MELEE:
			if melee_slots.size() >= MAX_MELEE_SLOTS:
				emit_signal("inventory_full")
				return false
			melee_slots.append(weapon)
	slot_changed.emit(primary_slots.size() + secondary_slots.size() + melee_slots.size() - 1, weapon)
	return true


## Equipa el arma activa por indice de slot.
## @param slot_index: 0..3 (primaria 0-1, secundaria 2, melee 3).
## @return el arma equipada o null.
func equip_slot(slot_index: int) -> BaseWeapon:
	var weapon: BaseWeapon = _weapon_at(slot_index)
	if weapon == null:
		return null
	if active_weapon != null:
		active_weapon.set_equipped(false)
	active_weapon = weapon
	active_slot = slot_index
	weapon.set_equipped(true)
	slot_changed.emit(slot_index, weapon)
	return weapon


## Devuelve el arma en un slot global (0..3), API publica.
## @param slot_index: 0..3.
## @return el arma o null.
func get_weapon_at(slot_index: int) -> BaseWeapon:
	return _weapon_at(slot_index)


## Devuelve el arma en un slot global (0..3).
func _weapon_at(slot_index: int) -> BaseWeapon:
	match slot_index:
		0, 1:
			return primary_slots[slot_index] if slot_index < primary_slots.size() else null
		2:
			return secondary_slots[0] if not secondary_slots.is_empty() else null
		3:
			return melee_slots[0] if not melee_slots.is_empty() else null
	return null


## Anade un consumible si hay espacio.
func add_consumable(item: ItemBase) -> bool:
	if consumables.size() >= MAX_CONSUMABLES:
		emit_signal("inventory_full")
		return false
	consumables.append(item)
	consumable_added.emit(item)
	return true


## Consume el primer consumible de un tipo dado.
## @param item_class: clase del item (Potion, Food, HealthKit).
## @return el item consumido o null.
func consume_first_of_type(item_class: Script) -> ItemBase:
	for i: int in consumables.size():
		var item: ItemBase = consumables[i]
		if is_instance_of(item, item_class):
			consumables.remove_at(i)
			consumable_removed.emit(item)
			return item
	return null


## Elimina un arma del inventario.
func remove_weapon(weapon: BaseWeapon) -> void:
	for slot: Array in [primary_slots, secondary_slots, melee_slots]:
		if slot.has(weapon):
			slot.erase(weapon)
			if active_weapon == weapon:
				active_weapon = null
			slot_changed.emit(-1, null)
			return


## Serializa el inventario.
func to_dict() -> Dictionary:
	return {
		"primary": primary_slots.map(func(w: BaseWeapon) -> String: return w.data.weapon_id),
		"secondary": secondary_slots.map(func(w: BaseWeapon) -> String: return w.data.weapon_id),
		"melee": melee_slots.map(func(w: BaseWeapon) -> String: return w.data.weapon_id),
		"active_slot": active_slot,
		"consumables": consumables.map(func(i: ItemBase) -> String: return i.item_id),
	}
