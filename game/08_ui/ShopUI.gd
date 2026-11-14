class_name ShopUI

extends Control
## UI de la tienda (fase de compra 8:00).
##
## Lee el catalogo de Shop y muestra items desbloqueados con precios
## actualizados por inflacion. Compra via evento.
## Accesible globalmente via `ShopUI` (class_name).

const Shop := preload("res://12_economy/Shop.gd")
const Currency := preload("res://12_economy/Currency.gd")
const WaveTimer := preload("res://06_waves/WaveTimer.gd")

signal closed

@onready var container: VBoxContainer = %Container
@onready var coin_label: Label = %CoinLabel
@onready var timer_label: Label = %TimerLabel
@onready var close_btn: Button = %CloseBtn

var shop: Shop = null
var _item_buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_btn.pressed.connect(_on_close)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.wave_timer_updated.connect(_on_timer_updated)
	EventBus.shop_phase_started.connect(_on_shop_started)
	EventBus.shop_phase_ended.connect(_on_shop_ended)
	call_deferred("_on_shop_ready")

func _on_shop_ready() -> void:
	shop = get_tree().get_first_node_in_group("shop") as Shop
	if shop != null:
		_refresh_catalog()

func _on_shop_started(wave_number: int) -> void:
	visible = true
	if shop != null:
		shop.set_wave(wave_number)
		_refresh_catalog()

func _on_shop_ended(_wave_number: int) -> void:
	visible = false
	closed.emit()

func _refresh_catalog() -> void:
	if shop == null:
		return
	for btn: Button in _item_buttons:
		btn.queue_free()
	_item_buttons.clear()
	var catalog: Array[Dictionary] = shop.get_catalog()
	for entry: Dictionary in catalog:
		if not entry.unlocked:
			continue
		var btn: Button = Button.new()
		btn.text = "%s - %d monedas" % [entry.item_id, entry.cost]
		btn.disabled = not Currency.can_afford(entry.cost)
		btn.pressed.connect(_on_item_purchased.bind(entry.item_id))
		container.add_child(btn)
		_item_buttons.append(btn)

func _on_item_purchased(item_id: StringName) -> void:
	if shop != null:
		shop.purchase(item_id)
	_refresh_catalog()

func _on_currency_changed(balance: int, _delta: int) -> void:
	coin_label.text = "Monedas: %d" % balance
	_refresh_catalog()

func _on_timer_updated(remaining: float, _total: float) -> void:
	timer_label.text = "Tiempo: %s" % WaveTimer.format_remaining_static(remaining)

func _on_close() -> void:
	EventBus.shop_phase_cancelled.emit()
	visible = false
	closed.emit()
