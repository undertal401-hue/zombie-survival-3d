class_name Cheats

extends RefCounted
## Trucos centralizados (solo builds debug).
##
## Accedidos via DebugConsole; no hay hotkeys directos.
## Accesible globalmente via `Cheats` (class_name).

static var enabled: bool = false
static var god_mode: bool = false
static var infinite_ammo: bool = false
static var infinite_stamina: bool = false
static var no_reload: bool = false
static var one_shot_kill: bool = false
static var no_infection: bool = false
static var super_speed: bool = false
static var super_jump: bool = false


## Alterna todos los trucos.
static func toggle_all() -> void:
	enabled = not enabled
	god_mode = enabled
	infinite_ammo = enabled
	infinite_stamina = enabled
	no_reload = enabled
	one_shot_kill = enabled
	no_infection = enabled


## Aplica los trucos activos al jugador.
## @param player: jugador objetivo.
static func apply_to(player: Player) -> void:
	if not enabled:
		return
	if player == null:
		return
	if god_mode:
		player.stats.hp = player.stats.max_hp
		player.stats.infection = 0.0
	if infinite_stamina:
		player.stats.stamina = player.stats.max_stamina
	if super_speed:
		player.stats.move_speed *= 3.0
		player.stats.sprint_speed *= 3.0
	if super_jump:
		player.stats.jump_velocity *= 2.5


## True si algun truco afecta al dano.
static func modifies_damage() -> bool:
	return one_shot_kill


## Multiplicador de dano por trucos.
static func damage_multiplier() -> float:
	return 999.0 if one_shot_kill else 1.0


## True si la recarga se salta.
static func skips_reload() -> bool:
	return no_reload or infinite_ammo


## True si la infeccion se ignora.
static func ignores_infection() -> bool:
	return no_infection
