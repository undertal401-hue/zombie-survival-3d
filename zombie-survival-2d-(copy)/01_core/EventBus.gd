extends Node

signal player_damaged(amount: float, source: Node)
signal player_health_changed(hp: float, max_hp: float)
signal player_stamina_changed(stamina: float, max_stamina: float)
signal player_hunger_changed(hunger: float, max_hunger: float, warning_threshold: float)
## R1-fix: el payload NO se tipa. Con `zombie: Node2D`, una instancia ya
## liberada hace que el motor rechace la llamada a cualquier receptor tipado
## ("Cannot convert argument 1 from Object to Object") y el error nombra el
## fichero del receptor (el usuario reporto el error en "Zombies.gd"). Sin
## tipo, el payload llega a los receptores y cada uno valida su vigencia.
## Coherente con `zombie_alerted(zombie, source)` y `game_state_changed(phase)`.
signal zombie_died(zombie)
signal wave_started(wave: int)
signal interaction_prompt(text: String)
signal interaction_cleared
signal notification(text: String)
signal victory
signal game_over
signal forest_entered
signal forest_exited

# Señales nuevas del estado central y de los subsistemas. Se dejan sin tipos
# para que cualquier nodo pueda emitirlas sin fricción (fase, kind e item_id
# pueden viajar como String o StringName según el productor).
signal game_state_changed(phase)
signal difficulty_changed(level)
signal horde_started(wave)
signal weather_changed(kind)
signal craft_completed(item_id, amount)
signal vehicle_state_changed(vehicle, fuel, hp)
signal zombie_alerted(zombie, source)
# Avisos prioritarios del director de mundo (hordas, tormentas): el HUD los
# muestra por encima de los mensajes normales sin cambiar textos del contrato.
signal priority_notification(text)
