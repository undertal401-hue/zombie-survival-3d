class_name Potion

extends ItemBase
## Pocion: cura infeccion o vida, con variantes por color.

const ItemBase := preload("res://11_items/ItemBase.gd")
const Player := preload("res://02_player/Player.gd")

enum PotionKind {
	NONE,
	HEALTH,
	ANTIDOTE,
	STAMINA,
	ADRENALINE,
}

@export var kind: PotionKind = PotionKind.HEALTH
@export var power: float = 30.0
@export var duration: float = 0.0

func _init() -> void:
	item_id = &"potion_health"
	display_name = "Pocion"
	value = 35

func _ready() -> void:
	super._ready()
	match kind:
		PotionKind.HEALTH:
			item_id = &"potion_health"
			display_name = "Pocion de vida"
		PotionKind.ANTIDOTE:
			item_id = &"potion_antidote"
			display_name = "Antidoto"
		PotionKind.STAMINA:
			item_id = &"potion_stamina"
			display_name = "Pocion de vigor"
		PotionKind.ADRENALINE:
			item_id = &"potion_adrenaline"
			display_name = "Adrenalina"

func apply(player: Node3D) -> bool:
	if player == null or not player.has_method("heal"):
		return false
	var target := player as Player
	match kind:
		PotionKind.HEALTH:
			target.heal(power)
		PotionKind.ANTIDOTE:
			target.cure_infection(power)
		PotionKind.STAMINA:
			target.stats.stamina = minf(target.stats.stamina + power, target.stats.max_stamina)
		PotionKind.ADRENALINE:
			target.stats.apply_permanent_upgrade(&"speed", 0.05)
		_:
			return false
	EventBus.item_consumed.emit(self, player)
	EventBus.sfx_2d_requested.emit(&"drink_potion")
	return true

func get_interaction_prompt() -> String:
	match kind:
		PotionKind.ANTIDOTE:
			return "Beber %s (-%.0f%% infeccion)" % [display_name, power]
		PotionKind.HEALTH:
			return "Beber %s (+%.0f HP)" % [display_name, power]
	return "Beber %s" % display_name
