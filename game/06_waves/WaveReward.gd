class_name WaveReward


extends Resource
## Recompensas de fin de oleada (data-driven).
##
## Define monedas base, bonus por tiempo, items garantizados y ventana de
## drop raro. El WaveManager la usa para otorgar recompensas.
## Accesible globalmente via `WaveReward` (class_name).

@export var wave_number: int = 1
@export var base_coins: int = 50
@export var time_bonus_coins: int = 0
@export var guaranteed_items: Array[StringName] = []
@export var rare_drop_chance: float = 0.02
@export var rare_upgrade_table: Array[Dictionary] = []


## Calcula las monedas finales incluyendo bonus por rapidez.
## @param clear_time_ratio: 0..1 (1 = muy rapido).
## @return monedas totales.
func calculate_coins(clear_time_ratio: float = 0.5) -> int:
	var bonus: int = int(time_bonus_coins * clampf(clear_time_ratio, 0.0, 1.0))
	return base_coins + bonus


## Roll de drop raro.
## @return diccionario {kind, amount} o vacio.
func roll_rare() -> Dictionary:
	if randf() > rare_drop_chance:
		return {}
	if rare_upgrade_table.is_empty():
		return {}
	var roll: float = randf()
	var acc: float = 0.0
	for entry: Dictionary in rare_upgrade_table:
		acc += float(entry.get("weight", 0.0))
		if roll <= acc:
			return entry
	return {}


## Genera una recompensa de oleada estandar.
## @param wave_number: oleada.
static func for_wave(wave_number: int) -> WaveReward:
	var reward := WaveReward.new()
	reward.wave_number = wave_number
	reward.base_coins = 40 + wave_number * 10
	reward.rare_drop_chance = 0.02
	reward.rare_upgrade_table = [
		{"kind": &"damage", "amount": 0.05, "weight": 0.5},
		{"kind": &"speed", "amount": 0.03, "weight": 0.3},
		{"kind": &"jump", "amount": 0.10, "weight": 0.2},
	]
	return reward
