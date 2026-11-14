class_name ScreamerZombie
extends BaseZombie
## Zombie griton: periódicamente grita y acelera a los zombies cercanos.

const BaseZombie := preload("res://03_zombies/BaseZombie.gd")

const SCREAM_INTERVAL: float = 6.0
const SCREAM_RADIUS: float = 12.0
const SPEED_BUFF: float = 1.35
const BUFF_DURATION: float = 3.0

var _scream_timer: float = 2.0


func _ready() -> void:
	super._ready()
	if stats != null and stats.type_name == &"":
		stats.type_name = &"screamer"


func _custom_tick(delta: float) -> void:
	_scream_timer -= delta
	if _scream_timer > 0.0:
		return
	_scream_timer = SCREAM_INTERVAL
	_scream()


## Grita: buff de velocidad a zombies cercanos y aviso a la UI.
func _scream() -> void:
	EventBus.voice_requested.emit(&"zombie_scream", global_position)
	EventBus.zombie_horde_warn.emit(8)
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		var other := node as BaseZombie
		if other == null or other == self:
			continue
		if global_position.distance_to(other.global_position) <= SCREAM_RADIUS:
			other.apply_temporary_speed(SPEED_BUFF, BUFF_DURATION)


## Buff de velocidad temporal (usado por ScreamerZombie).
func apply_temporary_speed(multiplier: float, duration: float) -> void:
	if stats == null or multiplier <= 1.0:
		return
	stats.speed *= multiplier
	get_tree().create_timer(duration).timeout.connect(func() -> void: stats.speed /= multiplier)
