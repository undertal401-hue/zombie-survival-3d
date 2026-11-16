class_name LootContainer
extends Area2D

@export var item_id: String = ""
@export var amount: int = 0
@export var container_name: String = "armario"

@onready var body_visual: Polygon2D = $Body
@onready var lid: Polygon2D = $Lid
@onready var marker: Label = $Marker

var _player_inside: Node2D
var _looted: bool = false

func _ready() -> void:
	add_to_group("loot")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_marker()

func _unhandled_input(event: InputEvent) -> void:
	if _looted or _player_inside == null:
		return
	if event.is_action_pressed("interact"):
		loot()
		get_viewport().set_input_as_handled()

func loot() -> void:
	if _looted:
		return
	_looted = true
	if item_id != "" and amount > 0:
		Inventory.add_item(item_id, amount)
		EventBus.notification.emit("+%d %s" % [amount, Inventory.display_name(item_id)])
	else:
		EventBus.notification.emit("No hay nada útil aquí")
	EventBus.interaction_cleared.emit()
	marker.visible = false
	lid.color = Color(0.25, 0.25, 0.25)
	body_visual.color = Color(0.3, 0.28, 0.25)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = body
	if not _looted:
		EventBus.interaction_prompt.emit("E  Saquear %s" % container_name)

func _on_body_exited(body: Node2D) -> void:
	if body != _player_inside:
		return
	_player_inside = null
	EventBus.interaction_cleared.emit()

func _update_marker() -> void:
	marker.visible = not _looted
	if item_id == "combustible":
		marker.text = "!"
		marker.modulate = Color(1.0, 0.8, 0.25)
		lid.color = Color(0.72, 0.5, 0.2)
	elif item_id == "medkit":
		marker.text = "+"
		marker.modulate = Color(0.5, 1.0, 0.6)
		lid.color = Color(0.35, 0.65, 0.4)
	else:
		marker.text = "?"
		marker.modulate = Color(0.7, 0.7, 0.7)
