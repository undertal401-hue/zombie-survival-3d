extends Node
## ============================================================================
## HELD ITEM VISUAL TEST — contrato de presentación de objetos en la mano.
## ============================================================================
## Los objetos picked up y las armas equipadas deben representarse con su
## sprite real. El proyecto todavía no contiene el pack final de iconos; por
## eso esta puerta prohíbe expresamente fabricar un bloque de color y exige el
## marcador "FALTA ASSET - NO INVENTAR" hasta que exista el asset real.
##
## El arnés usa Main.tscn para cubrir el estado inicial real: el arma equipada
## no debe perderse porque WeaponController llegue al ready antes que Player,
## ni puede ser sustituida por el seed de inventario del arranque.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	_check(player != null, "Main crea un jugador real")
	if player == null:
		await _finish()
		return

	var visual: Node = player.get_node_or_null("PlayerVisual")
	_check(visual != null, "Player contiene PlayerVisual")
	if visual == null:
		await _finish()
		return

	var held_item: Sprite2D = visual.get_node_or_null("HeldItem") as Sprite2D
	var missing_asset: Label = visual.get_node_or_null("HeldItemMissing") as Label
	_check(held_item != null, "HeldItem es un Sprite2D real")
	_check(missing_asset != null, "HeldItemMissing existe para assets pendientes")
	if held_item == null or missing_asset == null:
		await _finish()
		return

	var weapon_controller: Node = player.get_node_or_null("WeaponController")
	_check(weapon_controller != null, "Player contiene WeaponController")
	if weapon_controller == null:
		await _finish()
		return

	var current_weapon: Weapon = weapon_controller.get("current_weapon") as Weapon
	_check(current_weapon != null, "El jugador arranca con un arma equipada")
	if current_weapon != null:
		_check(current_weapon.weapon_name == "Pistola 9mm",
			"El arma inicial sigue siendo la pistola equipada")
		_check_held_resolution(visual, held_item, missing_asset,
			current_weapon.weapon_name,
			"El arma inicial se representa desde su estado real")

	# La senal de recogida debe llegar al mismo nodo y usar la resolucion
	# oficial del item, no un color generado.
	Inventory.item_picked_up.emit("medkit", 1)
	await get_tree().process_frame
	_check_held_resolution(visual, held_item, missing_asset, "medkit",
		"item_picked_up actualiza el objeto en mano")

	# Cambiar de arma tambien debe pasar por la misma presentacion.
	if current_weapon != null:
		weapon_controller.emit_signal("weapon_changed", current_weapon)
		await get_tree().process_frame
		_check_held_resolution(visual, held_item, missing_asset,
			current_weapon.weapon_name,
			"weapon_changed actualiza el arma en mano")

	# Toda ruta declarada que exista debe cargar exactamente ese asset. Las
	# rutas ausentes siguen resolviendo a null, nunca a arte fabricado.
	for item_id: String in Inventory.ITEM_DEFS.keys():
		var path: String = String(Inventory.ITEM_DEFS[item_id].get("icon", ""))
		var resolved: Texture2D = Inventory.get_item_texture(item_id)
		if ResourceLoader.exists(path, "Texture2D"):
			_check(resolved != null and resolved.resource_path == path,
				"El icono oficial de %s carga desde su ruta data-driven" % item_id)
		else:
			_check(resolved == null,
				"El icono ausente de %s resuelve a null sin inventar arte" % item_id)

	# La API sigue admitiendo un Texture2D explicito cuando existe.
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var explicit_texture := ImageTexture.create_from_image(image)
	visual.call("set_held_item", "medkit", explicit_texture)
	_check(held_item.visible and held_item.texture == explicit_texture,
		"Un Texture2D real se muestra en HeldItem")
	_check(not missing_asset.visible,
		"El marcador de asset ausente se oculta cuando hay sprite real")

	# El marcador vive bajo el jugador, que rota al apuntar. Debe compensar esa
	# rotacion para que siga legible en pantalla.
	player.rotation = -0.75
	visual.call("update_from_player", player, Vector2.ZERO, weapon_controller)
	_check(is_equal_approx(missing_asset.rotation, 0.75),
		"El marcador compensa la rotacion del jugador")
	_check(absf(missing_asset.get_global_transform().get_rotation()) < 0.001,
		"El marcador permanece alineado con la pantalla")

	await _finish()


func _check_held_resolution(visual: Node, held_item: Sprite2D,
		missing_asset: Label, item_id: String, context: String) -> void:
	var resolved: Texture2D = Inventory.get_item_texture(item_id)
	if resolved != null:
		_check(held_item.visible and held_item.texture == resolved,
			"%s: muestra el sprite oficial" % context)
		_check(not missing_asset.visible,
			"%s: oculta el marcador cuando existe el asset" % context)
	else:
		_check(not held_item.visible and held_item.texture == null,
			"%s: no fabrica una textura de color" % context)
		_check(missing_asset.visible and missing_asset.text.contains("FALTA ASSET - NO INVENTAR"),
			"%s: muestra FALTA ASSET - NO INVENTAR" % context)
		_check(missing_asset.text.contains(Inventory.display_name(item_id)),
			"%s: identifica el item que falta" % context)


func _finish() -> void:
	print("HELD_ITEM_VISUAL_TEST failures=%d" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
