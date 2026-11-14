extends Node
## Wrapper autoload para WaveData generation.

func generate(wave_number: int, scaling) -> Object:
	var WaveData = load("res://06_waves/WaveData.gd")
	var data = WaveData.new()
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
