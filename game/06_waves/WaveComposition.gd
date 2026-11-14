class_name WaveComposition

extends RefCounted


## Instancia global unica.
static var instance: WaveComposition = null


func _ready() -> void:
	instance = self
## Construye la lista de apariciones de una oleada a partir de pesos.
##
## Determinista si se fija la semilla (tests). Usa WeightedRandomPicker.

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Crea la lista de tipos de zombie de una oleada.
## @param data: WaveData con composicion.
## @return Array[StringName] con `spawn_count` entradas.
func build(data: WaveData) -> Array[StringName]:
	var result: Array[StringName] = []
	var entries: Array[Dictionary] = data.composition
	if entries.is_empty() or data.spawn_count <= 0:
		return result
	var picker := WeightedPicker.new()
	for entry: Dictionary in entries:
		var type_name: StringName = entry.get("type", &"walker")
		var weight: float = float(entry.get("weight", 0.0))
		if weight > 0.0:
			picker.add(type_name, weight)
	for i: int in data.spawn_count:
		result.append(picker.pick(rng))
	return result


## Fija la semilla para reproducibilidad.
## @param seed_value: semilla.
func set_seed(seed_value: int) -> void:
	rng.seed = seed_value
