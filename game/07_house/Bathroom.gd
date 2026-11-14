class_name Bathroom

extends Node3D
## Zona segura (baño): recarga municion, cura infeccion, acceso a tienda.
##
## Gratis 1x por oleada (municion) y 1x por partida (infeccion). Despues cuesta monedas.
## Accesible globalmente via `Bathroom` (class_name).

const Room := preload("res://07_house/Room.gd")
const Currency := preload("res://12_economy/Currency.gd")
const ItemBase := preload("res://11_items/ItemBase.gd")
const PermanentUpgrade := preload("res://11_items/PermanentUpgrade.gd")
const Player := preload("res://02_player/Player.gd")
const BaseWeapon := preload("res://04_weapons/BaseWeapon.gd")
const Inventory := preload("res://02_player/Inventory.gd")

const INTERACTION_RADIUS: float = 2.0
const AMMO_REFILL_COST: int = 50
const INFECTION_CURE_COST: int = 100
const CURE_AMOUNT: float = 25.0

var room: Room
var interaction_area: Area3D
var ammo_refill_used: bool = false
var infection_cure_used: bool = false
var _ui_prompt: Label3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_visuals()
	_build_interaction()

## Coloca el baño dentro de una habitacion existente.
func setup_in_room(p_room: Room) -> void:
	room = p_room
	global_position = p_room.get_center() + Vector3(0.0, 0.0, 2.0)

func _build_visuals() -> void:
	var floor: MeshInstance3D = MeshInstance3D.new()
	floor.name = "BathroomFloor"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(4.0, 0.15, 3.0)
	floor.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.18, 0.22)
	floor.material_override = mat
	floor.position = Vector3(0.0, 0.075, 0.0)
	add_child(floor)
	var static_body := StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	(collision.shape as BoxShape3D).size = Vector3(4.0, 0.15, 3.0)
	static_body.add_child(collision)
	static_body.position = Vector3(0.0, 0.075, 0.0)
	add_child(static_body)
	# Luz calida de zona segura
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.6, 1.0)
	light.light_energy = 1.5
	light.omni_range = 5.0
	light.position = Vector3(0.0, 2.5, 0.0)
	add_child(light)
	# Prompt 3D
	_ui_prompt = Label3D.new()
	_ui_prompt.text = "[E] Baño - Zona Segura"
	_ui_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_prompt.position = Vector3(0.0, 2.2, 0.0)
	_ui_prompt.font_size = 64
	add_child(_ui_prompt)

func _build_interaction() -> void:
	interaction_area = Area3D.new()
	interaction_area.name = "InteractionArea"
	var sphere: CollisionShape3D = CollisionShape3D.new()
	sphere.shape = SphereShape3D.new()
	(sphere.shape as SphereShape3D).radius = INTERACTION_RADIUS
	interaction_area.add_child(sphere)
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 1 << 0
	add_child(interaction_area)
	interaction_area.body_entered.connect(_on_player_entered)
	interaction_area.body_exited.connect(_on_player_exited)

## Punto seguro dentro del baño.
func get_safe_position() -> Vector3:
	return global_position + Vector3(0.0, 1.0, 0.0)

## Jugador entra en el area de interaccion.
func _on_player_entered(body: Node3D) -> void:
	if body is Player:
		body.interaction.set_focused(self)
		EventBus.safe_zone_entered.emit(self)

## Jugador sale del area.
func _on_player_exited(body: Node3D) -> void:
	if body is Player:
		body.interaction.clear_focus(self)
		EventBus.safe_zone_exited.emit(self)

## Interfaz Interactable.
func interact(player: Player) -> void:
	_show_options(player)

## Muestra opciones (UI simple via evento).
func _show_options(player: Player) -> void:
	var can_free_ammo: bool = not ammo_refill_used
	var can_free_cure: bool = not infection_cure_used
	var lines: Array[String] = []
	lines.append("=== BAÑO (Zona Segura) ===")
	var ammo_text: String = "GRATIS (1/oleada)" if can_free_ammo else ("%d monedas" % AMMO_REFILL_COST)
	var cure_base: String = "GRATIS (1/partida)" if can_free_cure else ("%d monedas" % INFECTION_CURE_COST)
	var line1: String = "1. Recargar municion completa - %s" % ammo_text
	var line2: String = "2. Curar infeccion (-" + str(CURE_AMOUNT) + "%%) - " + cure_base
	lines.append(line1)
	lines.append(line2)
	lines.append("3. Abrir tienda")
	EventBus.ui_notification.emit("\n".join(lines), &"info")
	# En una implementacion completa esto abriria un menu modal; aqui ejecutamos directo
	_refill_ammo(player)
	_cure_infection(player)

## Recarga municion de todas las armas.
func _refill_ammo(player: Player) -> void:
	if player == null or player.inventory == null:
		return
	if not ammo_refill_used:
		ammo_refill_used = true
		_free_refill_all(player)
		EventBus.ammo_refilled.emit(0, 0, true)
		return
	if Currency.try_spend(AMMO_REFILL_COST, &"ammo_refill"):
		_free_refill_all(player)
		EventBus.ammo_refilled.emit(0, 0, false)

func _free_refill_all(player: Player) -> void:
	for weapon: BaseWeapon in player.inventory.primary_slots:
		weapon.reserve_ammo = weapon.data.reserve_max
		weapon.magazine = weapon.data.magazine
		EventBus.ammo_changed.emit(weapon, weapon.magazine, weapon.reserve_ammo)
	for weapon: BaseWeapon in player.inventory.secondary_slots:
		weapon.reserve_ammo = weapon.data.reserve_max
		weapon.magazine = weapon.data.magazine
		EventBus.ammo_changed.emit(weapon, weapon.magazine, weapon.reserve_ammo)
	for weapon: BaseWeapon in player.inventory.melee_slots:
		pass
	EventBus.ui_notification.emit("Municion recargada al maximo", &"reward")

## Cura infeccion.
func _cure_infection(player: Player) -> void:
	if player == null:
		return
	if not infection_cure_used:
		infection_cure_used = true
		player.cure_infection(CURE_AMOUNT)
		EventBus.ui_notification.emit("Infeccion curada (gratis)", &"reward")
		return
	if Currency.try_spend(INFECTION_CURE_COST, &"infection_cure"):
		player.cure_infection(CURE_AMOUNT)
		EventBus.ui_notification.emit("Infeccion curada", &"reward")

## Resetea el uso gratis de municion (nueva oleada).
func reset_ammo_refill() -> void:
	ammo_refill_used = false

## Serializacion para guardado.
func to_dict() -> Dictionary:
	return {"ammo_refill_used": ammo_refill_used, "infection_cure_used": infection_cure_used}

func from_dict(data: Dictionary) -> void:
	ammo_refill_used = data.get("ammo_refill_used", false)
	infection_cure_used = data.get("infection_cure_used", false)
