class_name CoinPickup

extends ItemBase
## Moneda recogible: suma saldo al jugador.

const ItemBase := preload("res://11_items/ItemBase.gd")
const Currency := preload("res://12_economy/Currency.gd")

@export var coin_amount: int = 5

func _init() -> void:
	item_id = &"coin"
	display_name = "Moneda"
	value = 1

func apply(player: Node3D) -> bool:
	if player == null:
		return false
	Currency.add(coin_amount, &"pickup")
	EventBus.item_picked.emit(self, player)
	EventBus.sfx_2d_requested.emit(&"pickup_coin")
	return true

func get_interaction_prompt() -> String:
	return "Recoger %d monedas" % coin_amount
