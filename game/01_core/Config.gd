class_name GameConfig

extends Resource

## Global accessor for config values.
static var instance: GameConfig = null


func _ready() -> void:
	instance = self
## Configuracion central del juego (data-driven).
##
## Todos los valores de balance viven aqui o en `16_data/*.tres`. Los scripts nunca
## hardcodean stats: los leen de esta recurso o de las tablas de datos.

@export_group("Player")
@export var player_max_hp: float = 100.0
@export var player_hp_regen_rate: float = 2.0
@export var player_hp_regen_delay: float = 5.0
@export var player_stamina_max: float = 100.0
@export var player_stamina_regen: float = 15.0
@export var player_stamina_sprint_drain: float = 12.0
@export var player_dodge_cost: float = 25.0
@export var player_melee_charge_cost: float = 20.0
@export var player_infection_max: float = 100.0
@export var player_move_speed: float = 5.0
@export var player_sprint_speed: float = 8.2
@export var player_crouch_speed: float = 2.4
@export var player_jump_velocity: float = 5.5
@export var player_dodge_speed: float = 12.0
@export var player_dodge_duration: float = 0.28
@export var player_interaction_range: float = 3.0

@export_group("Infection")
@export var infection_cure_amount: float = 25.0
@export var infection_cure_free_per_run: int = 1
@export var infection_damage_ratio: float = 0.6
@export var infection_game_over_at: float = 100.0
@export var infection_decay_out_of_combat: float = 0.0

@export_group("Zombies")
@export var zombie_base_coins: int = 5
@export var zombie_rare_drop_chance: float = 0.02
@export var zombie_very_rare_drop_chance: float = 0.008
@export var zombie_hp_scale_per_wave: float = 0.15
@export var zombie_damage_scale_per_wave: float = 0.10
@export var zombie_speed_scale_per_wave: float = 0.05
@export var zombie_max_alive: int = 80
@export var zombie_despawn_distance: float = 90.0
@export var zombie_attack_range: float = 1.8
@export var zombie_attack_cooldown: float = 1.1

@export_group("Waves")
@export var wave_count: int = 10
@export var wave_shop_duration: float = 480.0
@export var wave_boss_wave: int = 10
@export var wave_base_spawn_count: int = 8
@export var wave_spawn_count_growth: float = 1.35
@export var wave_endless_enabled: bool = true
@export var wave_spawn_interval: float = 0.9
@export var wave_spawn_batch_size: int = 3

@export_group("Economy")
@export var economy_starting_coins: int = 100
@export var economy_ammo_refill_free_per_wave: int = 1
@export var economy_shop_tax_rate: float = 0.0
@export var economy_sell_multiplier: float = 0.5
@export var economy_price_inflation_per_wave: float = 0.02

@export_group("Combat")
@export var combat_headshot_multiplier: float = 2.0
@export var combat_crit_chance: float = 0.05
@export var combat_crit_multiplier: float = 1.75
@export var combat_knockback_base: float = 4.0
@export var combat_blood_decal_pool: int = 256
@export var combat_bullet_pool: int = 512
@export var combat_particle_pool: int = 128

@export_group("Performance")
@export var perf_target_fps: int = 60
@export var perf_lod_distance: float = 10.0
@export var perf_max_draw_calls: int = 4000
@export var perf_cull_distance: float = 70.0
@export var perf_enable_occlusion: bool = true

@export_group("Audio")
@export var audio_master_volume_db: float = 0.0
@export var audio_music_volume_db: float = -6.0
@export var audio_sfx_volume_db: float = -3.0
@export var audio_max_voices: int = 24
@export var audio_spatial_falloff: float = 18.0

@export_group("UI")
@export var ui_notification_duration: float = 2.5
@export var ui_damage_vignette_duration: float = 0.6
@export var ui_crosshair_spread_base: float = 4.0
@export var ui_crosshair_spread_max: float = 40.0


## Carga overrides desde `user://config.json` si existe.
## @return true si se aplico un archivo de override.
func load_overrides() -> bool:
	var path: String = "user://config.json"
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	for key: String in parsed:
		if not key in self:
			continue
		var value: Variant = parsed[key]
		if typeof(value) == typeof(get(key)):
			set(key, value)
	return true


## Restaura los valores por defecto declarados en este recurso.
func reset_to_defaults() -> void:
	# Los valores por defecto ya estan en las propiedades; recargar el recurso
	# base garantiza que no persista basura entre partidas.
	var fresh: GameConfig = load("res://16_data/GameBalance.tres") as GameConfig
	if fresh != null:
		for prop: Dictionary in fresh.get_property_list():
			if prop["name"] in self and not prop["name"].begins_with("_"):
				set(prop["name"], fresh.get(prop["name"]))
