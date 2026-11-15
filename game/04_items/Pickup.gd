extends Area2D

@export var item_id: String = "llave"
@export var amount: int = 1

func _ready() -> void:
	add_to_group("pickups")

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		Inventory.add_item(item_id, amount)
		queue_free()
