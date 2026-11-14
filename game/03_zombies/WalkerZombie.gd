class_name WalkerZombie
extends BaseZombie
## Zombie basico: camina hacia el jugador y ataca cuerpo a cuerpo.
##
## Es el tipo por defecto y el mas numeroso. Stats base en ZombieStats.

const BaseZombie := preload("res://03_zombies/BaseZombie.gd")

const STEP_INTERVAL: float = 0.9

var _step_timer: float = 0.0


func _ready() -> void:
	super._ready()
	if stats == null:
		stats = ZombieStats.new()
	if stats.type_name == &"":
		stats.type_name = &"walker"


func _custom_tick(delta: float) -> void:
	_step_timer -= delta
	if _step_timer <= 0.0 and ai != null and ai.target != null:
		_step_timer = STEP_INTERVAL
		EventBus.footstep_requested.emit(&"flesh", global_position)
