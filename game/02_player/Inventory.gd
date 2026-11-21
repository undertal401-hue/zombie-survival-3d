extends Node

## Economía del juego: objetos con categoría, apilado con límite, capacidad por
## peso/tipo, crafting y tablas de botín por rareza.
## API pública nueva: can_add_item, current_weight, category, get_condition,
## degrade_item, repair_item, condition_factor, can_craft, craft, roll_loot.

signal inventory_changed
## Señal local de crafting (EventBus puede no tenerla aún: ver _emit_craft_signal).
signal crafting_completed(item_id: String, amount: int)
signal item_rejected(item_id: String, reason: String)
## Se emite cuando el jugador recoge un objeto al inventario (para mostrar su sprite).
signal item_picked_up(item_id: String, amount: int)

const MAX_SLOTS := 16
const MAX_WEIGHT := 200.0
const MAX_STACK := 99

const CAT_FOOD := "consumible"
const CAT_MEDICAL := "medico"
const CAT_AMMO := "municion"
const CAT_FUEL := "combustible"
const CAT_MATERIAL := "material"
const CAT_KEY := "clave"
const CAT_MISC := "misc"

## id -> presentación, categoría, tope de pila y peso por unidad (kg).
## `combustible` se conserva: el objetivo de extracción y QA lo usan.
## `vehicle_fuel` es un id NUEVO para el crafting / repostaje de vehículos.
const ITEM_DEFS: Dictionary = {
	"comida": {"name": "Comida enlatada", "category": CAT_FOOD, "stack": 30, "weight": 0.6, "icon": "res://assets/items/comida.png"},
	"medkit": {"name": "Botiquín", "category": CAT_MEDICAL, "stack": 12, "weight": 0.8, "icon": "res://assets/items/medkit.png"},
	"pistol_ammo": {"name": "Cartucho 9mm (12 balas)", "category": CAT_AMMO, "stack": 240, "weight": 0.02, "icon": "res://assets/items/pistol_ammo.png"},
	"rifle_ammo": {"name": "Cartucho 5.56mm (30 balas)", "category": CAT_AMMO, "stack": 300, "weight": 0.02, "icon": "res://assets/items/rifle_ammo.png"},
	"shotgun_ammo": {"name": "Cartucho 12ga (6 balas)", "category": CAT_AMMO, "stack": 120, "weight": 0.04, "icon": "res://assets/items/shotgun_ammo.png"},
	"Machete": {"name": "Machete", "category": CAT_MISC, "stack": 1, "weight": 1.2, "icon": "res://assets/items/machete.png"},
	"Pistola 9mm": {"name": "Pistola 9mm", "category": CAT_MISC, "stack": 1, "weight": 1.0, "icon": "res://assets/items/pistol.png"},
	"Escopeta 12ga": {"name": "Escopeta 12ga", "category": CAT_MISC, "stack": 1, "weight": 3.2, "icon": "res://assets/items/shotgun.png"},
	"Fusil 5.56mm": {"name": "Fusil 5.56mm", "category": CAT_MISC, "stack": 1, "weight": 3.5, "icon": "res://assets/items/rifle.png"},
	"combustible": {"name": "Bidón de combustible", "category": CAT_FUEL, "stack": 12, "weight": 5.0, "icon": "res://assets/items/combustible.png"},
	"scrap": {"name": "Chatarra", "category": CAT_MATERIAL, "stack": 60, "weight": 0.4, "icon": "res://assets/items/scrap.png"},
	"cloth": {"name": "Tela", "category": CAT_MATERIAL, "stack": 60, "weight": 0.15, "icon": "res://assets/items/cloth.png"},
	"vehicle_fuel": {"name": "Combustible de vehículo", "category": CAT_FUEL, "stack": 20, "weight": 2.5, "icon": "res://assets/items/vehicle_fuel.png"},
	"llave": {"name": "Llave", "category": CAT_KEY, "stack": 1, "weight": 0.05, "icon": "res://assets/items/llave.png"},
}

