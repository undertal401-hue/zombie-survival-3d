class_name Progress

extends Resource
## Progreso global persistente entre partidas (logros, stats historicos).
## Accesible globalmente via `Progress` (class_name).

@export var total_kills: int = 0
@export var total_waves_cleared: int = 0
@export var total_playtime: float = 0.0
@export var highest_wave: int = 0
@export var total_coins_earned: int = 0
@export var permanent_upgrades_owned: Array[Dictionary] = []
@export var achievements: Dictionary = {}


## Incrementa contadores al morir/completar.
func record_run(kills: int, waves: int, playtime: float, coins: int) -> void:
	total_kills += kills
	total_waves_cleared += waves
	total_playtime += playtime
	total_coins_earned += coins
	highest_wave = maxi(highest_wave, waves)


## Desbloquea un logro.
func unlock_achievement(achievement_id: StringName) -> void:
	if achievements.has(achievement_id):
		return
	achievements[achievement_id] = Time.get_unix_time_from_system()
	EventBus.achievement_unlocked.emit(achievement_id)


## Serializa para guardado.
func to_dict() -> Dictionary:
	return {
		"total_kills": total_kills,
		"total_waves_cleared": total_waves_cleared,
		"total_playtime": total_playtime,
		"highest_wave": highest_wave,
		"total_coins_earned": total_coins_earned,
		"permanent_upgrades_owned": permanent_upgrades_owned,
		"achievements": achievements,
	}


## Restaura desde guardado.
func from_dict(data: Dictionary) -> void:
	total_kills = int(data.get("total_kills", 0))
	total_waves_cleared = int(data.get("total_waves_cleared", 0))
	total_playtime = float(data.get("total_playtime", 0.0))
	highest_wave = int(data.get("highest_wave", 0))
	total_coins_earned = int(data.get("total_coins_earned", 0))
	permanent_upgrades_owned = data.get("permanent_upgrades_owned", [])
	achievements = data.get("achievements", {})
