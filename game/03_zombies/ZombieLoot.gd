class_name ZombieLoot


extends Node
## Genera el botin al morir un zombie: monedas + items + mejora rara.
##
## Usa DropCalculator para las probabilidades (1-3% de mejora permanente) y
## crea pickups reales en el mundo.
## Accesible globalmente via `ZombieLoot` (class_name).

const COIN_SCENE: PackedScene = preload("res://11_items/CoinPickup.tscn")
const ITEM_SCENE_DIR: String = "res://11_items/"

var zombie: BaseZombie
var calculator: DropCalculator
var factory: ItemFactory


func _ready() -> void:
	calculator = DropCalculator.new()
	calculator.configure(null)
	factory = ItemFactory.new()


## Suelta el botin del zombie.
## @param killer: jugador o fuente del dano.
func drop_loot(killer: Node3D) -> void:
	if zombie == null:
		return
	var drop: Dictionary = calculator.calculate(zombie.zombie_type(), zombie.current_wave)
	_spawn_coins(int(drop.get("coins", 5)))
	for entry: Dictionary in drop.get("items", []):
		_spawn_item(entry)
	var rare: Dictionary = drop.get("rare_upgrade", {})
	if not rare.is_empty():
		_spawn_rare_upgrade(rare)
	if killer is Player:
		Currency.add(int(drop.get("coins", 5)), &"kill")


## Crea monedas en arco para que el jugador las recoja.
func _spawn_coins(amount: int) -> void:
	if amount <= 0:
		return
	var chunks: int = clampi(amount / 5, 1, 10)
	var per_chunk: int = maxi(amount / chunks, 1)
	for i: int in chunks:
		var coin: ItemBase = COIN_SCENE.instantiate() as ItemBase
		if coin == null:
			continue
		coin.coin_amount = per_chunk
		zombie.get_parent().add_child(coin)
		coin.global_position = zombie.global_position + Vector3.UP * 0.6
		coin.apply_impulse(Vector3(randf_range(-1.5, 1.5), randf_range(2.0, 3.5), randf_range(-1.5, 1.5)))


## Crea un item del botin.
func _spawn_item(entry: Dictionary) -> void:
	var item: ItemBase = factory.create(entry.get("item_id", &"") as StringName)
	if item == null:
		return
	item.quantity = int(entry.get("qty", 1))
	zombie.get_parent().add_child(item)
	item.global_position = zombie.global_position + Vector3.UP * 0.5


## Crea el pickup de mejora permanente rara.
func _spawn_rare_upgrade(entry: Dictionary) -> void:
	var upgrade := PermanentUpgrade.new()
	upgrade.kind = entry.get("kind", &"damage") as StringName
	upgrade.amount = float(entry.get("amount", 0.05))
	upgrade.display_name = PermanentUpgrade.kind_label(upgrade.kind)
	upgrade.rarity_id = &"rare"
	EventBus.rare_drop_acquired.emit(upgrade)
	var pickup: Node3D = _make_upgrade_pickup(upgrade)
	zombie.get_parent().add_child(pickup)
	pickup.global_position = zombie.global_position + Vector3.UP * 0.8


## Construye el pickup visual de una mejora permanente.
func _make_upgrade_pickup(upgrade: PermanentUpgrade) -> Node3D:
	var pickup := PermanentUpgradePickup.new()
	pickup.item_id = &"permanent_upgrade"
	pickup.display_name = upgrade.display_name
	pickup.upgrade = upgrade
	return pickup
