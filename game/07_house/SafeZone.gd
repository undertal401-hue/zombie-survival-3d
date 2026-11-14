class_name SafeZone


extends Area3D
## Zona segura generica (heredada por Bathroom).
##
## Emite senales al entrar/salir y proporciona curacion/recarga.
## Accesible globalmente via `SafeZone` (class_name).

signal player_entered(player: Node3D)
signal player_exited(player: Node3D)

const RADIUS: float = 3.0

var heal_rate: float = 5.0
var infection_cure_rate: float = 10.0
var ammo_refill_rate: int = 30
var _players_inside: Array[Node3D] = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 0
	var sphere: CollisionShape3D = CollisionShape3D.new()
	sphere.shape = SphereShape3D.new()
	(sphere.shape as SphereShape3D).radius = RADIUS
	add_child(sphere)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_players_inside.append(body)
		player_entered.emit(body)
		EventBus.safe_zone_entered.emit(self)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_players_inside.erase(body)
		player_exited.emit(body)
		EventBus.safe_zone_exited.emit(self)


func _process(delta: float) -> void:
	for player: Node3D in _players_inside:
		if player is Player:
			player.heal(heal_rate * delta)
			player.cure_infection(infection_cure_rate * delta)


func get_bounds() -> Vector3:
	return Vector3(RADIUS, RADIUS, RADIUS)
