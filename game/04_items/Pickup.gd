extends Area2D

const MISSING_ASSET_TEXT: String = "FALTA ASSET - NO INVENTAR"

@export var item_id: String = "llave"
@export var amount: int = 1

var _collected: bool = false

func _ready() -> void:
	add_to_group("pickups")
	_refresh_visual()

## Usa exclusivamente el icono oficial resuelto por Inventory. Si el pack aun
## no esta disponible, el rectangulo generico se oculta y se declara el asset
## pendiente; no se fabrica arte sustituto.
func _refresh_visual() -> void:
	var visual := get_node_or_null("Visual") as Polygon2D
	var icon := get_node_or_null("ItemIcon") as Sprite2D
	var missing := get_node_or_null("MissingAsset") as Label
	var texture: Texture2D = Inventory.get_item_texture(item_id)
	if texture != null:
		if icon != null:
			icon.texture = texture
			icon.visible = true
		if missing != null:
			missing.text = MISSING_ASSET_TEXT
			missing.visible = false
		if visual != null:
			visual.visible = false
		return
	if icon != null:
		icon.visible = false
	if missing != null:
		missing.text = MISSING_ASSET_TEXT
		missing.visible = true
	if visual != null:
		visual.visible = false

## Respaldo determinista para el caso en que el Area2D se crea o el jugador
## entra en el mismo frame de fisica: el broadphase puede tardar un frame en
## informar la entrada. La senal Area2D sigue siendo la via principal.
func _physics_process(_delta: float) -> void:
	if _collected:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	if global_position.distance_to(player.global_position) <= 16.0:
		_try_collect(player)

func _on_body_entered(body: Node2D) -> void:
	_try_collect(body)

func _try_collect(body: Node2D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	# add_item notifica el motivo exacto (pila llena / sobrecarga) y no se
	# destruye la pickup si no cupo: el jugador puede volver a por ella.
	var room: Dictionary = Inventory.can_add_item(item_id, amount)
	var accepted: int = int(room.get("added", 0))
	if accepted <= 0:
		return
	var added: int = Inventory.add_item(item_id, accepted)
	if added <= 0:
		return
	# El inventario puede aceptar solo una parte si la pila o el peso estan
	# casi llenos. El resto sigue existiendo en el mundo: la pickup no se
	# destruye hasta que su cantidad pendiente llega a cero.
	amount -= added
	if amount <= 0:
		_collected = true
		queue_free()
