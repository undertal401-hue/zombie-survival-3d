class_name Food

extends ItemBase
## Comida: cura vida y reduce ligeramente la infeccion.

const ItemBase := preload("res://11_items/ItemBase.gd")
const Player := preload("res://02_player/Player.gd")

@export var heal_amount: float = 25.0
@export var infection_reduction: float = 5.0
@export var eating_time: float = 1.2

func _init() -> void:
	item_id = &"food_can"
	display_name = "Lata de comida"
	description = "Restaura 25 de vida y reduce la infeccion."
	value = 20

func apply(player: Node3D) -> bool:
	if player == null or not player.has_method("heal"):
		return false
	(player as Player).heal(heal_amount)
	if infection_reduction > 0.0:
		(player as Player).cure_infection(infection_reduction)
	EventBus.item_consumed.emit(self, player)
	EventBus.sfx_2d_requested.emit(&"eat_food")
	return true

func get_interaction_prompt() -> String:
	return "Comer %s (+%.0f HP)" % [display_name, heal_amount]
