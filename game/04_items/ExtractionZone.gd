class_name ExtractionZone
extends Area2D

const RADIUS := 72.0

@onready var title: Label = $Title

var _player_inside: Node2D = null

func _ready() -> void:
	add_to_group("extraction")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_title()

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = body
	EventBus.notification.emit("Zona de extracción (no operativa)")

func _on_body_exited(body: Node2D) -> void:
	if body == _player_inside:
		_player_inside = null

func _update_title() -> void:
	title.text = "ZONA DE EXTRACCIÓN"
	title.modulate = Color(0.7, 0.9, 1.0)

func _draw() -> void:
	var fill := Color(0.2, 0.5, 0.9, 0.1)
	var line := Color(0.35, 0.7, 1.0, 0.9)
	draw_circle(Vector2.ZERO, RADIUS, fill)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, line, 3.0, true)
	draw_arc(Vector2.ZERO, RADIUS - 10.0, 0.0, TAU, 48, Color(0.35, 0.7, 1.0, 0.2), 8.0, true)
