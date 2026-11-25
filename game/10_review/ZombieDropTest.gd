extends Node
## ============================================================================
## ZOMBIE DROP TEST — la recompensa del zombi es un objeto físico recogible.
## ============================================================================
## Esta puerta ejercita la ruta real de muerte y el contrato completo del
## botín: el inventario no cambia al morir, cada recompensa aparece como
## Pickup, la matriz determinista fija la politica de municion del jefe, el
## objeto sobrevive al cadaver y a los ciclos reales de bosque/horda, una
## aceptacion parcial conserva el resto y una recogida nunca duplica unidades.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")
const ZOMBIE_SCENE: PackedScene = preload("res://03_zombies/Zombie.tscn")

const BOSS_KIND: int = 1
const NEAR_CAPACITY: int = 57
const SCRAP_STACK_LIMIT: int = 60
const MISSING_ASSET_TEXT: String = "FALTA ASSET - NO INVENTAR"
const ALLOWED_BOSS_REWARD_IDS: Array[String] = [
	"scrap", "medkit", "pistol_ammo", "shotgun_ammo", "rifle_ammo",
]
const BOSS_REWARD_RANGES: Dictionary = {
	"scrap": Vector2i(5, 8),
	"medkit": Vector2i(1, 2),
	"pistol_ammo": Vector2i(12, 24),
	"shotgun_ammo": Vector2i(6, 12),
	"rifle_ammo": Vector2i(12, 24),
}
const WALKER_REWARD_RANGES: Dictionary = {
	"scrap": Vector2i(1, 1),
	"cloth": Vector2i(1, 1),
	"pistol_ammo": Vector2i(2, 6),
	"shotgun_ammo": Vector2i(2, 4),
	"rifle_ammo": Vector2i(4, 8),
}
## Semillas frontera -> roll compartido -> IDs y cantidades exactos. Cada
## umbral 0,30/0,50/0,70 tiene una muestra inmediatamente debajo y encima.
const BOSS_BRANCH_CASES: Array[Dictionary] = [
	{
		"seed": 2592291,
		"roll": 0.299999743700,
		"label": "justo debajo de 0,30: pistola + escopeta + fusil",
		"rewards": {
			"scrap": 8, "pistol_ammo": 12, "shotgun_ammo": 10,
			"rifle_ammo": 19, "medkit": 2,
		},
	},
	{
		"seed": 2639706,
		"roll": 0.300000071526,
		"label": "justo encima de 0,30: pistola + escopeta",
		"rewards": {"scrap": 8, "pistol_ammo": 18, "shotgun_ammo": 9, "medkit": 2},
	},
	{
		"seed": 547937,
		"roll": 0.499999880791,
		"label": "justo debajo de 0,50: pistola + escopeta",
		"rewards": {"scrap": 5, "pistol_ammo": 17, "shotgun_ammo": 9, "medkit": 1},
	},
	{
		"seed": 1585036,
		"roll": 0.500000178814,
		"label": "justo encima de 0,50: solo pistola",
		"rewards": {"scrap": 6, "pistol_ammo": 22, "medkit": 2},
	},
	{
		"seed": 403054,
		"roll": 0.699999868870,
		"label": "justo debajo de 0,70: solo pistola",
		"rewards": {"scrap": 8, "pistol_ammo": 17, "medkit": 1},
	},
	{
		"seed": 1299245,
		"roll": 0.700000047684,
		"label": "justo encima de 0,70: sin municion",
		"rewards": {"scrap": 6, "medkit": 2},
	},
]

