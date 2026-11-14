class_name WaveScaling


extends Resource


## Instancia global unica.
static var instance: WaveScaling = null


func _ready() -> void:
	instance = self
## Curvas de escalado por oleada.
##
## Fuente unica de verdad para HP, dano, velocidad y numero de enemigos.
## Los valores por defecto cumplen: +15% HP, +10% dano, +5% velocidad.

@export_group("Progression")
@export var base_count: int = 8
@export var count_growth: float = 1.35
@export var base_interval: float = 0.9
@export var boss_every: int = 10

@export_group("HP")
@export var base_hp: float = 60.0
@export var hp_scale_per_wave: float = 0.15
@export var hp_growth_exponent: float = 1.0

@export_group("Damage")
@export var base_damage: float = 10.0
@export var damage_scale_per_wave: float = 0.10

@export_group("Speed")
@export var base_speed: float = 2.2
@export var speed_scale_per_wave: float = 0.05
@export var max_speed_multiplier: float = 2.5

@export_group("Rewards")
@export var base_reward: int = 50
@export var coin_scale_per_wave: float = 0.10
@export var rare_drop_chance: float = 0.02


## Multiplicador de HP para una oleada.
## @param wave_number: 1-indexado.
func hp_multiplier(wave_number: int) -> float:
	return 1.0 + hp_scale_per_wave * float(maxi(wave_number - 1, 0))


## Multiplicador de dano para una oleada.
func damage_multiplier(wave_number: int) -> float:
	return 1.0 + damage_scale_per_wave * float(maxi(wave_number - 1, 0))


## Multiplicador de velocidad (limitado).
func speed_multiplier(wave_number: int) -> float:
	var value: float = 1.0 + speed_scale_per_wave * float(maxi(wave_number - 1, 0))
	return minf(value, max_speed_multiplier)


## HP absoluto para una oleada.
func hp_for_wave(wave_number: int, base: float) -> float:
	return base * pow(hp_multiplier(wave_number), hp_growth_exponent)


## Dano absoluto para una oleada.
func damage_for_wave(wave_number: int, base: float) -> float:
	return base * damage_multiplier(wave_number)


## Velocidad absoluta para una oleada.
func speed_for_wave(wave_number: int, base: float) -> float:
	return base * speed_multiplier(wave_number)


## Recompensa de monedas de una oleada.
func reward_for_wave(wave_number: int) -> int:
	return int(base_reward * (1.0 + coin_scale_per_wave * float(maxi(wave_number - 1, 0))))


## Numero de enemigos de una oleada.
func count_for_wave(wave_number: int) -> int:
	return int(base_count * pow(count_growth, float(maxi(wave_number - 1, 0))))


## Volca todas las stats de una oleada a un diccionario (telemetria/tests).
func snapshot(wave_number: int) -> Dictionary:
	return {
		"wave": wave_number,
		"count": count_for_wave(wave_number),
		"hp_mult": hp_multiplier(wave_number),
		"damage_mult": damage_multiplier(wave_number),
		"speed_mult": speed_multiplier(wave_number),
		"reward": reward_for_wave(wave_number),
		"is_boss": wave_number % boss_every == 0,
	}
