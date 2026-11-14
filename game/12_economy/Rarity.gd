class_name Rarity

extends Resource
## Rareza de un item (data-driven).
## Accesible globalmente via `Rarity` (class_name).

@export var rarity_id: StringName = &"common"
@export var label: String = "Comun"
@export var color: Color = Color(0.8, 0.8, 0.8)
@export var drop_weight: float = 100.0
@export var sell_multiplier: float = 1.0
@export var price_multiplier: float = 1.0
@export var glow_intensity: float = 0.0


## Rarezas estandar del juego.
static func standard_table() -> Array[Rarity]:
	var table: Array[Rarity] = []
	table.append(_make(&"common", "Comun", Color(0.82, 0.82, 0.82), 100.0, 1.0, 1.0, 0.0))
	table.append(_make(&"uncommon", "Poco comun", Color(0.3, 0.85, 0.4), 45.0, 1.2, 1.25, 0.2))
	table.append(_make(&"rare", "Raro", Color(0.3, 0.55, 1.0), 12.0, 1.6, 1.7, 0.5))
	table.append(_make(&"epic", "Epico", Color(0.7, 0.35, 1.0), 3.0, 2.4, 2.5, 0.8))
	table.append(_make(&"legendary", "Legendario", Color(1.0, 0.65, 0.15), 0.6, 4.0, 4.0, 1.2))
	return table


static func _make(id: StringName, p_label: String, p_color: Color, weight: float,
		sell: float, price: float, glow: float) -> Rarity:
	var rarity := Rarity.new()
	rarity.rarity_id = id
	rarity.label = p_label
	rarity.color = p_color
	rarity.drop_weight = weight
	rarity.sell_multiplier = sell
	rarity.price_multiplier = price
	rarity.glow_intensity = glow
	return rarity