## Matriz exacta del caminante. El orden de draws es: material (0,18),
## split scrap/tela (0,60) solo si hubo material y municion (0,08/0,12/0,15).
## Cada umbral tiene una muestra inmediata debajo y encima.
const WALKER_BRANCH_CASES: Array[Dictionary] = [
	{
		"seed": 71992855,
		"material_roll": 0.179999679327011,
		"split_roll": 0.932130336761475,
		"ammo_roll": 0.757405042648315,
		"label": "material justo debajo de 0,18: tela",
		"rewards": {"cloth": 1},
	},
	{
		"seed": 73709094,
		"material_roll": 0.180000498890877,
		"split_roll": -1.0,
		"ammo_roll": 0.663103103637695,
		"label": "material justo encima de 0,18: sin material",
		"rewards": {},
	},
	{
		"seed": 80196757,
		"material_roll": 0.110469706356525,
		"split_roll": 0.599999964237213,
		"ammo_roll": 0.740165889263153,
		"label": "split justo debajo de 0,60: chatarra",
		"rewards": {"scrap": 1},
	},
	{
		"seed": 90640042,
		"material_roll": 0.114339120686054,
		"split_roll": 0.600000381469727,
		"ammo_roll": 0.186253398656845,
		"label": "split justo encima de 0,60: tela",
		"rewards": {"cloth": 1},
	},
	{
		"seed": 71599343,
		"material_roll": 0.380890697240829,
		"split_roll": -1.0,
		"ammo_roll": 0.079999707639217,
		"label": "municion justo debajo de 0,08: pistola",
		"rewards": {"pistol_ammo": 3},
	},
	{
		"seed": 71719984,
		"material_roll": 0.401184171438217,
		"split_roll": -1.0,
		"ammo_roll": 0.080000311136246,
		"label": "municion justo encima de 0,08: escopeta",
		"rewards": {"shotgun_ammo": 2},
	},
	{
		"seed": 74476158,
		"material_roll": 0.660870373249054,
		"split_roll": -1.0,
		"ammo_roll": 0.119999669492245,
		"label": "municion justo debajo de 0,12: escopeta",
		"rewards": {"shotgun_ammo": 3},
	},
	{
		"seed": 71845937,
		"material_roll": 0.808587372303009,
		"split_roll": -1.0,
		"ammo_roll": 0.120000027120113,
		"label": "municion justo encima de 0,12: fusil",
		"rewards": {"rifle_ammo": 8},
	},
	{
		"seed": 72595980,
		"material_roll": 0.427841901779175,
		"split_roll": -1.0,
		"ammo_roll": 0.149999707937241,
		"label": "municion justo debajo de 0,15: fusil",
		"rewards": {"rifle_ammo": 7},
	},
	{
		"seed": 68068886,
		"material_roll": 0.441972225904465,
		"split_roll": -1.0,
		"ammo_roll": 0.150000080466270,
		"label": "municion justo encima de 0,15: sin recompensa",
		"rewards": {},
	},
	{
		"seed": 71813614,
		"material_roll": 0.064877346158028,
		"split_roll": 0.419527769088745,
		"ammo_roll": 0.041581209748983,
		"label": "material y pistola comparten el mismo stream",
		"rewards": {"scrap": 1, "pistol_ammo": 5},
	},
	{
		"seed": 71813463,
		"material_roll": 0.001634263666347,
		"split_roll": 0.887996613979340,
		"ammo_roll": 0.081622533500195,
		"label": "material y escopeta comparten el mismo stream",
		"rewards": {"cloth": 1, "shotgun_ammo": 4},
	},
	{
		"seed": 71813565,
		"material_roll": 0.107130177319050,
		"split_roll": 0.354757159948349,
		"ammo_roll": 0.141732335090637,
		"label": "material y fusil comparten el mismo stream",
		"rewards": {"scrap": 1, "rifle_ammo": 8},
	},
	{
		"seed": 71813510,
		"material_roll": 0.329559087753296,
		"split_roll": -1.0,
		"ammo_roll": 0.276594847440720,
		"label": "caminante sin recompensa",
		"rewards": {},
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
	var inventory_before: Dictionary = Inventory.items()
	var boss: CharacterBody2D = _make_boss()
	_main.add_child(boss)
	boss.global_position = Vector2(100000.0, 100000.0)
	await get_tree().process_frame
	await get_tree().physics_frame

	boss.take_damage(10000.0, _player)
	var pickups_after: Dictionary = _pickup_snapshot()
	var new_pickups: Array[Node] = _new_pickups(pickups_before, pickups_after)

	_check(bool(boss.get("_dead")), "El jefe muere por la ruta real de dano")
	_check(_same_inventory(Inventory.items(), inventory_before),
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
	_check(_all_amounts_in_ranges(new_pickups),
		"Toda recompensa conserva su rango original")
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
	_check(not new_pickups.is_empty()
			and not _all_below_root(new_pickups, _foreign_drop_root),
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

	# El cadaver ahora permanece en el mundo durante dos dias de juego. La
	# pickup debe sobrevivir a su animacion y conservar la recompensa pendiente.
	for _i in range(100):
		await get_tree().physics_frame
	_check(is_instance_valid(boss), "El cadaver permanece tras su animacion de muerte")
	_check(scrap_pickups.size() == 1 and is_instance_valid(scrap_pickups[0]),
		"La recompensa fisica sobrevive al final de la animacion del cadaver")
	_check(scrap_pickups.size() == 1
			and int(scrap_pickups[0].get("amount")) == scrap_amount,
		"La cantidad pendiente no cambia mientras nadie la recoge")

	if scrap_pickups.size() == 1 and is_instance_valid(scrap_pickups[0]):
		await _exercise_collection(scrap_pickups[0], scrap_amount)

	await _exercise_boss_rng_matrix()
	_check_walker_policy_constants()
	await _exercise_walker_rng_matrix()
	await _exercise_queued_stale_root()
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


func _make_walker() -> CharacterBody2D:
	var walker: CharacterBody2D = ZOMBIE_SCENE.instantiate() as CharacterBody2D
	walker.name = "ZombieDropWalker"
	walker.set("kind", 0)
	walker.set("speed", 0.0)
	walker.set("detect_radius", 0.0)
	walker.set("close_sense_radius", 0.0)
	walker.set("lose_radius", 0.0)
	return walker


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
	if pickups.is_empty():
		return false
	for node in pickups:
		if not is_instance_valid(node):
			return false
		if not ALLOWED_BOSS_REWARD_IDS.has(String(node.get("item_id"))):
			return false
	return true


func _all_amounts_positive(pickups: Array[Node]) -> bool:
	if pickups.is_empty():
		return false
	for node in pickups:
		if not is_instance_valid(node) or int(node.get("amount")) <= 0:
			return false
	return true


func _all_amounts_in_ranges(pickups: Array[Node]) -> bool:
	if pickups.is_empty():
		return false
	for node in pickups:
		if not is_instance_valid(node):
			return false
		var item_id: String = String(node.get("item_id"))
		if not BOSS_REWARD_RANGES.has(item_id):
			return false
		var limits: Vector2i = BOSS_REWARD_RANGES[item_id]
		var amount: int = int(node.get("amount"))
		if amount < limits.x or amount > limits.y:
			return false
	return true


func _all_walker_amounts_in_ranges(pickups: Array[Node]) -> bool:
	if pickups.is_empty():
		return false
	for node in pickups:
		if not is_instance_valid(node):
			return false
		var item_id: String = String(node.get("item_id"))
		if not WALKER_REWARD_RANGES.has(item_id):
			return false
		var limits: Vector2i = WALKER_REWARD_RANGES[item_id]
		var amount: int = int(node.get("amount"))
		if amount < limits.x or amount > limits.y:
			return false
	return true


func _all_below_root(pickups: Array[Node], root: Node) -> bool:
	if root == null or pickups.is_empty():
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


func _same_inventory(actual: Dictionary, expected: Dictionary) -> bool:
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
	if actual.is_empty() or expected.is_empty():
		return false
	if actual.size() != expected.size():
		return false
	for item_id in expected.keys():
		if not actual.has(item_id) or int(actual[item_id]) != int(expected[item_id]):
			return false
	return true


## Compara un mapa de recompensa que permite estar vacio. Se usa para las ramas del
## caminante donde no dropear nada es un resultado valido y debe distinguirse
## de una prueba que nunca llego a ejecutarse.
func _same_reward_map(actual: Dictionary, expected: Dictionary) -> bool:
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
	_check(_scrap_pickup_events.size() == 2,
		"No se emite una tercera recogida de chatarra")
	_check(_pickups_with_id(_all_pickups(), "scrap").is_empty(),
		"No queda ninguna pickup de chatarra tras la recogida completa")


func _exercise_boss_rng_matrix() -> void:
	for case_data in BOSS_BRANCH_CASES:
		var seed_value: int = int(case_data.get("seed", GameState.MASTER_SEED))
		var label: String = String(case_data.get("label", "rama de jefe"))
		var expected_roll: float = float(case_data.get("roll", -1.0))
		var expected: Dictionary = case_data.get("rewards", {}) as Dictionary
		GameState.reset_rngs(seed_value)
		var production_rng: RandomNumberGenerator = GameState.rng(&"loot")
		var roll_probe := RandomNumberGenerator.new()
		roll_probe.state = production_rng.state
		roll_probe.randi_range(5, 8)
		var actual_roll: float = roll_probe.randf()
		_check(absf(actual_roll - expected_roll) < 0.000000001,
			"La matriz reproduce el roll compartido exacto (%s)" % label)

		var inventory_before: Dictionary = Inventory.items()
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
		_check(_all_amounts_in_ranges(pickups),
			"La matriz del jefe conserva los rangos originales (%s)" % label)
		_check(_same_amounts(_reward_amounts(pickups), expected),
			"La matriz RNG del jefe conserva IDs y cantidades exactas (%s)" % label)
		_check(_same_inventory(Inventory.items(), inventory_before),
			"La matriz del jefe no muta el inventario (%s)" % label)

		boss.queue_free()
		for pickup in pickups:
			if is_instance_valid(pickup):
				pickup.queue_free()
		await get_tree().process_frame
	GameState.reset_rngs(GameState.MASTER_SEED)


func _check_walker_policy_constants() -> void:
	var zombie_script: Script = load("res://03_zombies/Zombie.gd") as Script
	var constants: Dictionary = {}
	if zombie_script != null:
		constants = zombie_script.get_script_constant_map()
	var expected: Dictionary = {
		"WALKER_MATERIAL_CHANCE": 0.18,
		"WALKER_SCRAP_CHANCE": 0.60,
		"WALKER_PISTOL_CHANCE": 0.08,
		"WALKER_SHOTGUN_CHANCE": 0.12,
		"WALKER_RIFLE_CHANCE": 0.15,
	}
	for constant_name in expected.keys():
		_check(constants.has(constant_name)
				and absf(float(constants[constant_name]) - float(expected[constant_name])) < 0.000000001,
			"La politica del caminante conserva la constante %s" % constant_name)


func _exercise_walker_rng_matrix() -> void:
	for case_data in WALKER_BRANCH_CASES:
		var seed_value: int = int(case_data.get("seed", GameState.MASTER_SEED))
		var label: String = String(case_data.get("label", "rama de caminante"))
		var expected_material: float = float(case_data.get("material_roll", -1.0))
		var expected_split: float = float(case_data.get("split_roll", -1.0))
		var expected_ammo: float = float(case_data.get("ammo_roll", -1.0))
		var expected: Dictionary = case_data.get("rewards", {}) as Dictionary

		GameState.reset_rngs(seed_value)
		var production_rng: RandomNumberGenerator = GameState.rng(&"loot")
		var draw_probe := RandomNumberGenerator.new()
		draw_probe.state = production_rng.state
		var actual_material: float = draw_probe.randf()
		var actual_split: float = -1.0
		if actual_material < 0.18:
			actual_split = draw_probe.randf()
		var actual_ammo: float = draw_probe.randf()
		_check(absf(actual_material - expected_material) < 0.000000001,
			"La matriz reproduce el roll de material exacto (%s)" % label)
		_check(absf(actual_split - expected_split) < 0.000000001,
			"La matriz reproduce el roll de split exacto (%s)" % label)
		_check(absf(actual_ammo - expected_ammo) < 0.000000001,
			"La matriz reproduce el roll de municion exacto (%s)" % label)

		var inventory_before: Dictionary = Inventory.items()
		var pickups_before: Dictionary = _pickup_snapshot()
		var walker: CharacterBody2D = _make_walker()
		walker.name = "ZombieDropMatrixWalker"
		_main.add_child(walker)
		walker.global_position = Vector2(100000.0, 100000.0)
		await get_tree().process_frame
		walker.call("_drop_loot")
		var pickups: Array[Node] = _new_pickups(pickups_before, _pickup_snapshot())

		_check(_same_reward_map(_reward_amounts(pickups), expected),
			"La matriz RNG del caminante conserva IDs y cantidades exactas (%s)" % label)
		_check(_same_inventory(Inventory.items(), inventory_before),
			"La matriz del caminante no muta el inventario (%s)" % label)
		if expected.is_empty():
			_check(pickups.is_empty(),
				"La rama sin recompensa no crea ninguna pickup (%s)" % label)
		else:
			_check(_all_amounts_positive(pickups),
				"La matriz del caminante solo crea cantidades positivas (%s)" % label)
			_check(_all_walker_amounts_in_ranges(pickups),
				"La matriz del caminante conserva los rangos originales (%s)" % label)

		walker.queue_free()
		for pickup in pickups:
			if is_instance_valid(pickup):
				pickup.queue_free()
		await get_tree().process_frame
	GameState.reset_rngs(GameState.MASTER_SEED)


func _exercise_queued_stale_root() -> void:
	var original_scene: Node = get_tree().current_scene
	var isolated_scene := Node2D.new()
	isolated_scene.name = "QueuedRootProbeScene"
	get_tree().root.add_child(isolated_scene)
	get_tree().current_scene = isolated_scene

	var stale_root := Node2D.new()
	stale_root.name = "QueuedZombieDrops"
	stale_root.add_to_group("zombie_drop_root")
	isolated_scene.add_child(stale_root)
	stale_root.queue_free()

	var inventory_before: Dictionary = Inventory.items()
	var pickups_before: Dictionary = _pickup_snapshot()
	var boss: CharacterBody2D = _make_boss()
	boss.name = "QueuedRootProbeBoss"
	isolated_scene.add_child(boss)
	boss.call("_drop_loot")
	var pickups: Array[Node] = _new_pickups(pickups_before, _pickup_snapshot())
	var fallback: Node = isolated_scene.get_node_or_null("ZombieDropsFallback")

	_check(stale_root.is_queued_for_deletion(),
		"La raiz de grupo obsoleta esta pendiente de liberacion")
	_check(pickups.size() >= 2,
		"La raiz pendiente no puede recibir las recompensas")
	_check(fallback != null,
		"El mundo actual crea una raiz de botin valida de reemplazo")
	_check(fallback != null and _all_below_root(pickups, fallback),
		"Las recompensas pertenecen a la raiz valida de reemplazo")
	_check(not _all_below_root(pickups, stale_root),
		"Ninguna recompensa pertenece a la raiz pendiente de liberacion")
	_check(_same_inventory(Inventory.items(), inventory_before),
		"La prueba de raiz obsoleta no concede botin directamente")

	for pickup in pickups:
		if is_instance_valid(pickup):
			pickup.queue_free()
	get_tree().current_scene = original_scene
	isolated_scene.queue_free()
	await get_tree().process_frame


func _exercise_forest_cleanup() -> void:
	var forest: Node2D = _main.get_node_or_null("ForestZombies") as Node2D
	_check(forest != null, "Main crea el gestor real de zombis del bosque")
	if forest == null:
		return
	EventBus.forest_entered.emit()
	await get_tree().process_frame
	var forest_actors: Array[CharacterBody2D] = _actors_with_meta(forest, "forest_zombie")
	_check(forest_actors.size() >= 2,
		"La entrada al bosque crea varios zombis reales")
	if forest_actors.is_empty():
		return
	var boss: CharacterBody2D = forest_actors[0]
	boss.set("kind", BOSS_KIND)
	boss.call("_apply_kind")
	var inventory_before: Dictionary = Inventory.items()
	var pickups_before: Dictionary = _pickup_snapshot()

	boss.take_damage(10000.0, _player)
	var pickups: Array[Node] = _new_pickups(pickups_before, _pickup_snapshot())
	var amounts_before: Dictionary = _reward_amounts(pickups)
	_check(_same_inventory(Inventory.items(), inventory_before),
		"El zombi real del bosque no concede botin directamente")
	_check(pickups.size() >= 2 and _all_valid(pickups),
		"El zombi real del bosque deja recompensas fisicas")
	var forest_survivors: Array[CharacterBody2D] = []
	for actor in forest_actors:
		if actor != boss:
			forest_survivors.append(actor)

	EventBus.forest_exited.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_all_invalid(forest_survivors),
		"La salida del bosque libera sus zombis reales")
	_check(_all_valid(pickups),
		"La recompensa del bosque sobrevive a la salida real")
	_check(_same_amounts(_reward_amounts(pickups), amounts_before),
		"La recompensa del bosque conserva su cantidad pendiente")
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
	director.call("force_phase", "night")
	EventBus.forest_entered.emit()
	await get_tree().process_frame
	director.call("trigger_horde")
	await get_tree().process_frame
	await get_tree().process_frame
	var horde_actors: Array[CharacterBody2D] = _actors_with_meta(director, "horde_zombie")
	_check(horde_actors.size() >= 2,
		"La horda real crea varios zombis reales")
	_check(int(director.call("horde_size")) == horde_actors.size(),
		"La horda real conserva su lista de zombis")
	if horde_actors.is_empty():
		return
	var boss: CharacterBody2D = horde_actors[0]
	var horde_survivors: Array[CharacterBody2D] = []
	for actor in horde_actors:
		if actor != boss:
			horde_survivors.append(actor)
	boss.set("kind", BOSS_KIND)
	boss.call("_apply_kind")
	var inventory_before: Dictionary = Inventory.items()
	var pickups_before: Dictionary = _pickup_snapshot()

	boss.take_damage(10000.0, _player)
	var pickups: Array[Node] = _new_pickups(pickups_before, _pickup_snapshot())
	var amounts_before: Dictionary = _reward_amounts(pickups)
	_check(_same_inventory(Inventory.items(), inventory_before),
		"El zombi real de horda no concede botin directamente")
	_check(pickups.size() >= 2 and _all_valid(pickups),
		"El zombi real de horda deja recompensas fisicas")

	director.call("_end_horde")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_all_invalid(horde_survivors),
		"La dispersion real de horda libera sus zombis vivos")
	_check(is_instance_valid(boss),
		"El cadaver de la horda sobrevive a la dispersion")
	_check(int(director.call("horde_size")) == 0
			and not bool(director.call("is_horde_active")),
		"La horda real queda cerrada y vacia")
	_check(_all_valid(pickups),
		"La recompensa de horda sobrevive a la dispersion real")
	_check(_same_amounts(_reward_amounts(pickups), amounts_before),
		"La recompensa de horda conserva su cantidad pendiente")
	_check(_all_below_root(pickups, _main.get_node_or_null("ZombieDrops")),
		"La recompensa de horda conserva el propietario persistente")
	for pickup in pickups:
		if is_instance_valid(pickup):
			pickup.queue_free()
	EventBus.forest_exited.emit()
	await get_tree().process_frame


func _actors_with_meta(parent: Node, meta_name: String) -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	for child in parent.get_children():
		if child is CharacterBody2D and bool(child.get_meta(meta_name, false)):
			result.append(child as CharacterBody2D)
	return result


func _all_pickups() -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group("pickups"):
		if is_instance_valid(node):
			result.append(node)
	return result


func _all_valid(pickups: Array[Node]) -> bool:
	if pickups.is_empty():
		return false
	for pickup in pickups:
		if not is_instance_valid(pickup):
			return false
	return true


func _all_invalid(instances: Array[CharacterBody2D]) -> bool:
	if instances.is_empty():
		return false
	for instance in instances:
		if is_instance_valid(instance):
			return false
	return true


func _on_item_picked_up(item_id: String, amount: int) -> void:
	if item_id == "scrap":
		_scrap_pickup_events.append(amount)


func _finish() -> void:
	GameState.reset_rngs(GameState.MASTER_SEED)
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
