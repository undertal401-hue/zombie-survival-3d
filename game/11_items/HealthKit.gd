class_name HealthKit

extends ItemBase
## Botiquin: cura gran cantidad de vida, mas lento y raro.

const ItemBase := preload("res://11_items/ItemBase.gd")
const Player := preload("res://02_player/Player.gd")

@export var heal_amount: float = 60.0

func _init() -> void:
	item_id = &"health_kit"
	display_name = "Botiquin"
	description = "Restaura 60 de vida."
	value = 60

func apply(player: Node3D) -> bool:
	if player == null or not player.has_method("heal"):
		return false
	(player as Player).heal(heal_amount)
	EventBus.item_consumed.emit(self, player)
	EventBus.sfx_2d_requested.emit(&"use_medkit")
	return true

func get_interaction_prompt() -> String:
	return "Usar %s (+%.0f HP)" % [display_name, heal_amount]