## Recetas: id -> objeto producido, cantidad y coste. El coste de `pistol_ammo` da una
## recarga completa (12 balas); las demás producen una unidad.
const RECIPES: Dictionary = {
	"medkit": {"output": "medkit", "amount": 1, "cost": {"cloth": 2, "scrap": 1}},
	"pistol_ammo": {"output": "pistol_ammo", "amount": 12, "cost": {"scrap": 2, "cloth": 1}},
	"rifle_ammo": {"output": "rifle_ammo", "amount": 30, "cost": {"scrap": 3, "cloth": 2}},
	"shotgun_ammo": {"output": "shotgun_ammo", "amount": 6, "cost": {"scrap": 2, "cloth": 1}},
	"vehicle_fuel": {"output": "vehicle_fuel", "amount": 1, "cost": {"scrap": 2, "cloth": 1}},
}

## Botín por rareza. NUNCA aparece `combustible` aquí: los bidones del objetivo
## los coloca el mundo y QA cuenta 9 contenedores en 8 sectores.
const LOOT_TABLES: Dictionary = {
	"common": [
		{"id": "scrap", "min": 1, "max": 3, "weight": 42},
		{"id": "cloth", "min": 1, "max": 3, "weight": 34},
		{"id": "comida", "min": 1, "max": 1, "weight": 14},
		{"id": "pistol_ammo", "min": 12, "max": 24, "weight": 10},
		{"id": "shotgun_ammo", "min": 8, "max": 16, "weight": 8},
		{"id": "rifle_ammo", "min": 16, "max": 32, "weight": 8},
	],
	"uncommon": [
		{"id": "scrap", "min": 2, "max": 4, "weight": 30},
		{"id": "cloth", "min": 2, "max": 4, "weight": 25},
		{"id": "medkit", "min": 1, "max": 1, "weight": 20},
		{"id": "pistol_ammo", "min": 24, "max": 48, "weight": 20},
		{"id": "shotgun_ammo", "min": 16, "max": 28, "weight": 10},
		{"id": "rifle_ammo", "min": 32, "max": 56, "weight": 10},
		{"id": "vehicle_fuel", "min": 1, "max": 1, "weight": 5},
	],
	"rare": [
		{"id": "vehicle_fuel", "min": 1, "max": 1, "weight": 40},
		{"id": "medkit", "min": 1, "max": 2, "weight": 35},
		{"id": "pistol_ammo", "min": 48, "max": 72, "weight": 25},
		{"id": "shotgun_ammo", "min": 24, "max": 40, "weight": 14},
		{"id": "rifle_ammo", "min": 56, "max": 84, "weight": 14},
	],
}

## API pública de recetas (QA check 47 la lee desde /root/Inventory).
## Formato: {recipe_id: {"output": String, "amount": int, "cost": {id: int}}}
var recipes: Dictionary = RECIPES.duplicate(true)

var _items: Dictionary = {}
## Cache de iconos data-driven. Una ruta ausente devuelve null y no se inventa
## ninguna textura sustituta.
var _item_icon_cache: Dictionary = {}
## Condición 0..1 por id de objeto/herramienta; 1.0 = nueva.
var _conditions: Dictionary = {}
var _fallback_rng: RandomNumberGenerator

func _ready() -> void:
	_fallback_rng = RandomNumberGenerator.new()
	# Semilla fija: sin GameState el botín sigue siendo reproducible en tests.
	_fallback_rng.seed = 20261117

# ---------------------------------------------------------------------------
# Consulta / presentación
# ---------------------------------------------------------------------------

func _def(id: String) -> Dictionary:
	return ITEM_DEFS.get(id, {
		"name": id, "category": CAT_MISC, "stack": MAX_STACK, "weight": 0.5
	})

func display_name(id: String) -> String:
	return String(_def(id).get("name", id))


