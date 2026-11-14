extends Node
## Wrapper autoload para ItemFactory.

var factory

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ItemFactory = load("res://11_items/ItemFactory.gd")
	factory = ItemFactory.new()

func create(item_id: StringName) -> Object:
	return factory.create(item_id)

func has(item_id: StringName) -> bool:
	return factory.has(item_id)

func registered_ids() -> Array:
	return factory.registered_ids()
