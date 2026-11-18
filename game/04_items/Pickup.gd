extends Area2D

@export var item_id: String = "llave"
@export var amount: int = 1

func _ready() -> void:
	add_to_group("pickups")
	var visual := get_node_or_null("Visual") as Polygon2D
	if visual == null:
		return
	match item_id:
		"medkit": visual.color = Color(0.4, 0.9, 0.6)
		"combustible", "vehicle_fuel": visual.color = Color(0.95, 0.7, 0.2)
		"scrap": visual.color = Color(0.7, 0.72, 0.75)
		"cloth": visual.color = Color(0.85, 0.82, 0.7)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	# add_item notifica el motivo exacto (pila llena / sobrecarga) y no se
	# destruye la pickup si no cupo: el jugador puede volver a por ella.
	if Inventory.add_item(item_id, amount) > 0:
		queue_free()
