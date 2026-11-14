class_name ZombieSenses


extends Node
## Sentidos del zombie: vision por cono y oido por eventos de sonido.
##
## Optimizado: solo evalua cada N frames y limita el numero de obstaculos
## consultados. Si no hay linea de vision, el zombie vuelve a IDLE.
## Accesible globalmente via `ZombieSenses` (class_name).

const SENSE_INTERVAL: float = 0.15
const VISION_RANGE: float = 22.0
const VISION_HALF_ANGLE_DEG: float = 55.0
const HEARING_RADIUS: float = 14.0

var zombie: BaseZombie
var can_see_player: bool = false
var last_known_position: Vector3 = Vector3.ZERO
var _timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = SENSE_INTERVAL
	_update_vision()
	_update_hearing()


## Actualiza el cono de vision contra el jugador.
func _update_vision() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or zombie == null:
		can_see_player = false
		return
	var to_target: Vector3 = player.global_position - zombie.global_position
	var distance: float = to_target.length()
	if distance > VISION_RANGE:
		can_see_player = false
		return
	var forward: Vector3 = -zombie.global_transform.basis.z
	var angle: float = rad_to_deg(forward.angle_to(to_target / maxf(distance, 0.001)))
	if angle > VISION_HALF_ANGLE_DEG and distance > 2.0:
		can_see_player = false
		return
	can_see_player = _has_line_of_sight(player)
	if can_see_player:
		last_known_position = player.global_position


## Raycast de linea de vision contra el entorno.
func _has_line_of_sight(player: Node3D) -> bool:
	var space: PhysicsDirectSpaceState3D = zombie.get_viewport().get_viewport().get_world_3d().direct_space_state
	var from: Vector3 = zombie.global_position + Vector3.UP * 1.4
	var to: Vector3 = player.global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 << 3)
	query.exclude = [zombie.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player


## Detecta fuentes de sonido recientes (disparos, pasos, gritos).
func _update_hearing() -> void:
	if zombie == null or zombie.ai == null:
		return
	# El EventBus publica `sfx_requested`; aqui solo se registra la escucha.
	if not EventBus.sfx_requested.is_connected(_on_sfx):
		EventBus.sfx_requested.connect(_on_sfx)


func _on_sfx(cue_id: StringName, world_position: Vector3) -> void:
	if zombie == null or not zombie.stats.can_scream and cue_id == &"zombie_scream":
		return
	if zombie.global_position.distance_to(world_position) > HEARING_RADIUS:
		return
	if zombie.ai != null and zombie.ai.state == ZombieAI.State.IDLE:
		zombie.ai.target = get_tree().get_first_node_in_group("player")
		zombie.ai.hear_position = world_position
