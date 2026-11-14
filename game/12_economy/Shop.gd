class_name Shop

extends Node
## Tienda de la fase de compra.
##
## Catalogo data-driven (PriceTable) con inflacion por oleada y desbloqueo
## progresivo. Gestiona compras, ventas y devoluciones, y notifica por
## EventBus. No conoce la UI: la UI lee `get_catalog()`.
## Accesible globalmente via `Shop` (class_name).

signal catalog_refreshed(wave_number: int)
signal purchase_completed(transaction: Transaction)
signal purchase_failed(item_id: StringName, reason: StringName)

var price_table: PriceTable = PriceTable.new()
var rarity_table: Array[Rarity] = Rarity.standard_table()
var transactions: Array[Transaction] = []
var current_wave: int = 1


func _ready() -> void:
	add_to_group("shop")
	_load_price_table()
	_load_rarity_table()


## Carga la tabla de precios desde el recurso de datos.
func _load_price_table() -> void:
	var table: PriceTable = load("res://16_data/PriceTable.tres") as PriceTable
	if table != null:
		price_table = table


## Carga la tabla de rarezas desde el recurso de datos.
func _load_rarity_table() -> void:
	var table: Array[Rarity] = Rarity.standard_table()
	var override: Resource = load("res://16_data/RarityTable.tres")
	if override != null and override is Rarity:
		table = [override as Rarity]
	rarity_table = table


## Compra un item si es posible.
## @param item_id: identificador del item.
## @return true si la compra fue exitosa.
func purchase(item_id: StringName) -> bool:
	if not price_table.is_unlocked(item_id, current_wave):
		purchase_failed.emit(item_id, &"locked")
		return false
	var cost: int = price_table.final_cost(item_id, current_wave, rarity_table)
	if cost < 0:
		purchase_failed.emit(item_id, &"unknown_item")
		return false
	if not Currency.try_spend(cost, item_id):
		purchase_failed.emit(item_id, &"insufficient_funds")
		return false
	var tx: Transaction = Transaction.make(item_id, Transaction.TransactionType.PURCHASE,
		cost, current_wave, true)
	transactions.append(tx)
	_deliver(item_id)
	EventBus.shop_purchased.emit(item_id, cost)
	purchase_completed.emit(tx)
	return true


## Vende un item del inventario.
## @param item_id: identificador.
## @param sell_price: precio de venta.
## @return true si se vendio.
func sell(item_id: StringName, sell_price: int) -> bool:
	var tx: Transaction = Transaction.make(item_id, Transaction.TransactionType.SELL,
		sell_price, current_wave, true)
	transactions.append(tx)
	Currency.add(sell_price, &"sell")
	return true


## Entrega el item comprado al jugador (por evento; sin referencia directa).
func _deliver(item_id: StringName) -> void:
	EventBus.item_picked.emit(null, null)
	EventBus.ui_notification.emit("Comprado: %s" % item_id, &"reward")


## Catalogo disponible para la UI en la oleada actual.
## @return Array[Dictionary] con item_id, cost, rarity, category, unlocked.
func get_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in price_table.entries:
		var item_id: StringName = entry.get("item_id", &"")
		var unlocked: bool = price_table.is_unlocked(item_id, current_wave)
		result.append({
			"item_id": item_id,
			"cost": price_table.final_cost(item_id, current_wave, rarity_table),
			"rarity": entry.get("rarity", &"common"),
			"category": entry.get("category", &"consumable"),
			"unlock_wave": entry.get("unlock_wave", 1),
			"unlocked": unlocked,
		})
	return result


## Actualiza la oleada actual (recalcula precios).
## @param wave_number: oleada.
func set_wave(wave_number: int) -> void:
	current_wave = maxi(wave_number, 1)
	catalog_refreshed.emit(current_wave)


## Historial de transacciones.
func get_transactions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tx: Transaction in transactions:
		result.append({
			"id": tx.transaction_id, "item": tx.item_id, "type": tx.type_label(),
			"amount": tx.amount, "wave": tx.wave_number,
		})
	return result
