class_name ShopPhase


extends Node
## Coordinador de la fase de compra.
##
## Vincula WaveManager, la UI de tienda, el bano (recarga/cura) y la economia.
## No reproduce logica de compra: la tienda (12_economy/Shop.gd) la tiene.
## Accesible globalmente via `ShopPhase` (class_name).

signal phase_opened(wave_number: int)
signal phase_closed(wave_number: int)
signal phase_timer_expired

var is_open: bool = false
var wave_number: int = 0
var shop: Shop
var safe_zone: Node3D = null


func _ready() -> void:
	EventBus.shop_phase_started.connect(_on_shop_started)
	EventBus.shop_phase_ended.connect(_on_shop_ended)
	EventBus.shop_phase_cancelled.connect(close)


## Abre la fase de compra.
## @param p_wave_number: oleada que acaba de terminar.
func open(p_wave_number: int) -> void:
	if is_open:
		return
	is_open = true
	wave_number = p_wave_number
	shop = get_node_or_null("/root/Shop") as Shop
	phase_opened.emit(p_wave_number)


## Cierra la fase de compra.
func close() -> void:
	if not is_open:
		return
	is_open = false
	phase_closed.emit(wave_number)


func _on_shop_started(p_wave_number: int) -> void:
	open(p_wave_number)


func _on_shop_ended(_wave_number: int) -> void:
	close()


## Compra un item de la tienda si se puede pagar.
## @param item_id: identificador del item.
## @return true si la compra fue exitosa.
func purchase(item_id: StringName) -> bool:
	if shop == null:
		return false
	return shop.purchase(item_id)
