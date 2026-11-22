extends Node
## ============================================================================
## ZOMBIE DROP TEST — la recompensa del zombi es un objeto físico recogible.
## ============================================================================
## Esta puerta ejercita la ruta real de muerte y comprueba el ciclo completo:
## el inventario no cambia al morir, cada recompensa aparece como Pickup, el
## objeto sobrevive al cadaver, una aceptacion parcial conserva el resto y una
## recogida nunca duplica unidades.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")
const ZOMBIE_SCENE: PackedScene = preload("res://03_zombies/Zombie.tscn")

const BOSS_KIND: int = 1
const NEAR_CAPACITY: int = 57
const SCRAP_STACK_LIMIT: int = 60

var _failures: Array[String] = []
var _main: Node
var _player: CharacterBody2D
var _scrap_pickup_events: Array[int] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	for _i in range(12):
		await get_tree().process_frame

	_player = _main.get_node_or_null("Player") as CharacterBody2D
	_check(_player != null, "Main crea el jugador real")
	if _player == null:
		await _finish()
		return

	# La pila de chatarra queda a tres unidades de su tope. La primera
	# recogida solo puede aceptar tres; el resto debe permanecer en el mundo.
	Inventory.clear()
	Inventory.add_item("scrap", NEAR_CAPACITY, true)
	_player.global_position = Vector2(-120000.0, -120000.0)

	var pickups_before: Dictionary = _pickup_snapshot()
	var boss: CharacterBody2D = _make_boss()
	_main.add_child(boss)
	boss.global_position = Vector2(100000.0, 100000.0)
	await get_tree().process_frame
	await get_tree().physics_frame

	boss.take_damage(10000.0, _player)
	var pickups_after: Dictionary = _pickup_snapshot()
	var new_pickups: Array[Node] = _new_pickups(pickups_before, pickups_after)

	_check(bool(boss.get("_dead")), "El jefe muere por la ruta real de dano")
	_check(Inventory.count("scrap") == NEAR_CAPACITY,
		"La muerte del zombi no concede chatarra directamente al inventario")
	_check(Inventory.count("medkit") == 0
			and Inventory.count("pistol_ammo") == 0
			and Inventory.count("shotgun_ammo") == 0
			and Inventory.count("rifle_ammo") == 0,
		"La muerte del zombi no concede el resto del botin directamente")

	var scrap_pickups: Array[Node] = _pickups_with_id(new_pickups, "scrap")
	var medkit_pickups: Array[Node] = _pickups_with_id(new_pickups, "medkit")
	var pistol_pickups: Array[Node] = _pickups_with_id(new_pickups, "pistol_ammo")
	var shotgun_pickups: Array[Node] = _pickups_with_id(new_pickups, "shotgun_ammo")
	var rifle_pickups: Array[Node] = _pickups_with_id(new_pickups, "rifle_ammo")

	_check(new_pickups.size() >= 2 and new_pickups.size() <= 5,
		"El jefe crea entre dos y cinco recompensas fisicas")
	_check(scrap_pickups.size() == 1,
		"El jefe crea una unica pickup de chatarra")
	_check(medkit_pickups.size() == 1,
		"El jefe crea una unica pickup de botiquin")
	_check(pistol_pickups.size() <= 1 and shotgun_pickups.size() <= 1
			and rifle_pickups.size() <= 1,
		"El jefe crea como mucho una pickup por tipo de municion")
	_check(pistol_pickups.size() == 0
			or _amount_in_range(pistol_pickups[0], 12, 24),
		"La pickup de 9mm conserva el rango original de 12-24")
	_check(shotgun_pickups.size() == 0
			or _amount_in_range(shotgun_pickups[0], 6, 12),
		"La pickup de 12ga conserva el rango original de 6-12")
	_check(rifle_pickups.size() == 0
			or _amount_in_range(rifle_pickups[0], 12, 24),
		"La pickup de 5.56 conserva el rango original de 12-24")

	var drop_root: Node = _main.get_node_or_null("ZombieDrops")
	_check(drop_root != null, "Main crea una raiz persistente para el botin de zombis")
	_check(drop_root != null and drop_root.is_in_group("zombie_drop_root"),
		"La raiz de botin de zombis es resoluble por su grupo")
	_check(_all_below_root(new_pickups, drop_root),
		"Todas las recompensas fisicas pertenecen a la raiz persistente")

	var scrap_amount: int = 0
	if scrap_pickups.size() == 1:
		var scrap_pickup: Node = scrap_pickups[0]
		scrap_amount = int(scrap_pickup.get("amount"))
		_check(scrap_amount >= 5 and scrap_amount <= 8,
			"La pickup de chatarra conserva la cantidad original de 5-8")
		_check(_missing_asset_is_honest(scrap_pickup),
			"La recompensa sin icono declara FALTA ASSET - NO INVENTAR")

	# El cadaver actual desaparece tras su animacion. La pickup debe quedar en
	# el mundo y conservar la recompensa pendiente.
	for _i in range(100):
		await get_tree().physics_frame
	_check(not is_instance_valid(boss), "El cadaver termina su ciclo visual")
	_check(scrap_pickups.size() == 1 and is_instance_valid(scrap_pickups[0]),
		"La recompensa fisica sobrevive a la eliminacion del cadaver")
	_check(scrap_pickups.size() == 1
			and int(scrap_pickups[0].get("amount")) == scrap_amount,
		"La cantidad pendiente no cambia mientras nadie la recoge")

	if scrap_pickups.size() == 1 and is_instance_valid(scrap_pickups[0]):
		await _exercise_collection(scrap_pickups[0], scrap_amount)

	await _finish()


