extends Node
## Autoload global de eventos (EventBus).
##
## Todas las comunicaciones entre sistemas pasan por aqui. Ningun sistema
## guarda una referencia directa a otro; publica un evento y los interesados
## reaccionan. Esto mantiene el desacoplamiento (arquitectura ECS-lite).
##
## Uso:
##   EventBus.zombie_died.connect(_on_zombie_died)
##   EventBus.player_damaged.emit(12.0, self)

# --- Player ---------------------------------------------------------------
signal player_spawned(player: Node3D)
signal player_died(player: Node3D)
signal player_health_changed(current: float, maximum: float)
signal player_stamina_changed(current: float, maximum: float)
signal player_infection_changed(current: float, maximum: float)
signal player_damaged(amount: float, source: Node3D)
signal player_healed(amount: float, source: Node3D)
signal player_infected(amount: float, source: Node3D)
signal player_dodge_started(duration: float)
signal player_died_final

# --- Zombies --------------------------------------------------------------
signal zombie_spawned(zombie: Node3D)
signal zombie_died(zombie: Node3D, killer: Node3D, reward: int)
signal zombie_hit(zombie: Node3D, damage_info: Resource)
signal zombie_boss_spawned(zombie: Node3D)
signal zombie_horde_warn(count: int)

# --- Weapons --------------------------------------------------------------
signal weapon_equipped(weapon: Node3D)
signal weapon_unequipped(weapon: Node3D)
signal weapon_fired(weapon: Node3D, origin: Vector3, direction: Vector3)
signal weapon_trigger_pulled(weapon: Node3D)
signal weapon_trigger_released(weapon: Node3D)
signal weapon_reload_started(weapon: Node3D, duration: float)
signal weapon_reload_finished(weapon: Node3D)
signal weapon_empty_clicked(weapon: Node3D)
signal ammo_changed(weapon: Node3D, magazine: int, reserve: int)
signal melee_swing_started(weapon: Node3D)
signal melee_hit_registered(weapon: Node3D, hits: int)

# --- Combat ---------------------------------------------------------------
signal damage_dealt(damage_info: Resource)
signal damage_blocked(damage_info: Resource)
signal hit_registered(damage_info: Resource)
signal knockback_applied(target: Node3D, impulse: Vector3)
signal explosion_triggered(origin: Vector3, radius: float, damage: float)
signal critical_hit(damage_info: Resource)

# --- Waves ----------------------------------------------------------------
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int, stats: Dictionary)
signal wave_failed(wave_number: int)
signal wave_timer_updated(remaining: float, total: float)
signal wave_spawn_batch(count: int, zombie_type: StringName)
signal shop_phase_started(wave_number: int)
signal shop_phase_ended(wave_number: int)
signal shop_phase_cancelled
signal boss_wave_started(wave_number: int)
signal wave_intermission_ready

# --- Economy / Items ------------------------------------------------------
signal currency_changed(balance: int, delta: int)
signal currency_spent(amount: int, item_id: StringName)
signal item_dropped(item: Node3D)
signal item_picked(item: Node3D, by_player: Node3D)
signal item_consumed(item: Node3D, by_player: Node3D)
signal shop_purchased(item_id: StringName, cost: int)
signal shop_refused(item_id: StringName, reason: StringName)
signal rare_drop_acquired(upgrade: Resource)
signal loot_table_rolled(result: Dictionary)

# --- Safe zone ------------------------------------------------------------
signal safe_zone_entered(zone: Node3D)
signal safe_zone_exited(zone: Node3D)
signal infection_cured(amount: float)
signal ammo_refilled(magazine: int, reserve: int, free: bool)

# --- Audio ----------------------------------------------------------------
signal sfx_requested(cue_id: StringName, world_position: Vector3)
signal sfx_2d_requested(cue_id: StringName)
signal music_requested(track_id: StringName, fade: float)
signal music_stopped(fade: float)
signal footstep_requested(surface: StringName, world_position: Vector3)
signal voice_requested(cue_id: StringName, world_position: Vector3)

# --- Game flow ------------------------------------------------------------
signal game_state_changed(previous: int, current: int)
signal game_started
signal game_over(reason: StringName)
signal game_victory
signal run_completed
signal checkpoint_reached(checkpoint_id: StringName)
signal checkpoint_loaded(checkpoint_id: StringName)
signal pause_requested
signal resume_requested
signal ui_notification(text: String, tone: StringName)
signal scene_change_requested(scene_path: String, transition: StringName)
signal save_loaded(slot: int)
signal save_written(slot: int)
signal settings_changed(section: StringName)
signal achievement_unlocked(achievement_id: StringName)
signal debug_command_executed(command: String, args: PackedStringArray)


## Devuelve el numero de suscriptores de una senal (util para debug/telemetria).
## @param signal_name: nombre de la senal declarada en este autoload.
## @return Cantidad de conexiones activas, o -1 si la senal no existe.
func subscriber_count(signal_name: StringName) -> int:
	if not has_signal(signal_name):
		return -1
	var total: int = 0
	for info: Dictionary in get_signal_connection_list(signal_name):
		total += 1
	return total


## Emite una notificacion de UI de forma centralizada.
## @param text: mensaje a mostrar.
## @param tone: "info" | "warning" | "error" | "reward".
func notify(text: String, tone: StringName = &"info") -> void:
	ui_notification.emit(text, tone)
