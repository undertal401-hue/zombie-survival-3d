class_name MutatedZombie
extends BaseZombie
## Jefe de la oleada 10: Mutado. Fases por vida, invocacion y gritos.

const BaseZombie := preload("res://03_zombies/BaseZombie.gd")

const PHASE_THRESHOLDS: Array[float] = [0.66, 0.33]
const SPAWN_COUNT: int = 3
const SCREAM_RADIUS: float = 18.0

var _phases_triggered: Array[bool] = [false, false]
var _scream_cooldown: float = 0.0


func _ready() -> void:
	super._ready()
	if stats != null:
		stats.type_name = &"mutated"
		stats.is_boss = true
	add_to_group("bosses")


func _custom_tick(delta: float) -> void:
	if stats == null:
		return
	_scream_cooldown = maxf(_scream_cooldown - delta, 0.0)
	var ratio: float = stats.current_hp / maxf(stats.max_hp, 1.0)
	for i: int in PHASE_THRESHOLDS.size():
		if not _phases_triggered[i] and ratio <= PHASE_THRESHOLDS[i]:
			_phases_triggered[i] = true
			_enter_phase(i + 1)


## Comportamiento por fase: invoca refuerzos y acelera.
func _enter_phase(phase: int) -> void:
	_spawn_minions()
	_scream()
	stats.speed *= 1.12
	EventBus.ui_notification.emit("El Mutado entra en fase %d" % phase, &"warning")


## Invoca walkers alrededor del jefe.
func _spawn_minions() -> void:
	var spawner: ZombieSpawner = get_tree().get_first_node_in_group("zombie_spawner") as ZombieSpawner
	if spawner == null:
		return
	for i: int in SPAWN_COUNT:
		var offset: Vector3 = Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		var zombie: BaseZombie = spawner.pool.acquire(&"walker", 1.0, 1.0, 1.0)
		if zombie == null:
			continue
		get_parent().add_child(zombie)
		zombie.global_position = global_position + offset
		spawner.alive.append(zombie)


## Grito de jefe que aturde brevemente la UI y avisa.
func _scream() -> void:
	EventBus.voice_requested.emit(&"boss_roar", global_position)
	EventBus.zombie_boss_spawned.emit(self)
