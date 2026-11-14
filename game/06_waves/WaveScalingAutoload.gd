extends Node
## Wrapper autoload para WaveScaling.

var scaling

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var WaveScaling = load("res://06_waves/WaveScaling.gd")
	scaling = WaveScaling.new()
	# Valores por defecto
	scaling.base_count = 8
	scaling.count_growth = 1.35
	scaling.base_interval = 0.9
	scaling.boss_every = 10
	scaling.base_hp = 60.0
	scaling.hp_scale_per_wave = 0.15
	scaling.hp_growth_exponent = 1.0
	scaling.base_damage = 10.0
	scaling.damage_scale_per_wave = 0.10
	scaling.base_speed = 2.2
	scaling.speed_scale_per_wave = 0.05
	scaling.max_speed_multiplier = 2.5
	scaling.base_reward = 50
	scaling.coin_scale_per_wave = 0.10
	scaling.rare_drop_chance = 0.02

func hp_multiplier(wave_number: int) -> float:
	return scaling.hp_multiplier(wave_number)

func damage_multiplier(wave_number: int) -> float:
	return scaling.damage_multiplier(wave_number)

func speed_multiplier(wave_number: int) -> float:
	return scaling.speed_multiplier(wave_number)

func hp_for_wave(wave_number: int, base: float) -> float:
	return scaling.hp_for_wave(wave_number, base)

func damage_for_wave(wave_number: int, base: float) -> float:
	return scaling.damage_for_wave(wave_number, base)

func speed_for_wave(wave_number: int, base: float) -> float:
	return scaling.speed_for_wave(wave_number, base)

func reward_for_wave(wave_number: int) -> int:
	return scaling.reward_for_wave(wave_number)

func count_for_wave(wave_number: int) -> int:
	return scaling.count_for_wave(wave_number)

func snapshot(wave_number: int) -> Dictionary:
	return scaling.snapshot(wave_number)