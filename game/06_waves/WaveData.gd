class_name WaveData

extends Resource
## Definicion de una oleada (data-driven).
##
## Se instancia desde `16_data/WaveScaling.tres` y los .tres de oleada.
## El WaveManager la consume; nunca se hardcodea composicion.

@export var wave_number: int = 1
@export var display_name: String = "Oleada"
@export var spawn_count: int = 8
@export var spawn_interval: float = 0.9
@export var spawn_batch_size: int = 3
@export var is_boss: bool = false
@export var reward_coins: int = 50
@export var reward_items: Array[StringName] = []
@export var composition: Array[Dictionary] = []
@export var ambient_music: StringName = &"wave_ambient"
@export var intro_message: String = ""


## Anade una entrada de composicion con validez basica.
## @param zombie_type: tipo de zombie (debe existir en ZombieTypes).
## @param weight: peso relativo de aparicion.
func add_type(zombie_type: StringName, weight: float) -> void:
	composition.append({"type": zombie_type, "weight": maxf(weight, 0.0)})


## Peso total de la composicion (para normalizar).
func total_weight() -> float:
	var total: float = 0.0
	for entry: Dictionary in composition:
		total += float(entry.get("weight", 0.0))
	return total


## Crea una oleada procedural basada en escalado (para endless).
## @param wave_number: numero de oleada.
## @param scaling: recurso de escalado.
static func generate(wave_number: int, scaling: WaveScaling) -> WaveData:
	var data := WaveData.new()
	data.wave_number = wave_number
	data.display_name = "Oleada %d" % wave_number
	data.spawn_count = int(scaling.base_count * pow(scaling.count_growth, wave_number - 1))
	data.spawn_interval = maxf(scaling.base_interval - wave_number * 0.05, 0.25)
	data.is_boss = wave_number % scaling.boss_every == 0
	data.reward_coins = int(scaling.base_reward * (1.0 + 0.1 * wave_number))
	data.add_type(&"walker", 10.0)
	if wave_number >= 2:
		data.add_type(&"runner", 6.0 + wave_number * 0.4)
	if wave_number >= 3:
		data.add_type(&"crawler", 5.0)
	if wave_number >= 4:
		data.add_type(&"spitter", 4.0)
	if wave_number >= 5:
		data.add_type(&"screamer", 3.0)
	if wave_number >= 6:
		data.add_type(&"tank", 2.5)
	if wave_number >= 8:
		data.add_type(&"brute", 2.0)
	if data.is_boss:
		data.add_type(&"mutated", 1.0)
	return data
