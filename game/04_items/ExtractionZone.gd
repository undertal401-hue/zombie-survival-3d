class_name ExtractionZone
extends Area2D

const REQUIRED_FUEL := 3
const RADIUS := 72.0

@onready var title: Label = $Title

var _player_inside: Node2D
var _won: bool = false

func _ready() -> void:
	add_to_group("extraction")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	Inventory.inventory_changed.connect(_on_inventory_changed)
	_update_title()

func can_extract() -> bool:
	return Inventory.count("combustible") >= REQUIRED_FUEL

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = body
	_try_extract()

func _on_body_exited(body: Node2D) -> void:
	if body == _player_inside:
		_player_inside = null

func _on_inventory_changed() -> void:
	_update_title()
	if _player_inside != null:
		_try_extract()

func _try_extract() -> void:
	if _won:
		return
	if not can_extract():
		var missing: int = REQUIRED_FUEL - Inventory.count("combustible")
		EventBus.notification.emit("Faltan %d bidones de combustible" % missing)
		return
	_won = true
	EventBus.victory.emit()

func _update_title() -> void:
	if can_extract():
		title.text = "EXTRACCIÓN LISTA"
		title.modulate = Color(0.55, 1.0, 0.55)
	else:
		title.text = "EXTRACCIÓN · 3 BIDONES"
		title.modulate = Color(0.8, 1.0, 0.8)

func _draw() -> void:
	var fill := Color(0.2, 0.9, 0.4, 0.12)
	var line := Color(0.35, 1.0, 0.55, 0.9)
	draw_circle(Vector2.ZERO, RADIUS, fill)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, line, 3.0, true)
	draw_arc(Vector2.ZERO, RADIUS - 10.0, 0.0, TAU, 48, Color(0.35, 1.0, 0.55, 0.25), 8.0, true)
	draw_line(Vector2(-8.0, -12.0), Vector2(-8.0, 12.0), line, 4.0)
	draw_line(Vector2(8.0, -12.0), Vector2(8.0, 12.0), line, 4.0)
	draw_line(Vector2(-8.0, 0.0), Vector2(8.0, 0.0), line, 4.0)
