extends Node
## ============================================================================
## TREE FELLING TEST — talar con hacha, caer y soltar madera.
## ============================================================================
## Esta puerta ejercita el camino real: el hacha golpea un árbol físico, el
## bosque conserva el batching MultiMesh, rota el árbol caído alrededor de su
## base, desactiva únicamente la forma talada y deja un único Pickup de madera.
## El pack oficial de iconos sigue ausente: el botín debe declarar el asset
## pendiente, nunca sustituirlo por un rectángulo de color.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")
const AXE_PATH: String = "res://02_player/weapons/Hacha.tres"
const MACHETE_PATH: String = "res://02_player/weapons/Machete.tres"

var _failures: Array[String] = []
var _main: Node
var _player: CharacterBody2D
var _weapon_controller: WeaponController
var _forest: Node2D
var _controller_melee_weapon: Weapon = null


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	# La escena de prueba ya terminó su propio _ready al dejar el primer frame;
	# añadir Main al root antes de ese punto deja al root ocupado.
	await get_tree().process_frame
	_main = MAIN_SCENE.instantiate()
	# La semilla se fija antes de que Forest entre al árbol y ejecute _ready().
	_forest = _main.get_node_or_null("Level/Forest") as Node2D
	if _forest != null:
		_forest.set("SEED", 20261122)
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	for _i in range(12):
		await get_tree().process_frame

	_player = _main.get_node_or_null("Player") as CharacterBody2D
	_weapon_controller = _player.get_node_or_null("WeaponController") as WeaponController if _player != null else null

	_check(_player != null, "Main crea el jugador real")
	_check(_weapon_controller != null, "El jugador tiene WeaponController")
	_check(_weapon_controller != null and _weapon_controller.weapons.size() == 6,
		"El loadout conserva seis ranuras para armas, hacha y mejora meta")
	_check(_forest != null, "Main crea el bosque real")
	_check(_forest != null and _forest.tree_count() > 1, "El bosque contiene arboles para talar")

	var axe: Weapon = null
	if ResourceLoader.exists(AXE_PATH):
		axe = load(AXE_PATH) as Weapon
	_check(axe != null, "Existe el recurso real Hacha.tres")
	if axe != null:
		_check(int(axe.category) == 7, "El hacha usa la categoria TOOL")
		_check(bool(axe.get("can_chop_trees")), "El hacha puede talar arboles")
		_check(axe.base_damage > 0.0, "El hacha tiene dano real")

	var axe_slot: int = _find_axe_slot(_weapon_controller)
	_check(axe_slot == 4, "El hacha ocupa la ranura propia 4")
	_check(InputMap.has_action("weapon_slot_6"), "La sexta ranura tiene una tecla directa")
	if axe_slot == 4 and _weapon_controller != null and _weapon_controller.weapons.size() > 5:
		var meta: Node = _main.get_node_or_null("MetaProgress")
		if meta != null and meta.has_method("_equip_extra_weapon"):
			meta.set("_applied_extra_weapon", {})
			_weapon_controller.weapons[5] = null
			meta.call("_equip_extra_weapon")
			_check(_weapon_controller.get_weapon_in_slot(4) != null
					and _weapon_controller.get_weapon_in_slot(4).weapon_name == "Hacha",
				"La mejora meta no reemplaza el hacha")
			_check(_weapon_controller.get_weapon_in_slot(5) != null
					and _weapon_controller.get_weapon_in_slot(5).weapon_name == "Escopeta 12ga",
				"La mejora meta ocupa su propia sexta ranura")

	# El hacha debe atravesar la ruta real del controlador: equipar la ranura
	# TOOL y pedir un disparo debe emitir melee_attack, no un disparo de arma.
	if axe_slot == 4 and _weapon_controller != null and _player != null:
		_controller_melee_weapon = null
		var melee_callback := Callable(self, "_on_controller_melee_attack")
		if not _weapon_controller.melee_attack.is_connected(melee_callback):
			_weapon_controller.melee_attack.connect(melee_callback)
		_weapon_controller.call("_equip_slot", axe_slot)
		_player.global_position = Vector2(100000.0, 100000.0)
		_player.set("stamina", 100.0)
		var equipped_axe: Weapon = _weapon_controller.get_weapon_in_slot(axe_slot)
		if equipped_axe != null:
			equipped_axe.set("last_shot_time", 0.0)
		_weapon_controller.call("_try_fire")
		await get_tree().process_frame
		_check(_controller_melee_weapon != null
				and _controller_melee_weapon.weapon_name == "Hacha",
			"El controlador enruta el hacha por la ruta cuerpo a cuerpo")
		if _weapon_controller.melee_attack.is_connected(melee_callback):
			_weapon_controller.melee_attack.disconnect(melee_callback)

	_check(Inventory.ITEM_DEFS.has("wood"), "Madera existe como objeto de inventario")
	_check(Inventory.ITEM_DEFS.has("Hacha"), "Hacha existe como objeto de inventario")
	_check(_missing_asset_is_honest("wood"), "El icono ausente de madera no se sustituye por arte fabricado")
	_check(_missing_asset_is_honest("Hacha"), "El icono ausente del hacha no se sustituye por arte fabricado")

	if axe != null and _forest != null and _player != null:
		await _exercise_felling(axe, axe_slot)

	await _finish()


