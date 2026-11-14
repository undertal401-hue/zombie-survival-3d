class_name CrawlerZombie
extends BaseZombie
## Zombie rastrero: pequenio, rapido y de perfil bajo.
##
## Su hitbox es menor, lo que lo hace mas dificil de alcanzar a distancia.

const BaseZombie := preload("res://03_zombies/BaseZombie.gd")

const CRAWL_SCALE: Vector3 = Vector3(0.85, 0.55, 0.85)


func _ready() -> void:
	super._ready()
	if stats != null and stats.type_name == &"":
		stats.type_name = &"crawler"
	stats.scale = CRAWL_SCALE
	_apply_scale()


func _custom_tick(_delta: float) -> void:
	pass
