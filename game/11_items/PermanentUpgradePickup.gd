class_name PermanentUpgradePickup

extends ItemBase
## Pickup de mejora permanente (drop raro 1-3%).
##
## Al recogerlo aplica la mejora a PlayerStats y la persiste en SaveSystem.
## Accesible globalmente via `PermanentUpgradePickup` (class_name).

const ItemBase := preload("res://11_items/ItemBase.gd")
const PermanentUpgrade := preload("res://11_items/PermanentUpgrade.gd")
const Player := preload("res://02_player/Player.gd")
const Rarity := preload("res://12_economy/Rarity.gd")

@export var upgrade: PermanentUpgrade = null

func _init() -> void:
	item_id = &"permanent_upgrade"
	display_name = "Mejora permanente"
	value = 0

func _ready() -> void:
	super._ready()
	if upgrade != null:
		display_name = upgrade.display_name
		description = upgrade.description
		if upgrade.rarity_id != &"":
			rarity = _find_rarity(upgrade.rarity_id)
	set_glow()

## Aplica la mejora permanente al jugador y la persiste.
func apply(player: Node3D) -> bool:
	if upgrade == null or player == null or not player.has_method("get_stats"):
		return false
	var stats: PlayerStats = player.get_stats()
	upgrade.apply_to(stats)
	SaveSystem.record_permanent_upgrade(upgrade)
	EventBus.rare_drop_acquired.emit(upgrade)
	EventBus.sfx_2d_requested.emit(&"pickup_rare")
	EventBus.ui_notification.emit("Mejora permanente: %s" % upgrade.display_name, &"reward")
	return true

func get_interaction_prompt() -> String:
	return "Recoger %s" % display_name

## Bruto visual asociado a la rareza.
func set_glow() -> void:
	if rarity == null:
		return
	var light := OmniLight3D.new()
	light.light_color = rarity.color
	light.omni_range = 2.0
	light.light_energy = rarity.glow_intensity
	add_child(light)

func _find_rarity(rarity_id: StringName) -> Rarity:
	for rarity: Rarity in Rarity.standard_table():
		if rarity.rarity_id == rarity_id:
			return rarity
	return null
