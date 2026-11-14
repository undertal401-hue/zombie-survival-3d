class_name InteractionComponent

extends Node
## Componente de interaccion por proximidad.
##
## Detecta objetos con la interfaz `Interactable` y expone el foco actual.
## El jugador llama a `interact()` al pulsar la accion correspondiente.
## Accesible globalmente via `InteractionComponent` (class_name).

signal focus_changed(interactable: Node)
signal interaction_succeeded(interactable: Node)
signal interaction_failed(reason: StringName)

const DETECT_RADIUS: float = 2.4
const USE_COOLDOWN: float = 0.25

var player: Player
var _focused: Node = null
var _forced_focus: Node = null
var _cooldown: float = 0.0
var _candidates: Array[Node] = []


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_update_focus()


## Actualiza el objeto interactuable con mejor prioridad (mas cercano).
func _update_focus() -> void:
	if _forced_focus != null:
		if is_instance_valid(_forced_focus):
			_set_focus(_forced_focus)
			return
		_forced_focus = null
	if player == null:
		return
	_candidates.clear()
	var space: PhysicsDirectSpaceState3D = player.get_viewport().get_viewport().get_world_3d().direct_space_state
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = DETECT_RADIUS
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = player.global_transform
	query.collision_mask = 1 << 4  # capa pickup
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hits: Array[Dictionary] = space.intersect_shape(query, 16)
	var best: Node = null
	var best_dist: float = INF
	for hit: Dictionary in hits:
		var collider: Node = hit.get("collider") as Node
		if collider == null or not collider.has_method("interact"):
			continue
		var dist: float = player.global_position.distance_to(collider.global_position)
		if dist < best_dist:
			best_dist = dist
			best = collider
	if best != _focused:
		_focused = best
		focus_changed.emit(_focused)


## Fija el foco en un interactuable (zonas de trigger como el baño).
func set_focused(interactable: Node) -> void:
	_forced_focus = interactable
	_set_focus(interactable)


## Libera el foco forzado si coincide con el interactuable dado.
func clear_focus(interactable: Node = null) -> void:
	if interactable != null and _forced_focus != interactable:
		return
	_forced_focus = null
	_set_focus(null)


## Actualiza `_focused` emitiendo la senal solo si cambia.
func _set_focus(interactable: Node) -> void:
	if _focused == interactable:
		return
	_focused = interactable
	focus_changed.emit(_focused)


## Ejecuta la interaccion con el foco actual.
func interact() -> void:
	if _cooldown > 0.0 or _focused == null:
		return
	_cooldown = USE_COOLDOWN
	if _focused.has_method("interact"):
		_focused.interact(player)
		interaction_succeeded.emit(_focused)


## Devuelve el interactuable enfocado (o null).
func get_focused() -> Node:
	return _focused


## Etiqueta de ayuda para la UI.
func get_prompt_text() -> String:
	if _focused == null:
		return ""
	if _focused.has_method("get_interaction_prompt"):
		return _focused.get_interaction_prompt()
	return "Interactuar"
