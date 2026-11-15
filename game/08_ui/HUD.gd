extends CanvasLayer

@onready var label: Label = $Label

func _process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player")
	var hp: float = p.hp if p != null else 0.0
	label.text = "HP: %d  |  Items: %d" % [int(hp), Inventory.total()]
