class_name PriceTable

extends Resource
## Tabla de precios de la tienda (data-driven).
##
## Cada entrada asocia item_id con coste base, rareza, categoria y oleada de
## desbloqueo. La tienda aplica inflacion por oleada.
## Accesible globalmente via `PriceTable` (class_name).

@export var entries: Array[Dictionary] = []


## Anade una entrada de precio.
## @param item_id: identificador del item o arma.
## @param base_cost: coste base.
## @param rarity_id: rareza.
## @param category: "weapon" | "ammo" | "consumable" | "upgrade".
## @param unlock_wave: oleada a la que se desbloquea.
func add_entry(item_id: StringName, base_cost: int, rarity_id: StringName = &"common",
		category: StringName = &"consumable", unlock_wave: int = 1) -> void:
	entries.append({
		"item_id": item_id,
		"base_cost": base_cost,
		"rarity": rarity_id,
		"category": category,
		"unlock_wave": unlock_wave,
	})


## Busca una entrada por item_id.
## @return diccionario de la entrada o vacio.
func get_entry(item_id: StringName) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.get("item_id", &"") == item_id:
			return entry
	return {}


## Coste final con inflacion y rareza.
## @param item_id: identificador.
## @param wave_number: oleada actual (inflacion).
## @param rarity_table: tabla de rarezas para el multiplicador.
## @return coste final, o -1 si no existe.
func final_cost(item_id: StringName, wave_number: int, rarity_table: Array[Rarity]) -> int:
	var entry: Dictionary = get_entry(item_id)
	if entry.is_empty():
		return -1
	var rarity_mult: float = 1.0
	for rarity: Rarity in rarity_table:
		if rarity.rarity_id == entry.get("rarity", &"common"):
			rarity_mult = rarity.price_multiplier
			break
	var inflation: float = 1.0 + Config.economy_price_inflation_per_wave * maxi(wave_number - 1, 0)
	return maxi(int(float(entry["base_cost"]) * rarity_mult * inflation), 1)


## True si el item esta desbloqueado en la oleada dada.
func is_unlocked(item_id: StringName, wave_number: int) -> bool:
	var entry: Dictionary = get_entry(item_id)
	if entry.is_empty():
		return false
	return wave_number >= int(entry.get("unlock_wave", 1))
