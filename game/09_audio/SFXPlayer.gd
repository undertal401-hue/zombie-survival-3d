class_name SFXPlayer


extends Node3D
## Componente de SFX para entidades: pasos, voz, impacto.
##
## No reproduce directamente: delega en AudioManager via EventBus.
## Mantiene estado local (ultima superficie, cooldowns).
## Accesible globalmente via `SFXPlayer` (class_name).

const FOOTSTEP_COOLDOWN: float = 0.15

var _last_surface: StringName = &"concrete"
var _footstep_timer: float = 0.0
var _voice_cooldown: float = 0.0


func _process(delta: float) -> void:
	_footstep_timer = maxf(_footstep_timer - delta, 0.0)
	_voice_cooldown = maxf(_voice_cooldown - delta, 0.0)


## Solicita un paso con la superficie actual.
func request_footstep() -> void:
	if _footstep_timer > 0.0:
		return
	_footstep_timer = FOOTSTEP_COOLDOWN
	EventBus.footstep_requested.emit(_last_surface, global_position)


## Actualiza la superficie actual (raycast hacia abajo).
func update_surface() -> void:
	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position - Vector3.UP * 2.0, 1 << 3)
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var collider: Node = hit.get("collider") as Node
		if collider != null:
			var mat: StringName = _surface_from_collider(collider)
			if mat != &"":
				_last_surface = mat


func _surface_from_collider(collider: Node) -> StringName:
	if collider is StaticBody3D:
		var parent: Node = collider.get_parent()
		if parent != null and parent.has_meta("surface_type"):
			return parent.get_meta("surface_type") as StringName
	return &"concrete"


## Solicita una linea de voz (dano, muerte, grito).
## @param cue_id: cue de voz.
func request_voice(cue_id: StringName) -> void:
	if _voice_cooldown > 0.0:
		return
	_voice_cooldown = 0.5
	EventBus.voice_requested.emit(cue_id, global_position)
