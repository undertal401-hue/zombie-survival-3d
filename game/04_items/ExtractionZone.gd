class_name ExtractionZone
extends Area2D

const RADIUS := 72.0
const REQUIRED_FUEL := 3

@onready var title: Label = $Title

var _player_inside: Node2D = null
var _victory_triggered: bool = false

func _ready() -> void:
	add_to_group("extraction")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Si el jugador consigue el tercer bidón mientras ya está dentro del círculo
	# (recompensa de misión o loot cercano), body_entered no volverá a dispararse.
	Inventory.inventory_changed.connect(_on_inventory_changed)
	_update_title()

func _on_inventory_changed() -> void:
	if _player_inside != null and is_instance_valid(_player_inside):
		_check_extraction(_player_inside)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = body
	_check_extraction(body)

func _on_body_exited(body: Node2D) -> void:
	if body == _player_inside:
		_player_inside = null

func _check_extraction(player: Node2D) -> void:
	if _victory_triggered:
		return
	
	# `combustible` es el bidón del objetivo (QA); `vehicle_fuel` es el id
	# fabricable. Ambos sirven para extraer, pero no se duplica su cuenta.
	var fuel: int = Inventory.count("combustible") + Inventory.count("vehicle_fuel")
	if fuel >= REQUIRED_FUEL:
		_victory_triggered = true
		EventBus.victory.emit()
		EventBus.notification.emit("¡EXTRACTION EXITOSA! Has sobrevivido.")
		call_deferred("_show_victory")
	else:
		var needed: int = REQUIRED_FUEL - fuel
		EventBus.notification.emit("Faltan %d bidones de combustible para extraer." % needed)

func _show_victory() -> void:
	var hud := get_tree().get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("_on_victory"):
		hud.call("_on_victory")
	else:
		# Fallback: pause and show generic victory
		get_tree().paused = true
		EventBus.notification.emit("¡VICTORIA! R para reiniciar.")

func _update_title() -> void:
	title.text = "ZONA DE EXTRACCIÓN"
	title.modulate = Color(0.7, 0.9, 1.0)

func _draw() -> void:
	var fill := Color(0.2, 0.5, 0.9, 0.1)
	var line := Color(0.35, 0.7, 1.0, 0.9)
	draw_circle(Vector2.ZERO, RADIUS, fill)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, line, 3.0, true)
	draw_arc(Vector2.ZERO, RADIUS - 10.0, 0.0, TAU, 48, Color(0.35, 0.7, 1.0, 0.2), 8.0, true)