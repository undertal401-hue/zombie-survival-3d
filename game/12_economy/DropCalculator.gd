class_name DropCalculator

extends RefCounted
## Calcula drops de zombies: monedas base + botin + mejoras permanentes raras.
##
## Centraliza las probabilidades (1-3%) para que todos los tipos de zombie
## compartan exactamente la misma logica.
## Accesible globalmente via `DropCalculator` (class_name).

const BASE_COIN_DROP: int = 5
const RARE_DROP_MIN: float = 0.01
const RARE_DROP_MAX: float = 0.03

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var loot_table: LootTable = null


## Configura el calculador.
## @param p_loot_table: tabla de botin base.
## @param seed_value: semilla opcional (tests).
func configure(p_loot_table: LootTable, seed_value: int = 0) -> void:
	loot_table = p_loot_table
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## Resultado completo del drop de un zombie.
## @param zombie_type: tipo de zombie.
## @param wave_number: oleada (escala monedas).
## @return diccionario {coins, items, rare_upgrade}.
func calculate(zombie_type: StringName, wave_number: int = 1) -> Dictionary:
	var coins: int = int(BASE_COIN_DROP * (1.0 + 0.05 * maxi(wave_number - 1, 0)))
	var items: Array[Dictionary] = []
	if loot_table != null:
		items = loot_table.roll(rng)
	var rare_upgrade: Dictionary = {}
	var roll: float = rng.randf()
	var rare_chance: float = clampf(Config.zombie_rare_drop_chance, RARE_DROP_MIN, RARE_DROP_MAX)
	if roll <= rare_chance:
		rare_upgrade = _roll_rare_upgrade()
	return {"coins": coins, "items": items, "rare_upgrade": rare_upgrade}


## Roll de mejora permanente rara.
func _roll_rare_upgrade() -> Dictionary:
	var kinds: Array[Dictionary] = [
		{"kind": &"damage", "amount": 0.05, "weight": 0.50},
		{"kind": &"speed", "amount": 0.03, "weight": 0.30},
		{"kind": &"jump", "amount": 0.10, "weight": 0.20},
	]
	var picker := WeightedPicker.new()
	for entry: Dictionary in kinds:
		picker.add(entry["kind"], float(entry["weight"]))
	var kind: StringName = picker.pick(rng)
	for entry: Dictionary in kinds:
		if entry["kind"] == kind:
			return entry
	return {}


## Probabilidad de drop raro segun configuracion (telemetria/tests).
static func current_rare_chance() -> float:
	return clampf(Config.zombie_rare_drop_chance, RARE_DROP_MIN, RARE_DROP_MAX)
