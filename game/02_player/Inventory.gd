extends Node

signal inventory_changed

const DISPLAY_NAMES := {
	"combustible": "Bidón de combustible",
	"medkit": "Botiquín",
	"comida": "Comida enlatada",
}

var _items: Dictionary = {}

func add_item(id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	_items[id] = _items.get(id, 0) + amount
	inventory_changed.emit()

func remove_item(id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var have: int = _items.get(id, 0)
	if have < amount:
		return false
	_items[id] = have - amount
	inventory_changed.emit()
	return true

func count(id: String) -> int:
	return _items.get(id, 0)

func has(id: String) -> bool:
	return count(id) > 0

func total() -> int:
	var sum: int = 0
	for n in _items.values():
		sum += n
	return sum

func clear() -> void:
	_items.clear()
	inventory_changed.emit()

func display_name(id: String) -> String:
	return DISPLAY_NAMES.get(id, id)