func _find_axe_slot(controller: WeaponController) -> int:
	if controller == null:
		return -1
	for slot in range(controller.weapons.size()):
		var weapon: Weapon = controller.weapons[slot]
		if weapon != null and weapon.weapon_name == "Hacha":
			return slot
	return -1


func _missing_asset_is_honest(item_id: String) -> bool:
	if not Inventory.ITEM_DEFS.has(item_id):
		return false
	var path: String = String(Inventory.ITEM_DEFS[item_id].get("icon", ""))
	var resolved: Texture2D = Inventory.get_item_texture(item_id)
	if ResourceLoader.exists(path, "Texture2D"):
		return resolved != null and resolved.resource_path == path
	return resolved == null


func _exercise_felling(axe: Weapon, axe_slot: int) -> void:
	_check(_forest.has_method("tree_snapshot"), "El bosque expone el estado real de cada arbol")
	_check(_forest.has_method("damage_tree_by_shape"), "El bosque recibe el RID exacto de la forma golpeada")
	if not _forest.has_method("tree_snapshot") or not _forest.has_method("damage_tree_by_shape"):
		return

	var before: Dictionary = _forest.call("tree_snapshot", 0) as Dictionary
	var tree_position: Vector2 = before.get("position", Vector2.ZERO)
	var body_rid: RID = before.get("body_rid", RID())
	var shape_rid: RID = before.get("shape_rid", RID())
	var shape_index: int = int(before.get("shape_index", -1))
	var trunk_before: Transform2D = before.get("trunk_transform", Transform2D.IDENTITY)
	var tree_height: float = float(before.get("height", 0.0))
	var canopy_before: Array = before.get("canopy_transforms", []) as Array
	var body_shapes_before: int = int(before.get("body_shape_count", 0))
	var chunk_bodies_before: int = int(before.get("chunk_body_count", 0))
	var multimesh_nodes_before: int = int(before.get("multimesh_node_count", 0))
	var multimesh_instances_before: int = int(before.get("multimesh_instance_total", 0))

	_check(String(before.get("state", "")) == "standing", "El arbol empieza en pie")
	_check(body_rid.is_valid() and shape_rid.is_valid() and shape_index >= 0,
		"El arbol conserva la identidad exacta de cuerpo y forma")

	# El hacha golpea el arbol por el raycast real del jugador. La posicion se
	# fija a 30 px del tronco para que el resultado no dependa de la semilla.
	_player.global_position = tree_position - Vector2(30.0, 0.0)
	_player.rotation = 0.0
	await get_tree().physics_frame

	var state: String = "standing"
	for _hit in range(6):
		_player.set("_melee_cooldown", 0.0)
		_player.set("stamina", 100.0)
		_player.call("_on_melee_attack", axe, Vector2.RIGHT)
		await get_tree().physics_frame
		state = String((_forest.call("tree_snapshot", 0) as Dictionary).get("state", ""))
		if state != "standing":
			break

	_check(state == "falling" or state == "felled", "El hacha hace caer el arbol")
	await get_tree().create_timer(1.0).timeout
	var after: Dictionary = _forest.call("tree_snapshot", 0) as Dictionary
	state = String(after.get("state", ""))
	var fall_angle: float = float(after.get("fall_angle", 0.0))
	var trunk_after: Transform2D = after.get("trunk_transform", Transform2D.IDENTITY)
	var canopy_after: Array = after.get("canopy_transforms", []) as Array

	_check(state == "felled", "El arbol termina talado")
	_check(absf(absf(fall_angle) - PI * 0.5) < 0.02, "El arbol cae horizontal a la izquierda o a la derecha")
	_check(trunk_after != trunk_before, "El MultiMesh rota el arbol alrededor de su base")
	_check(tree_height > 0.0, "El arbol expone su altura real para verificar el pivote")

	var trunk_angle: float = wrapf(trunk_after.get_rotation() - trunk_before.get_rotation(), -PI, PI)
	var trunk_offset: Vector2 = trunk_after.get_origin() - tree_position
	_check(absf(absf(trunk_angle) - PI * 0.5) < 0.02,
		"El tronco gira noventa grados reales alrededor de la base")
	_check(tree_height > 0.0
			and absf(trunk_offset.length() - tree_height * 0.5) < 1.0
			and absf(trunk_offset.y) < 1.0,
		"El pivote del tronco permanece en la base y queda horizontal")
	_check(canopy_before.size() > 0 and canopy_after.size() == canopy_before.size(),
		"El bosque expone las transformaciones reales de la copa")
	if canopy_before.size() > 0 and canopy_after.size() == canopy_before.size():
		var canopy_before_xf: Transform2D = canopy_before[0]
		var canopy_after_xf: Transform2D = canopy_after[0]
		var canopy_angle: float = wrapf(
			canopy_after_xf.get_rotation() - canopy_before_xf.get_rotation(), -PI, PI)
		_check(canopy_after_xf != canopy_before_xf
				and absf(absf(canopy_angle) - PI * 0.5) < 0.02,
			"La copa gira noventa grados con el tronco")
	_check(int(after.get("body_shape_count", 0)) == body_shapes_before,
		"Talar no elimina la forma del cuerpo chunked")
	_check(int(after.get("chunk_body_count", 0)) == chunk_bodies_before,
		"Talar no destruye ni duplica los cuerpos chunked")
	_check(int(after.get("multimesh_node_count", 0)) == multimesh_nodes_before,
		"Talar no crea un nodo visual por arbol")
	_check(int(after.get("multimesh_instance_total", 0)) == multimesh_instances_before,
		"Talar preserva el batching y el instance_count MultiMesh")

	var still_blocks: bool = _shape_still_blocks(tree_position, body_rid, shape_index)
	_check(not still_blocks, "Solo la forma del arbol talado deja de bloquear")

	var control_index: int = _find_control_tree(0, before.get("chunk_key", Vector2i(0, 0)))
	_check(control_index >= 0,
		"La semilla de prueba incluye un arbol control del mismo chunk")
	if control_index >= 0:
		var control: Dictionary = _forest.call("tree_snapshot", control_index) as Dictionary
		var control_body_rid: RID = control.get("body_rid", RID())
		var control_shape_index: int = int(control.get("shape_index", -1))
		var control_still_blocks: bool = _shape_still_blocks(
			control.get("position", Vector2.ZERO), control_body_rid, control_shape_index)
		_check(control_still_blocks, "Otro arbol del mismo chunk conserva su colision")
		_check(String(control.get("state", "")) == "standing", "El arbol control del mismo chunk permanece intacto")

	var wood_pickups: Array[Node] = _wood_pickups()
	_check(wood_pickups.size() == 1, "El arbol deja un unico Pickup de madera")
	var accepted_again: bool = bool(_forest.call("damage_tree_by_shape",
		body_rid, shape_index, 999.0, Vector2.RIGHT))
	_check(not accepted_again, "Un arbol ya talado no admite otro talado")
	_check(_wood_pickups().size() == 1, "Un segundo golpe no duplica el botin")

	if wood_pickups.size() == 1:
		var pickup: Node = wood_pickups[0]
		var pickup_2d: Node2D = pickup as Node2D
		_check(String(pickup.get("item_id")) == "wood", "El Pickup contiene madera")
		_check(int(pickup.get("amount")) == 3, "El Pickup contiene tres unidades de madera")
		var missing_asset: Label = pickup.get_node_or_null("MissingAsset") as Label
		_check(missing_asset != null and missing_asset.visible
				and missing_asset.text.contains("FALTA ASSET - NO INVENTAR"),
			"El botin declara el icono oficial pendiente")

		# El contrato de recogida admite aceptacion parcial: al llenarse la
		# pila, el objeto conserva el resto. Si se destruye tras aceptar solo
		# una unidad, las otras dos desaparecen del mundo.
		var existing_wood: int = Inventory.count("wood")
		if existing_wood > 0:
			Inventory.remove_item("wood", existing_wood)
		Inventory.add_item("wood", 98, true)
		_player.global_position = pickup_2d.global_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(Inventory.count("wood") == 99,
			"La aceptacion parcial de madera rellena la pila hasta 99")
		var pickup_survives: bool = is_instance_valid(pickup)
		_check(pickup_survives,
			"La pickup parcial permanece viva hasta recoger todo su contenido")
		if pickup_survives:
			_check(int(pickup.get("amount")) == 2,
				"La pickup parcial conserva las dos unidades no recogidas")
		Inventory.remove_item("wood", 3)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(Inventory.count("wood") == 98,
			"La pickup parcial entrega el resto cuando vuelve a caber")
		_check(not is_instance_valid(pickup),
			"La pickup se elimina solo cuando no queda contenido")

	# El machete no es una herramienta de tala: otro arbol permanece intacto.
	var machete: Weapon = load(MACHETE_PATH) as Weapon
	if machete != null and _forest.tree_count() > 1:
		var other: Dictionary = _forest.call("tree_snapshot", 1) as Dictionary
		var other_position: Vector2 = other.get("position", Vector2.ZERO) as Vector2
		_player.global_position = other_position - Vector2(30.0, 0.0)
		_player.rotation = 0.0
		await get_tree().physics_frame
		_player.set("_melee_cooldown", 0.0)
		_player.set("stamina", 100.0)
		_player.call("_on_melee_attack", machete, Vector2.RIGHT)
		await get_tree().physics_frame
		_check(String((_forest.call("tree_snapshot", 1) as Dictionary).get("state", "")) == "standing",
			"El machete no tala arboles")

	# El hacha debe quedar visible en el loadout sin fabricar su sprite.
	if axe_slot >= 0:
		# Recoger madera cambia el objeto visible en la mano. Si el hacha ya
		# estaba equipada, _equip_slot no reemite weapon_changed; pasar por otra
		# ranura fuerza la presentacion real del hacha que se quiere comprobar.
		if _weapon_controller.current_slot == axe_slot:
			_weapon_controller.call("_equip_slot", 1)
		_weapon_controller.call("_equip_slot", axe_slot)
		await get_tree().process_frame
		var visual: Node = _player.get_node_or_null("PlayerVisual")
		var held_missing: Label = visual.get_node_or_null("HeldItemMissing") as Label if visual != null else null
		_check(held_missing != null and held_missing.visible
				and held_missing.text.contains("Hacha"),
			"El hacha en la mano declara FALTA ASSET - NO INVENTAR")
		var menu: Node = _main.get_node_or_null("InventoryMenu")
		var menu_missing: Label = menu.get_node_or_null(
			"Panel/WeaponSection/WeaponInfo/WeaponIconMissing") as Label if menu != null else null
		_check(menu_missing != null and menu_missing.visible
				and menu_missing.text.contains("FALTA ASSET - NO INVENTAR"),
			"El inventario declara el icono pendiente del hacha")
		var slots_row: HBoxContainer = menu.get_node_or_null(
			"Panel/WeaponSection/SlotsRow") as HBoxContainer if menu != null else null
		_check(slots_row != null and slots_row.get_child_count() == 6,
			"El inventario muestra las seis ranuras")


