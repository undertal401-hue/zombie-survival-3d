class_name WeightedPicker

extends RefCounted
## Selector aleatorio ponderado reutilizable.

var _entries: Array[Dictionary] = []
var _total: float = 0.0


## Anade una opcion con peso.
## @param value: valor a seleccionar.
## @param weight: peso relativo (> 0).
func add(value: StringName, weight: float) -> void:
	if weight <= 0.0:
		return
	_entries.append({"value": value, "weight": weight})
	_total += weight


## Elije una opcion segun pesos.
## @param rng: generador aleatorio.
## @return valor elegido, o &"" si vacio.
func pick(rng: RandomNumberGenerator) -> StringName:
	if _entries.is_empty() or _total <= 0.0:
		return &""
	var roll: float = rng.randf() * _total
	var acc: float = 0.0
	for entry: Dictionary in _entries:
		acc += float(entry["weight"])
		if roll <= acc:
			return entry["value"] as StringName
	return _entries.back()["value"] as StringName


## Reinicia el picker.
func clear() -> void:
	_entries.clear()
	_total = 0.0
