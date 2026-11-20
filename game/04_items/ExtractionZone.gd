class_name ExtractionZone
extends Area2D

## ÍTEM 14: la victoria no es instantánea. Al entrar con los tres bidones
## arranca una cuenta atrás de EXTRACTION_COUNTDOWN segundos que mantiene la
## tensión hasta la evacuación; solo al terminar se emite EventBus.victory.

signal countdown_progress(remaining: float)

const RADIUS := 72.0
const REQUIRED_FUEL := 3
## Duración de la cuenta atrás de extracción (segundos).
const EXTRACTION_COUNTDOWN: float = 12.0

@onready var title: Label = $Title

var _player_inside: Node2D = null
var _victory_triggered: bool = false
## -1 = cuenta atrás no iniciada; >= 0 = segundos restantes de evacuación.
var _countdown: float = -1.0
var _last_notified_second: int = -1

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

func _check_extraction(_player: Node2D) -> void:
	if _victory_triggered:
		return
	
	# `combustible` es el bidón del objetivo (QA); `vehicle_fuel` es el id
	# fabricable. Ambos sirven para extraer, pero no se duplica su cuenta.
	var fuel: int = Inventory.count("combustible") + Inventory.count("vehicle_fuel")
	if fuel >= REQUIRED_FUEL:
		_begin_countdown()
	else:
		var needed: int = REQUIRED_FUEL - fuel
		EventBus.notification.emit("Faltan %d bidones de combustible para extraer." % needed)

## Arranca la cuenta atrás una sola vez: ni el inventario ni un nuevo
## body_entered pueden reiniciarla ni adelantar la victoria.
func _begin_countdown() -> void:
	if _victory_triggered or _countdown >= 0.0:
		return
	_countdown = EXTRACTION_COUNTDOWN
	_last_notified_second = -1
	EventBus.notification.emit("EXTRACCIÓN iniciada: cuenta atrás de %d s para evacuar." % int(EXTRACTION_COUNTDOWN))
	emit_signal("countdown_progress", _countdown)
	_update_title()

## Progreso de la cuenta atrás: aviso por EventBus.notification cada segundo y
## una barra/progress en el título; el progreso también sale por emit_signal
## de la señal countdown_progress para HUD/minimapa. Victoria diferida a cero.
func _process(delta: float) -> void:
	if _victory_triggered or _countdown < 0.0:
		return
	_countdown = maxf(0.0, _countdown - delta)
	emit_signal("countdown_progress", _countdown)
	var seconds: int = int(ceilf(_countdown))
	if seconds != _last_notified_second:
		_last_notified_second = seconds
		EventBus.notification.emit("EXTRACCIÓN: %d s para evacuar." % seconds)
		_update_title()
	if _countdown <= 0.0:
		_complete_victory()

func _complete_victory() -> void:
	if _victory_triggered:
		return
	_victory_triggered = true
	_countdown = -1.0
	EventBus.victory.emit()
	EventBus.notification.emit("¡EXTRACCIÓN EXITOSA! Has sobrevivido.")
	call_deferred("_show_victory")

func _show_victory() -> void:
	var hud := get_tree().get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("_on_victory"):
		hud.call("_on_victory")
	else:
		# Fallback: pause and show generic victory
		get_tree().paused = true
		EventBus.notification.emit("¡VICTORIA! R para reiniciar.")

func _update_title() -> void:
	if _countdown >= 0.0 and not _victory_triggered:
		title.text = "ZONA DE EXTRACCIÓN · %d s" % int(ceilf(_countdown))
		title.modulate = Color(1.0, 0.85, 0.45)
	else:
		title.text = "ZONA DE EXTRACCIÓN"
		title.modulate = Color(0.7, 0.9, 1.0)

func _draw() -> void:
	var fill := Color(0.2, 0.5, 0.9, 0.1)
	var line := Color(0.35, 0.7, 1.0, 0.9)
	draw_circle(Vector2.ZERO, RADIUS, fill)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, line, 3.0, true)
	draw_arc(Vector2.ZERO, RADIUS - 10.0, 0.0, TAU, 48, Color(0.35, 0.7, 1.0, 0.2), 8.0, true)