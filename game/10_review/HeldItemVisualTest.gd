extends Node
## ============================================================================
## HELD ITEM VISUAL TEST — contrato de presentación de objetos en la mano.
## ============================================================================
## Los objetos picked up deben poder representarse con su sprite real. El
## proyecto todavía no contiene el pack final de iconos; por eso esta puerta
## prohíbe expresamente fabricar un bloque de color y exige el marcador
## "FALTA ASSET - NO INVENTAR" hasta que exista el asset real. Cuando el
## texture llega por la API data-driven, debe aparecer en el nodo HeldItem.
## ============================================================================

const PLAYER_SCENE: PackedScene = preload("res://02_player/Player.tscn")

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame
	var player: Node = PLAYER_SCENE.instantiate()
	add_child(player)
	await get_tree().process_frame

	var visual: Node = player.get_node_or_null("PlayerVisual")
	_check(visual != null, "Player contiene PlayerVisual")
	if visual == null:
		await _finish()
		return

	var held_item: Sprite2D = visual.get_node_or_null("HeldItem") as Sprite2D
	var missing_asset: Label = visual.get_node_or_null("HeldItemMissing") as Label
	_check(held_item != null, "HeldItem es un Sprite2D real")
	_check(missing_asset != null, "HeldItemMissing existe para assets pendientes")

	visual.call("set_held_item", "medkit")
	_check(held_item != null and held_item.texture == null,
		"No se fabrica una textura de color para un objeto sin sprite")
	_check(missing_asset != null and missing_asset.visible \
			and missing_asset.text.contains("FALTA ASSET - NO INVENTAR"),
		"Un asset ausente muestra FALTA ASSET - NO INVENTAR")

	var method_accepts_texture: bool = false
	for method in visual.get_method_list():
		if String(method.get("name", "")) == "set_held_item":
			method_accepts_texture = int(method.get("args", []).size()) >= 2
			break
	_check(method_accepts_texture, "set_held_item acepta un Texture2D data-driven")
	if method_accepts_texture:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		var texture := ImageTexture.create_from_image(image)
		visual.call("set_held_item", "medkit", texture)
		_check(held_item != null and held_item.visible and held_item.texture == texture,
			"El sprite real recibido se muestra en HeldItem")
		_check(missing_asset != null and not missing_asset.visible,
			"El marcador de asset ausente se oculta cuando hay sprite real")

	_check(Inventory.has_method("get_item_texture"),
		"Inventory expone la resolucion data-driven de iconos")
	if Inventory.has_method("get_item_texture"):
		_check(Inventory.call("get_item_texture", "medkit") == null,
			"Un icono inexistente resuelve a null sin inventar arte")

	await _finish()


func _finish() -> void:
	print("HELD_ITEM_VISUAL_TEST failures=%d" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
