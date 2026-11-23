extends Node
## ============================================================================
## ZOMBIE DROP TEST — la recompensa del zombi es un objeto físico recogible.
## ============================================================================
## Esta puerta ejercita la ruta real de muerte y el contrato completo del
## botín: el inventario no cambia al morir, cada recompensa aparece como
## Pickup, la matriz determinista fija la politica de municion del jefe, el
## objeto sobrevive al cadaver y a las limpiezas de bosque/horda, una aceptacion
## parcial conserva el resto y una recogida nunca duplica unidades.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")
const ZOMBIE_SCENE: PackedScene = preload("res://03_zombies/Zombie.tscn")

const BOSS_KIND: int = 1
const NEAR_CAPACITY: int = 57
const SCRAP_STACK_LIMIT: int = 60
const DEFAULT_MASTER_SEED: int = 20261117
const MISSING_ASSET_TEXT: String = "FALTA ASSET - NO INVENTAR"
const ALLOWED_BOSS_REWARD_IDS: Array[String] = [
	"scrap", "medkit", "pistol_ammo", "shotgun_ammo", "rifle_ammo",
]
## Semillas maestras -> stream `loot` -> rama compartida de municion.
## Las cantidades exactas fixation ademas el orden de los draws del RNG.
const BOSS_BRANCH_CASES: Array[Dictionary] = [
	{
		"seed": 1,
		"label": "roll < 0,30: pistola + escopeta + fusil",
		"rewards": {
			"scrap": 7, "pistol_ammo": 22, "shotgun_ammo": 8,
			"rifle_ammo": 24, "medkit": 1,
		},
	},
	{
		"seed": 6,
		"label": "0,30 <= roll < 0,50: pistola + escopeta",
		"rewards": {"scrap": 6, "pistol_ammo": 20, "shotgun_ammo": 11, "medkit": 2},
	},
	{
		"seed": 16,
		"label": "0,50 <= roll < 0,70: solo pistola",
		"rewards": {"scrap": 6, "pistol_ammo": 21, "medkit": 1},
	},
	{
		"seed": 3,
		"label": "roll >= 0,70: sin municion",
		"rewards": {"scrap": 5, "medkit": 1},
	},
]

var _failures: Array[String] = []
var _main: Node
var _player: CharacterBody2D
var _foreign_drop_root: Node2D
var _scrap_pickup_events: Array[int] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame

	# Este raiz pertenece al grupo, pero NO al mundo actual. El codigo de
	# produccion debe priorizar `Main/ZombieDrops`; nunca debe attachar botin
	# a un grupo externo obsoleto de otra escena o transicion.
	_foreign_drop_root = Node2D.new()
	_foreign_drop_root.name = "ForeignZombieDrops"
	_foreign_drop_root.add_to_group("zombie_drop_root")
	get_tree().root.add_child(_foreign_drop_root)

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
	var inventory_before: Dictionary = _inventory_counts([
		"scrap", "medkit", "pistol_ammo", "shotgun_ammo", "rifle_ammo",
	])
	var boss: CharacterBody2D = _make_boss()
	_main.add_child(boss)
	boss.global_position = Vector2(100000.0, 100000.0)
	await get_tree().process_frame
	await get_tree().physics_frame

	boss.take_damage(10000.0, _player)
	var pickups_after: Dictionary = _pickup_snapshot()
	var new_pickups: Array[Node] = _new_pickups(pickups_before, pickups_after)

	_check(bool(boss.get("_dead")), "El jefe muere por la ruta real de dano")
	_check(_same_counts(
			_inventory_counts(["scrap", "medkit", "pistol_ammo", "shotgun_ammo", "rifle_ammo"]),
			inventory_before),
		"La muerte del zombi no concede ninguna recompensa directamente")
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
	_check(_all_ids_allowed(new_pickups),
		"Toda recompensa usa un ID de botin permitido")
	_check(_all_amounts_positive(new_pickups),
		"Toda recompensa contiene una cantidad positiva")
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
	_check(medkit_pickups.size() == 1
			and _amount_in_range(medkit_pickups[0], 1, 2),
		"La pickup de botiquin conserva la cantidad original de 1-2")

	var drop_root: Node = _main.get_node_or_null("ZombieDrops")
	_check(drop_root != null, "Main crea una raiz persistente para el botin de zombis")
	_check(drop_root != null and drop_root.is_in_group("zombie_drop_root"),
		"La raiz de botin de zombis es resoluble por su grupo")
	_check(_all_below_root(new_pickups, drop_root),
		"Todas las recompensas fisicas pertenecen a la raiz persistente")
	_check(not _all_below_root(new_pickups, _foreign_drop_root),
		"La raiz persistente de la escena actual tiene prioridad sobre otros grupos")

	var scrap_amount: int = 0
	if scrap_pickups.size() == 1:
		var scrap_pickup: Node = scrap_pickups[0]
		scrap_amount = int(scrap_pickup.get("amount"))
		_check(scrap_amount >= 5 and scrap_amount <= 8,
			"La pickup de chatarra conserva la cantidad original de 5-8")
		_check(_missing_asset_is_honest(scrap_pickup),
			"La recompensa sin icono declara exactamente FALTA ASSET - NO INVENTAR")
	else:
		scrap_amount = 0

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

	await _exercise_boss_rng_matrix()
	await _exercise_forest_cleanup()
	await _exercise_horde_cleanup()
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


