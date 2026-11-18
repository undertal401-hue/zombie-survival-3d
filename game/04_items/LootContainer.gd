class_name LootContainer
extends Area2D

@export var item_id: String = ""
@export var amount: int = 0
@export var container_name: String = "armario"
## Contenedores sin objeto asignado se resuelven con tablas por rareza.
## `combustible` nunca se genera aquí: QA espera 9 bidones del mundo en 8 sectores.
@export var rarity: String = "common"
@export var loot_drops: int = 1

@onready var body_visual: Polygon2D = $Body
@onready var lid: Polygon2D = $Lid
@onready var marker: Label = $Marker

var _player_inside: Node2D
var _looted: bool = false
var _pending_drops: Array = []

func _ready() -> void:
	add_to_group("loot")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if item_id != "" and amount > 0:
		_pending_drops = [{"id": item_id, "amount": amount}]
	else:
		_pending_drops = Inventory.roll_loot(rarity, loot_drops)
		# Exponer el resultado para HUD/minimapa y para QA.
		if not _pending_drops.is_empty():
			item_id = String(_pending_drops[0].get("id", ""))
			amount = int(_pending_drops[0].get("amount", 0))
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
	if _pending_drops.is_empty():
		EventBus.notification.emit("No hay nada útil aquí")
		return
	var gained: int = 0
	for drop in _pending_drops:
		var id: String = String(drop.get("id", ""))
		var qty: int = int(drop.get("amount", 0))
		if id == "" or qty <= 0:
			continue
		# add_item avisa por EventBus.notification si la pila o el peso rechazan
		# el objeto: el contenedor sigue disponible para volver a intentarlo.
		gained += Inventory.add_item(id, qty)
	if gained <= 0:
		return
	_looted = true
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
	match item_id:
		"combustible":
			# Solo contenedores colocados por el mundo; el botín nunca lo genera.
			marker.text = "!"
			marker.modulate = Color(1.0, 0.8, 0.25)
			lid.color = Color(0.72, 0.5, 0.2)
		"vehicle_fuel":
			marker.text = "V"
			marker.modulate = Color(1.0, 0.75, 0.3)
			lid.color = Color(0.6, 0.45, 0.2)
		"medkit":
			marker.text = "+"
			marker.modulate = Color(0.5, 1.0, 0.6)
			lid.color = Color(0.35, 0.65, 0.4)
		"comida":
			marker.text = "C"
			marker.modulate = Color(1.0, 0.75, 0.35)
			lid.color = Color(0.7, 0.48, 0.18)
		"scrap", "cloth":
			marker.text = "M"
			marker.modulate = Color(0.75, 0.78, 0.8)
			lid.color = Color(0.36, 0.38, 0.38)
		_:
			marker.text = "?"
			marker.modulate = Color(0.7, 0.7, 0.7)
