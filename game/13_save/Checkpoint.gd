class_name Checkpoint


extends Area3D
## Punto de control en el mundo: guarda estado al tocarlo.
##
## Un solo checkpoint activo a la vez (el ultimo tocado).
## Accesible globalmente via `Checkpoint` (class_name).

signal checkpoint_activated(checkpoint_id: StringName)

@export var checkpoint_id: StringName = &"checkpoint"
@export var save_on_touch: bool = true

var _activated: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 0
	var sphere: CollisionShape3D = CollisionShape3D.new()
	sphere.shape = SphereShape3D.new()
	(sphere.shape as SphereShape3D).radius = 1.5
	add_child(sphere)
	body_entered.connect(_on_body_entered)
	# Visual
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = CylinderMesh.new()
	(mesh.mesh as CylinderMesh).height = 0.2
	(mesh.mesh as CylinderMesh).top_radius = 1.2
	(mesh.mesh as CylinderMesh).bottom_radius = 1.2
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.5)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mesh.material_override = mat
	add_child(mesh)


func _on_body_entered(body: Node3D) -> void:
	if not body is Player:
		return
	if _activated:
		return
	_activated = true
	if save_on_touch:
		SaveSystem.save_game(SaveSystem.current_slot)
	checkpoint_activated.emit(checkpoint_id)
	EventBus.checkpoint_reached.emit(checkpoint_id)
	EventBus.ui_notification.emit("Checkpoint: %s" % checkpoint_id, &"info")


## Resetea el checkpoint (nueva partida).
func reset() -> void:
	_activated = false
