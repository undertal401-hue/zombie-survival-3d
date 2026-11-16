extends Area2D

@export var item_id: String = "llave"
@export var amount: int = 1

func _ready() -> void:
	add_to_group("pickups")
	var visual := get_node_or_null("Visual") as Polygon2D
	if visual == null:
		return
	if item_id == "medkit":
		visual.color = Color(0.4, 0.9, 0.6)
	elif item_id == "combustible":
		visual.color = Color(0.95, 0.7, 0.2)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		Inventory.add_item(item_id, amount)
		queue_free()