func _all_ids_allowed(pickups: Array[Node]) -> bool:
	for node in pickups:
		if not is_instance_valid(node):
			return false
		if not ALLOWED_BOSS_REWARD_IDS.has(String(node.get("item_id"))):
			return false
	return true


func _all_amounts_positive(pickups: Array[Node]) -> bool:
	for node in pickups:
		if not is_instance_valid(node) or int(node.get("amount")) <= 0:
			return false
	return true


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
	var visual: Polygon2D = pickup.get_node_or_null("Visual") as Polygon2D
	var icon: Sprite2D = pickup.get_node_or_null("ItemIcon") as Sprite2D
	return missing != null and missing.visible \
			and missing.text == MISSING_ASSET_TEXT \
			and visual != null and not visual.visible \
			and icon != null and not icon.visible


func _inventory_counts(item_ids: Array[String]) -> Dictionary:
	var counts: Dictionary = {}
	for item_id in item_ids:
		counts[item_id] = Inventory.count(item_id)
	return counts


func _same_counts(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for item_id in expected.keys():
		if not actual.has(item_id) or int(actual[item_id]) != int(expected[item_id]):
			return false
	return true


func _reward_amounts(pickups: Array[Node]) -> Dictionary:
	var amounts: Dictionary = {}
	for node in pickups:
		if not is_instance_valid(node):
			continue
		var item_id: String = String(node.get("item_id"))
		if amounts.has(item_id):
			amounts[item_id] = -1
		else:
			amounts[item_id] = int(node.get("amount"))
	return amounts


func _same_amounts(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for item_id in expected.keys():
		if not actual.has(item_id) or int(actual[item_id]) != int(expected[item_id]):
			return false
	return true


func _exercise_collection(pickup: Node, original_amount: int) -> void:
	if not Inventory.item_picked_up.is_connected(_on_item_picked_up):
		Inventory.item_picked_up.connect(_on_item_picked_up)
	var collection_position: Vector2 = pickup.global_position
	_player.global_position = collection_position
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

	var remaining_amount: int = original_amount - accepted_first
	# La pila ya contiene 60 unidades. Para que TODO el resto quepa en una
	# segunda recogida se liberan exactamente esas unidades, nunca mas.
	_check(Inventory.remove_item("scrap", remaining_amount),
		"Se libera capacidad suficiente para el resto pendiente")
	_player.global_position = Vector2(-120000.0, -120000.0)
	await get_tree().physics_frame
	_player.global_position = collection_position
	for _i in range(4):
		await get_tree().physics_frame

	_check(Inventory.count("scrap") == SCRAP_STACK_LIMIT,
		"La segunda recogida entrega todo el resto pendiente")
	_check(not is_instance_valid(pickup),
		"La pickup se elimina cuando ya no queda contenido")
	_check(_scrap_pickup_events.size() == 2
			and _scrap_pickup_events[0] + _scrap_pickup_events[1] == original_amount,
		"Ninguna unidad se concede dos veces")

	# La comprobacion anterior era vacua con la pila llena: un reintento se
	# rechazaria por capacidad. Se abre espacio y se vuelve a entrar para que
	# una posible concesion duplicada sea observable.
	_check(Inventory.remove_item("scrap", 10),
		"Se abre capacidad para observar un posible reintento")
	_player.global_position = Vector2(-120000.0, -120000.0)
	await get_tree().physics_frame
	_player.global_position = collection_position
	for _i in range(4):
		await get_tree().physics_frame

	_check(Inventory.count("scrap") == SCRAP_STACK_LIMIT - 10,
		"La recompensa no vuelve a concederse despues de recogerse")
	_check(_pickups_with_id(_all_pickups(), "scrap").is_empty(),
		"No queda ninguna pickup de chatarra tras la recogida completa")


func _exercise_boss_rng_matrix() -> void:
	for case_data in BOSS_BRANCH_CASES:
		var seed_value: int = int(case_data.get("seed", DEFAULT_MASTER_SEED))
		var label: String = String(case_data.get("label", "rama de jefe"))
		var expected: Dictionary = case_data.get("rewards", {}) as Dictionary
		GameState.reset_rngs(seed_value)
		var inventory_before: Dictionary = _inventory_counts([
			"scrap", "medkit", "pistol_ammo", "shotgun_ammo", "rifle_ammo",
		])
		var pickups_before: Dictionary = _pickup_snapshot()
		var boss: CharacterBody2D = _make_boss()
		boss.name = "ZombieDropMatrixBoss"
		_main.add_child(boss)
		await get_tree().process_frame
		boss.call("_drop_loot")
		var pickups: Array[Node] = _new_pickups(pickups_before, _pickup_snapshot())

		_check(_all_ids_allowed(pickups),
			"La matriz del jefe solo crea IDs permitidos (%s)" % label)
		_check(_all_amounts_positive(pickups),
			"La matriz del jefe solo crea cantidades positivas (%s)" % label)
		_check(_same_amounts(_reward_amounts(pickups), expected),
			"La matriz RNG del jefe conserva IDs y cantidades exactas (%s)" % label)
		_check(_same_counts(
				_inventory_counts(["scrap", "medkit", "pistol_ammo", "shotgun_ammo", "rifle_ammo"]),
				inventory_before),
			"La matriz del jefe no muta el inventario (%s)" % label)

		boss.queue_free()
		for pickup in pickups:
			if is_instance_valid(pickup):
				pickup.queue_free()
		await get_tree().process_frame
	GameState.reset_rngs(DEFAULT_MASTER_SEED)


func _exercise_forest_cleanup() -> void:
	var forest: Node2D = _main.get_node_or_null("ForestZombies") as Node2D
	_check(forest != null, "Main crea el gestor real de zombis del bosque")
	if forest == null:
		return
	var boss: CharacterBody2D = _make_boss()
	boss.name = "ZombieDropForestBoss"
	forest.add_child(boss)
	boss.global_position = Vector2(110000.0, 110000.0)
	var spawned: Array = forest.get("_spawned")
	spawned.append(boss)
	await get_tree().process_frame

	var pickups_before: Dictionary = _pickup_snapshot()
	boss.take_damage(10000.0, _player)
	var pickups: Array[Node] = _new_pickups(pickups_before, _pickup_snapshot())
	forest.call("_clear_zombies")
	await get_tree().process_frame

	_check(not is_instance_valid(boss),
		"La limpieza del bosque libera sus zombis")
	_check(pickups.size() >= 2 and _all_valid(pickups),
		"La recompensa del bosque sobrevive a su limpieza")
	_check(_all_below_root(pickups, _main.get_node_or_null("ZombieDrops")),
		"La recompensa del bosque conserva el propietario persistente")
	for pickup in pickups:
		if is_instance_valid(pickup):
			pickup.queue_free()
	await get_tree().process_frame


func _exercise_horde_cleanup() -> void:
	var director: Node = _main.get_node_or_null("WaveManager")
	_check(director != null, "Main crea el WorldDirector real")
	if director == null:
		return
	var boss: CharacterBody2D = _make_boss()
	boss.name = "ZombieDropHordeBoss"
	director.add_child(boss)
	boss.global_position = Vector2(120000.0, 120000.0)
	var horde: Array = director.get("_horde_zombies")
	horde.append(boss)
	await get_tree().process_frame

	var pickups_before: Dictionary = _pickup_snapshot()
	boss.take_damage(10000.0, _player)
	var pickups: Array[Node] = _new_pickups(pickups_before, _pickup_snapshot())
	director.call("_clear_horde_zombies", false)
	await get_tree().process_frame

	_check(not is_instance_valid(boss),
		"La limpieza de horda libera sus zombis")
	_check(pickups.size() >= 2 and _all_valid(pickups),
		"La recompensa de horda sobrevive a su limpieza")
	_check(_all_below_root(pickups, _main.get_node_or_null("ZombieDrops")),
		"La recompensa de horda conserva el propietario persistente")
	for pickup in pickups:
		if is_instance_valid(pickup):
			pickup.queue_free()
	await get_tree().process_frame


func _all_pickups() -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group("pickups"):
		if is_instance_valid(node):
			result.append(node)
	return result


func _all_valid(pickups: Array[Node]) -> bool:
	for pickup in pickups:
		if not is_instance_valid(pickup):
			return false
	return true


func _on_item_picked_up(item_id: String, amount: int) -> void:
	if item_id == "scrap":
		_scrap_pickup_events.append(amount)


func _finish() -> void:
	if Inventory.item_picked_up.is_connected(_on_item_picked_up):
		Inventory.item_picked_up.disconnect(_on_item_picked_up)
	if is_instance_valid(_main):
		_main.queue_free()
		_main = null
	if is_instance_valid(_foreign_drop_root):
		_foreign_drop_root.queue_free()
		_foreign_drop_root = null
	for _i in range(3):
		await get_tree().process_frame
	print("ZOMBIE_DROP_TEST failures=%d" % _failures.size())
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)
