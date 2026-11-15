extends Node

signal inventory_changed

var _items: Dictionary = {}

func add_item(id: String, amount: int = 1) -> void:
	_items[id] = _items.get(id, 0) + amount
	inventory_changed.emit()

func remove_item(id: String, amount: int = 1) -> bool:
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