func _make_boss() -> CharacterBody2D:
	var boss: CharacterBody2D = ZOMBIE_SCENE.instantiate() as CharacterBody2D
	boss.name = "ZombieDropBoss"
	boss.set("kind", BOSS_KIND)
	boss.set("speed", 0.0)
	boss.set("detect_radius", 0.0)
	boss.set("close_sense_radius", 0.0)
	boss.set("lose_radius", 0.0)
	return boss


func _pickup_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for node in get_tree().get_nodes_in_group("pickups"):
		if is_instance_valid(node):
			snapshot[node.get_instance_id()] = node
	return snapshot


func _new_pickups(before: Dictionary, after: Dictionary) -> Array[Node]:
	var result: Array[Node] = []
	for instance_id in after.keys():
		if before.has(instance_id):
			continue
		var node: Node = after[instance_id] as Node
		if node != null and is_instance_valid(node):
			result.append(node)
	return result


func _pickups_with_id(pickups: Array[Node], item_id: String) -> Array[Node]:
	var result: Array[Node] = []
	for node in pickups:
		if is_instance_valid(node) and String(node.get("item_id")) == item_id:
			result.append(node)
	return result


func _amount_in_range(node: Node, minimum: int, maximum: int) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var amount: int = int(node.get("amount"))
	return amount >= minimum and amount <= maximum


func _all_below_root(pickups: Array[Node], root: Node) -> bool:
	if root == null:
		return false
	for node in pickups:
		var ancestor: Node = node.get_parent()
		var found: bool = false
		while ancestor != null:
			if ancestor == root:
				found = true
				break
			ancestor = ancestor.get_parent()
		if not found:
			return false
	return true


func _missing_asset_is_honest(pickup: Node) -> bool:
	var missing: Label = pickup.get_node_or_null("MissingAsset") as Label
	return missing != null and missing.visible \
			and missing.text.contains("FALTA ASSET - NO INVENTAR")


func _exercise_collection(pickup: Node, original_amount: int) -> void:
	if not Inventory.item_picked_up.is_connected(_on_item_picked_up):
		Inventory.item_picked_up.connect(_on_item_picked_up)
	_player.global_position = pickup.global_position
	for _i in range(4):
		await get_tree().physics_frame

	var accepted_first: int = SCRAP_STACK_LIMIT - NEAR_CAPACITY
	_check(Inventory.count("scrap") == SCRAP_STACK_LIMIT,
		"La primera recogida acepta solo la capacidad disponible")
	_check(is_instance_valid(pickup)
			and int(pickup.get("amount")) == original_amount - accepted_first,
		"La pickup parcial conserva las unidades que no caben")
	_check(_scrap_pickup_events == [accepted_first],
		"La recogida parcial notifica exactamente las unidades aceptadas")

	Inventory.remove_item("scrap", accepted_first)
	_player.global_position = Vector2(-120000.0, -120000.0)
	await get_tree().physics_frame
	_player.global_position = pickup.global_position if is_instance_valid(pickup) \
			else Vector2(100000.0, 100000.0)
	for _i in range(4):
		await get_tree().physics_frame

	_check(Inventory.count("scrap") == original_amount,
		"La segunda recogida entrega el resto pendiente")
	_check(not is_instance_valid(pickup),
		"La pickup se elimina cuando ya no queda contenido")
	_check(_scrap_pickup_events.size() == 2
			and _scrap_pickup_events[0] + _scrap_pickup_events[1] == original_amount,
		"Ninguna unidad se concede dos veces")

	for _i in range(4):
		await get_tree().physics_frame
	_check(Inventory.count("scrap") == original_amount,
		"La recompensa no vuelve a concederse despues de recogerse")


func _on_item_picked_up(item_id: String, amount: int) -> void:
	if item_id == "scrap":
		_scrap_pickup_events.append(amount)


func _finish() -> void:
	if Inventory.item_picked_up.is_connected(_on_item_picked_up):
		Inventory.item_picked_up.disconnect(_on_item_picked_up)
	if is_instance_valid(_main):
		_main.queue_free()
		_main = null
	for _i in range(3):
		await get_tree().process_frame
	print("ZOMBIE_DROP_TEST failures=%d" % _failures.size())
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)
