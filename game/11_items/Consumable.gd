class_name Consumable

extends Resource
## Definicion data-driven de un consumible (no es un nodo de mundo).
##
## Los pickups concretos (Food, Potion, HealthKit) envuelven una definicion de
## este tipo para no duplicar datos entre instancias.
## Accesible globalmente via `Consumable` (class_name).

@export var consumable_id: StringName = &"consumable"
@export var display_name: String = "Consumible"
@export var description: String = ""
@export var heal_amount: float = 0.0
@export var infection_reduction: float = 0.0
@export var stamina_amount: float = 0.0
@export var permanent_kind: StringName = &""
@export var permanent_amount: float = 0.0
@export var use_time: float = 1.0
@export var cooldown: float = 0.0
@export var max_stack: int = 5
@export var value: int = 25


## Crea un ItemBase de mundo a partir de esta definicion.
## @return nodo ItemBase listo para insertar en la escena.
func spawn(scene_parent: Node) -> ItemBase:
	var item: ItemBase = ItemBase.new()
	item.item_id = consumable_id
	item.display_name = display_name
	item.description = description
	item.value = value
	scene_parent.add_child(item)
	return item


## Aplica el efecto sobre un jugador.
## @param player: jugador objetivo.
## @return true si tuvo efecto.
func apply(player: Node3D) -> bool:
	if player == null or not player.has_method("heal"):
		return false
	var target := player as Player
	if heal_amount > 0.0:
		target.heal(heal_amount)
	if infection_reduction > 0.0:
		target.cure_infection(infection_reduction)
	if stamina_amount > 0.0:
		target.stats.stamina = minf(target.stats.stamina + stamina_amount, target.stats.max_stamina)
	if permanent_kind != &"":
		target.stats.apply_permanent_upgrade(permanent_kind, permanent_amount)
	EventBus.item_consumed.emit(null, player)
	return true