## Consulta por forma: el RID identifica el cuerpo chunked y `shape` identifica
## la forma dentro de ese cuerpo. Un point query solo devolveria el RID del
## cuerpo y no podria probar que se desactivo una forma concreta.
func _shape_still_blocks(position: Vector2, body_rid: RID, shape_index: int) -> bool:
	if _player == null or not body_rid.is_valid() or shape_index < 0:
		return false
	var circle := CircleShape2D.new()
	circle.radius = 1.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, position)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for hit: Dictionary in _player.get_world_2d().direct_space_state.intersect_shape(query, 32):
		if hit.get("rid", RID()) == body_rid and int(hit.get("shape", -1)) == shape_index:
			return true
	return false


func _find_control_tree(target_index: int, chunk_key: Vector2i) -> int:
	if _forest == null or not _forest.has_method("tree_snapshot"):
		return -1
	for index in range(_forest.tree_count()):
		if index == target_index:
			continue
		var snapshot: Dictionary = _forest.call("tree_snapshot", index) as Dictionary
		if snapshot.get("chunk_key", Vector2i(0, 0)) == chunk_key:
			return index
	return -1


func _wood_pickups() -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group("pickups"):
		if is_instance_valid(node) and String(node.get("item_id")) == "wood":
			result.append(node)
	return result


func _on_controller_melee_attack(weapon: Weapon, _direction: Vector2) -> void:
	_controller_melee_weapon = weapon


func _finish() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
		_main = null
	for _i in range(3):
		await get_tree().process_frame
	print("TREE_FELLING_TEST failures=%d" % _failures.size())
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)
	for failure in _failures:
		assert(false, "TREE_FELLING_TEST: " + failure)
