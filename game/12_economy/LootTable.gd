class_name LootTable

extends Resource
## Tabla de botin con pesos (data-driven).
##
## Usada por zombies, cofres y la fase de tienda. Soporta drop unico o
## múltiple con seed determinista.
## Accesible globalmente via `LootTable` (class_name).

@export var table_id: StringName = &"loot"
@export var entries: Array[Dictionary] = []
@export var rolls: int = 1
@export var guaranteed_coins: int = 0


## Anade una entrada de botin.
## @param item_id: identificador del item.
## @param weight: peso relativo.
## @param min_qty: cantidad minima.
## @param max_qty: cantidad maxima.
func add_entry(item_id: StringName, weight: float, min_qty: int = 1, max_qty: int = 1) -> void:
	entries.append({
		"item_id": item_id, "weight": maxf(weight, 0.0),
		"min_qty": mini(min_qty, max_qty), "max_qty": maxi(max_qty, min_qty),
	})


## Peso total.
func total_weight() -> float:
	var total: float = 0.0
	for entry: Dictionary in entries:
		total += float(entry.get("weight", 0.0))
	return total


## Realiza los rolls y devuelve resultados.
## @param rng: generador aleatorio.
## @return Array[Dictionary] con item_id y qty.
func roll(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var picker := WeightedPicker.new()
	for entry: Dictionary in entries:
		picker.add(entry["item_id"], float(entry["weight"]))
	for i: int in rolls:
		var item_id: StringName = picker.pick(rng)
		if item_id == &"":
			continue
		var entry: Dictionary = _entry(item_id)
		var qty: int = rng.randi_range(int(entry["min_qty"]), int(entry["max_qty"]))
		results.append({"item_id": item_id, "qty": qty})
	return results


func _entry(item_id: StringName) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.get("item_id", &"") == item_id:
			return entry
	return {"min_qty": 1, "max_qty": 1}