## Resuelve el sprite oficial de un objeto desde su ruta data-driven.
## `FALTA ASSET - NO INVENTAR`: si el archivo no existe devuelve null; jamás
## fabrica un rectangulo de color que se haga pasar por el sprite del objeto.
func get_item_texture(id: String) -> Texture2D:
	if _item_icon_cache.has(id):
		var cached: Texture2D = _item_icon_cache[id] as Texture2D
		if cached != null:
			return cached
	var path: String = String(_def(id).get("icon", ""))
	if path == "" or not ResourceLoader.exists(path, "Texture2D"):
		# Los fallos no se cachean: durante el editor el asset puede importarse
		# despues y debe poder resolverse sin reiniciar el proceso.
		return null
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		_item_icon_cache[id] = texture
	return texture

func get_category(id: String) -> String:
	return String(_def(id).get("category", CAT_MISC))

func category(id: String) -> String:
	return get_category(id)

func stack_limit(id: String) -> int:
	return maxi(int(_def(id).get("stack", MAX_STACK)), 1)

func unit_weight(id: String) -> float:
	return maxf(float(_def(id).get("weight", 0.5)), 0.0)

func current_weight() -> float:
	var total: float = 0.0
	for id in _items:
		total += unit_weight(String(id)) * float(_items[id])
	return total

func max_weight() -> float:
	return MAX_WEIGHT

func used_slots() -> int:
	return _items.size()

func max_slots() -> int:
	return MAX_SLOTS

func items() -> Dictionary:
	return _items.duplicate(true)

func count(id: String) -> int:
	return int(_items.get(id, 0))

func has(id: String) -> bool:
	return count(id) > 0

func total() -> int:
	var sum: int = 0
	for n in _items.values():
		sum += int(n)
	return sum

func clear() -> void:
	_items.clear()
	_conditions.clear()
	inventory_changed.emit()

# ---------------------------------------------------------------------------
# Altas / bajas con capacidad y razones de rechazo
# ---------------------------------------------------------------------------

## Devuelve cuántas unidades CABEN realmente (0 = rechazado). `silent` se usa
## internamente para no duplicar avisos tras un craft ya validado.
func can_add_item(id: String, amount: int = 1) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "added": 0, "reason": "Cantidad no válida"}
	var have: int = count(id)
	var added: int = mini(amount, maxi(stack_limit(id) - have, 0))
	var reason: String = ""
	if added <= 0:
		reason = "Pila completa: %s (%d/%d)" % [display_name(id), have, stack_limit(id)]
	# Un nuevo tipo ocupa una ranura; ampliar una pila existente no.
	if added > 0 and have == 0 and _items.size() >= MAX_SLOTS:
		added = 0
		reason = "Inventario lleno: %d/%d tipos" % [_items.size(), MAX_SLOTS]
	# Capacidad de peso.
	if added > 0:
		var weight: float = unit_weight(id)
		if weight > 0.0:
			var room: float = maxf(MAX_WEIGHT - current_weight(), 0.0)
			var by_weight: int = int(floor(room / weight + 0.0001))
			if by_weight < added:
				added = maxi(by_weight, 0)
				if added <= 0:
					reason = "Sobrecarga: %.1f/%.1f kg" % [current_weight(), MAX_WEIGHT]
	return {
		"ok": added > 0,
		"added": added,
		"partial": added > 0 and added < amount,
		"reason": reason,
	}

func add_item(id: String, amount: int = 1, silent: bool = false) -> int:
	if amount <= 0:
		return 0
	var room: Dictionary = can_add_item(id, amount)
	var added: int = int(room.get("added", 0))
	if added <= 0:
		if not silent:
			var why: String = String(room.get("reason", "Inventario lleno"))
			_reject(id, why)
		return 0
	_items[id] = count(id) + added
	if not _conditions.has(id):
		_conditions[id] = 1.0
	inventory_changed.emit()
	if not silent:
		item_picked_up.emit(id, added)
		if added < amount:
			_notify("Espacio limitado: +%d/%d %s" % [added, amount, display_name(id)])
		else:
			_notify("+%d %s" % [added, display_name(id)])
	return added

