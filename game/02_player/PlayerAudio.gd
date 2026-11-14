class_name PlayerAudio

extends Node
## Componente de audio del jugador: pasos, dano, curacion y interacciones.
##
## No reproduce audio directamente: pide cues al AudioManager, que gestiona
## voces, pooling y atenuacion espacial.
## Accesible globalmente via `PlayerAudio` (class_name).

const FOOTSTEP_INTERVAL: float = 0.42
const FOOTSTEP_SPRINT_INTERVAL: float = 0.28

var player: Player
var _step_timer: float = 0.0
var _last_surface: StringName = &"concrete"


func _ready() -> void:
	var owner_node: Node = owner
	if owner_node is Player:
		player = owner_node as Player
		EventBus.player_damaged.connect(_on_player_damaged)
		EventBus.player_healed.connect(_on_player_healed)
		EventBus.player_dodge_started.connect(_on_player_dodged)


func _process(delta: float) -> void:
	if player == null or player.controller == null:
		return
	if player.controller.get_horizontal_speed() < 0.5 or not player.is_on_floor():
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = FOOTSTEP_SPRINT_INTERVAL if player.controller.is_sprinting else FOOTSTEP_INTERVAL
		EventBus.footstep_requested.emit(_last_surface, player.global_position)


func _on_player_damaged(amount: float, _source: Node3D) -> void:
	if amount >= 30.0:
		EventBus.sfx_requested.emit(&"player_hurt_heavy", player.global_position)
	else:
		EventBus.sfx_requested.emit(&"player_hurt_light", player.global_position)


func _on_player_healed(_amount: float, _source: Node3D) -> void:
	EventBus.sfx_requested.emit(&"player_heal", player.global_position)


func _on_player_dodged(_duration: float) -> void:
	EventBus.sfx_requested.emit(&"player_dodge", player.global_position)
