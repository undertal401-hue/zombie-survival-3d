class_name ItemFactory


extends RefCounted
## Fabrica de items por identificador (data-driven).
##
## Registra los tipos de item y los crea sin que el invocador conozca la clase
## concreta. Asi ZombieLoot, LootTable y la tienda comparten una unica via.
## Accesible globalmente via `ItemFactory` (class_name).

var _registry: Dictionary = {}


func _init() -> void:
	register(&"ammo_light", AmmoPickup)
	register(&"ammo_heavy", AmmoPickup)
	register(&"ammo_shells", AmmoPickup)
	register(&"food_can", Food)
	register(&"potion_health", Potion)
	register(&"potion_antidote", Potion)
	register(&"potion_stamina", Potion)
	register(&"potion_adrenaline", Potion)
	register(&"health_kit", HealthKit)
	register(&"coin", CoinPickup)


## Registra una clase de item para un id.
## @param item_id: identificador.
## @param item_class: script de la subclase de ItemBase.
func register(item_id: StringName, item_class: Script) -> void:
	_registry[item_id] = item_class


## Crea una instancia de item por id.
## @param item_id: identificador registrado.
## @return ItemBase o null si no existe.
func create(item_id: StringName) -> ItemBase:
	var item_class: Script = _registry.get(item_id) as Script
	if item_class == null:
		return null
	return item_class.new() as ItemBase


## True si el id esta registrado.
func has(item_id: StringName) -> bool:
	return _registry.has(item_id)


## Lista de ids registrados.
func registered_ids() -> Array[StringName]:
	return _registry.keys()
