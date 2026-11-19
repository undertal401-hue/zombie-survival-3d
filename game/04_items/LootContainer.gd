class_name LootContainer
extends Area2D

## ÍTEM 13: la rareza se lee a distancia. Colores de la paleta canónica de
## ART_BIBLE.md (16 colores): STEEL_LIGHT -> AMBER -> BLOOD_BRIGHT.
const RARITY_COLORS: Dictionary = {
	"common": Color(0.604, 0.671, 0.714),    # STEEL_LIGHT #9aabb6
	"uncommon": Color(0.824, 0.659, 0.404),  # AMBER #d2a867
	"rare": Color(0.910, 0.337, 0.235),      # BLOOD_BRIGHT #e8563c
}
const RARITY_GLOW_STRENGTH: Dictionary = {
	"common": 0.0,
	"uncommon": 0.5,
	"rare": 1.0,
}

## Rareza resuelta (nombre, color y halo) para HUD, minimapa y QA.
var rarity_color: Color = Color.WHITE
var rarity_glow: Color = Color.WHITE

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
	_apply_rarity_visual()

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
	# El contenedor vacío pierde el brillo de rareza.
	body_visual.modulate = Color.WHITE
	lid.modulate = Color.WHITE
	queue_redraw()
	_play_rarity_sfx()

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

## Common (incluidos los bidones de QA) conserva su aspecto original; uncommon
## y rare tiñen el cuerpo/tapa/marcador y dibujan un halo visible a distancia.
func _apply_rarity_visual() -> void:
	var key: String = rarity.to_lower()
	rarity_color = RARITY_COLORS.get(key, RARITY_COLORS["common"]) as Color
	rarity_glow = rarity_color
	if key != "common":
		body_visual.modulate = rarity_color
		lid.modulate = rarity_color
		marker.modulate = rarity_color
	queue_redraw()

func _draw() -> void:
	if _looted:
		return
	var key: String = rarity.to_lower()
	var strength: float = float(RARITY_GLOW_STRENGTH.get(key, 0.0))
	if strength <= 0.0:
		return
	var outer: Color = Color(rarity_glow.r, rarity_glow.g, rarity_glow.b, 0.28 * strength)
	var inner: Color = Color(rarity_glow.r, rarity_glow.g, rarity_glow.b, 0.85 * strength)
	draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 32, outer, 6.0, true)
	draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 32, inner, 1.5, true)

## SFX de botín por rareza: el AudioDirector reutiliza la síntesis PCM de 'loot'
## con un pitch distinto (sin assets nuevos).
func _play_rarity_sfx() -> void:
	var audio: Node = get_tree().get_first_node_in_group("audio_director") as Node
	if audio != null and audio.has_method("play_loot_rarity"):
		audio.call("play_loot_rarity", rarity, global_position)
