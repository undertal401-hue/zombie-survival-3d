class_name ItemBase

extends Area3D
## Base de todos los items recogibles en el mundo.
##
## Implementa la interfaz `Interactable`: el jugador la detecta con
## InteractionComponent y llama a `interact(player)`. El efecto concreto lo
## define cada subclase en `apply()`.
## Accesible globalmente via `ItemBase` (class_name).

@export var item_id: StringName = &"item"
@export var display_name: String = "Item"
@export var description: String = ""
@export var rarity: Rarity = null
@export var value: int = 0
@export var quantity: int = 1
@export var bob_height: float = 0.15
@export var rotate_speed: float = 1.2

var _base_y: float = 0.0
var _time: float = 0.0
var _impulse: Vector3 = Vector3.ZERO
var _impulse_active: bool = false


func _ready() -> void:
	_base_y = position.y
	collision_layer = 1 << 4  # pickup
	collision_mask = 0


func _process(delta: float) -> void:
	_time += delta
	if _impulse_active:
		_integrate_impulse(delta)
	else:
		position.y = _base_y + sin(_time * 2.5) * bob_height
	rotation.y += rotate_speed * delta


## Integracion simple de impulso para pickups (arco y rebote en suelo).
func _integrate_impulse(delta: float) -> void:
	_impulse.y -= 12.0 * delta
	position += _impulse * delta
	if position.y <= _base_y:
		position.y = _base_y
		if absf(_impulse.y) > 1.5:
			_impulse.y = -_impulse.y * 0.35
			_impulse.x *= 0.6
			_impulse.z *= 0.6
		else:
			_impulse_active = false
			_impulse = Vector3.ZERO


## Aplica un impulso inicial (por ejemplo al soltar botin).
## @param impulse: vector de velocidad inicial.
func apply_impulse(impulse: Vector3) -> void:
	_impulse = impulse
	_impulse_active = true


## Interfaz de interaccion: recoge el item.
## @param player: jugador que lo recoge.
func interact(player: Node3D) -> void:
	if player == null:
		return
	var applied: bool = apply(player)
	if applied:
		quantity = maxi(quantity - 1, 0)
		EventBus.item_picked.emit(self, player)
		if quantity <= 0:
			queue_free()
	else:
		EventBus.ui_notification.emit("No puedes usar esto ahora", &"warning")


## Efecto concreto del item. Las subclases lo sobrescriben.
## @param player: jugador objetivo.
## @return true si se aplico.
func apply(_player: Node3D) -> bool:
	return false


## Texto de ayuda que muestra la UI al enfocar el item.
func get_interaction_prompt() -> String:
	return "Recoger %s" % display_name


## Precio de venta (mitad del valor, como minimo 1).
func sell_price() -> int:
	return maxi(int(value * Config.economy_sell_multiplier), 1)


## Serializa el item para guardado.
func to_dict() -> Dictionary:
	return {
		"item_id": item_id,
		"display_name": display_name,
		"quantity": quantity,
		"value": value,
		"rarity": rarity.rarity_id if rarity != null else &"common",
	}