func remove_item(id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var have: int = count(id)
	if have < amount:
		return false
	_items[id] = have - amount
	if int(_items[id]) <= 0:
		_items.erase(id)
		_conditions.erase(id)
	inventory_changed.emit()
	return true

# ---------------------------------------------------------------------------
# Condición de herramientas y armas
# ---------------------------------------------------------------------------

## 0.0 = rota, 1.0 = nueva. Los ids no registrados se consideran nuevos para
## que combat pueda llamar a esta API con cualquier id de arma sin fallos.
func get_condition(item_id: String) -> float:
	return clampf(float(_conditions.get(item_id, 1.0)), 0.0, 1.0)

func set_condition(item_id: String, value: float) -> void:
	if not has(item_id):
		return
	_conditions[item_id] = clampf(value, 0.0, 1.0)

## Desgaste por uso (combat debe llamarlo al disparar/golpear).
func degrade_item(item_id: String, amount: float = 0.01) -> float:
	if not has(item_id) or amount <= 0.0:
		return get_condition(item_id)
	var next: float = clampf(get_condition(item_id) - amount, 0.0, 1.0)
	_conditions[item_id] = next
	if next <= 0.0:
		_notify("%s está gastada: inútil hasta repararla" % display_name(item_id))
	return next

func wear_item(item_id: String, amount: float = 0.01) -> float:
	return degrade_item(item_id, amount)

func repair_item(item_id: String, amount: float = 0.25) -> float:
	if not has(item_id) or amount <= 0.0:
		return get_condition(item_id)
	var next: float = clampf(get_condition(item_id) + amount, 0.0, 1.0)
	_conditions[item_id] = next
	return next

## Multiplicador de eficacia para combat: condición baja = arma menos precisa
## y menos dañina, pero nunca inútil al 100%.
func condition_factor(item_id: String) -> float:
	return clampf(0.35 + 0.65 * get_condition(item_id), 0.35, 1.0)

# ---------------------------------------------------------------------------
# Crafting
# ---------------------------------------------------------------------------

func get_recipes() -> Dictionary:
	return recipes.duplicate(true)

func recipe_name(recipe_id: String) -> String:
	return display_name(String(recipes.get(recipe_id, {}).get("output", recipe_id)))

func recipe_cost_text(recipe_id: String) -> String:
	var recipe: Dictionary = recipes.get(recipe_id, {})
	var parts: Array[String] = []
	for ingredient in recipe.get("cost", {}):
		parts.append("%d %s" % [int(recipe["cost"][ingredient]), display_name(String(ingredient))])
	return " + ".join(parts)

func can_craft(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = recipes.get(recipe_id, {})
	if recipe.is_empty():
		return {"ok": false, "reason": "Receta desconocida"}
	for ingredient in recipe.get("cost", {}):
		var need: int = int(recipe["cost"][ingredient])
		var have: int = count(String(ingredient))
		if have < need:
			return {"ok": false, "reason": "Faltan %d %s" % [need - have, display_name(String(ingredient))]}
	var room: Dictionary = can_add_item(String(recipe.get("output", recipe_id)), int(recipe.get("amount", 1)))
	if not bool(room.get("ok", false)):
		return {"ok": false, "reason": "Sin espacio: %s" % String(room.get("reason", ""))}
	return {"ok": true, "reason": ""}

func craft(recipe_id: String) -> bool:
	var check: Dictionary = can_craft(recipe_id)
	if not bool(check.get("ok", false)):
		_reject(recipe_id, String(check.get("reason", "No se puede fabricar")))
		return false
	var recipe: Dictionary = recipes[recipe_id]
	for ingredient in recipe.get("cost", {}):
		remove_item(String(ingredient), int(recipe["cost"][ingredient]))
	var output: String = String(recipe.get("output", recipe_id))
	var amount: int = int(recipe.get("amount", 1))
	var added: int = add_item(output, amount, true)
	if added <= 0:  # rollback defensivo si la capacidad cambió entre check y craft
		for ingredient in recipe.get("cost", {}):
			add_item(String(ingredient), int(recipe["cost"][ingredient]), true)
		_reject(recipe_id, "No se pudo guardar el objeto fabricado")
		return false
	_notify("Fabricado: %s ×%d" % [display_name(output), added])
	_emit_craft_signal(output, added)
	return true

func craft_item(recipe_id: String) -> bool:
	return craft(recipe_id)

# ---------------------------------------------------------------------------
# Botín por rareza (GameState.rng('loot') de forma defensiva)
# ---------------------------------------------------------------------------

func _tree() -> SceneTree:
	# get_tree() puede fallar si el autoload se usa desde un --script sin escena.
	if not is_inside_tree():
		return null
	return get_tree()

func _loot_rng() -> Object:
	var tree: SceneTree = _tree()
	if tree != null:
		var state: Node = tree.root.get_node_or_null("GameState")
		if state != null and state.has_method("rng"):
			var rng: Object = state.call("rng", "loot") as Object
			if rng != null and (rng.has_method("randf") or rng.has_method("randi_range")):
				return rng
	if _fallback_rng == null:
		_fallback_rng = RandomNumberGenerator.new()
		_fallback_rng.seed = 20261117
	return _fallback_rng

func _randf(rng: Object) -> float:
	if rng != null and rng.has_method("randf"):
		return clampf(float(rng.call("randf")), 0.0, 1.0)
	return randf()

func _randi(rng: Object, low: int, high: int) -> int:
	if rng != null and rng.has_method("randi_range"):
		return int(rng.call("randi_range", low, high))
	return randi_range(low, high)

## Devuelve una Array de Dictionary {id, amount, rarity}. Nunca `combustible`.
func roll_loot(rarity: String = "common", drops: int = 1) -> Array:
	var result: Array = []
	var table: Array = LOOT_TABLES.get(rarity, LOOT_TABLES.get("common", []))
	if table.is_empty():
		return result
	var rng: Object = _loot_rng()
	for _i in range(maxi(drops, 1)):
		var total: float = 0.0
		for entry in table:
			total += maxf(float(entry.get("weight", 0)), 0.0)
		if total <= 0.0:
			continue
		var roll: float = _randf(rng) * total
		var chosen: Dictionary = {}
		for entry in table:
			roll -= maxf(float(entry.get("weight", 0)), 0.0)
			if roll <= 0.0:
				chosen = entry
				break
		if chosen.is_empty():
			chosen = table[table.size() - 1]
		var low: int = maxi(int(chosen.get("min", 1)), 1)
		var high: int = maxi(int(chosen.get("max", low)), low)
		result.append({
			"id": String(chosen.get("id", "scrap")),
			"amount": _randi(rng, low, high),
			"rarity": rarity,
		})
	return result

# ---------------------------------------------------------------------------
# Señales / avisos
# ---------------------------------------------------------------------------

func _bus() -> Node:
	var tree: SceneTree = _tree()
	if tree != null:
		return tree.root.get_node_or_null("EventBus") as Node
	return null

func _notify(text: String) -> void:
	if text.is_empty():
		return
	var bus: Node = _bus()
	if bus != null and bus.has_signal("notification"):
		bus.emit_signal("notification", text)

func _reject(id: String, reason: String) -> void:
	item_rejected.emit(id, reason)
	_notify("No se puede añadir %s: %s" % [display_name(id), reason])

func _emit_craft_signal(item_id: String, amount: int) -> void:
	crafting_completed.emit(item_id, amount)
	var bus: Node = _bus()
	if bus == null:
		return
	# core puede añadir EventBus.crafting_completed con 0/1/2 argumentos.
	for name in ["crafting_completed", "craft_completed", "item_crafted"]:
		if not bus.has_signal(name):
			continue
		for sig in bus.get_signal_list():
			if String(sig.get("name", "")) != name:
				continue
			var arity: int = int((sig.get("args", []) as Array).size())
			if arity == 0:
				bus.emit_signal(name)
			elif arity == 1:
				bus.emit_signal(name, item_id)
			else:
				bus.emit_signal(name, item_id, amount)
			return
