class_name EconomyConfig

extends Resource
## Configuracion de economia (data-driven, override de GameConfig).

@export_group("Starting")
@export var starting_coins: int = 100
@export var max_coins: int = 999999

@export_group("Inflation")
@export var price_inflation_per_wave: float = 0.02
@export var sell_multiplier: float = 0.5
@export var shop_tax_rate: float = 0.0

@export_group("Waves")
@export var wave_reward_base: int = 50
@export var wave_reward_growth: float = 0.10
@export var ammo_refill_free_per_wave: int = 1

@export_group("Drops")
@export var rare_drop_chance: float = 0.02
@export var very_rare_drop_chance: float = 0.008
@export var base_coins_per_kill: int = 5


## Aplica estos valores al GameConfig global.
## @param cfg: GameConfig destino.
func apply_to(cfg: GameConfig) -> void:
	cfg.economy_starting_coins = starting_coins
	cfg.economy_price_inflation_per_wave = price_inflation_per_wave
	cfg.economy_sell_multiplier = sell_multiplier
	cfg.economy_shop_tax_rate = shop_tax_rate
	cfg.economy_ammo_refill_free_per_wave = ammo_refill_free_per_wave
	cfg.zombie_base_coins = base_coins_per_kill
	cfg.zombie_rare_drop_chance = rare_drop_chance
