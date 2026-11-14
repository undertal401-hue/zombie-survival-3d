class_name SceneValidator

extends RefCounted
## Validador de escenas: nodos requeridos, capas de colision, scripts, recursos.
##
## Usado por 17_tests/test_scene_validation.gd y CI.
## Accesible globalmente via `SceneValidator` (class_name).

const REQUIRED_AUTLOADS: Array[StringName] = [
	&"EventBus", &"Config", &"GameClock", &"SaveSystem",
	&"AudioManager", &"WaveManager", &"GameManager", &"DebugConsole",
]

const REQUIRED_GROUPS: Array[String] = [
	"player", "zombies", "spawn_points", "zombie_spawner",
	"shop", "explosion_system", "damage_system", "knockback_system",
]


## Valida una escena dada.
## @param scene_path: ruta de la escena.
## @param strict: si true, falla en warnings.
## @return diccionario {valid: bool, errors: [], warnings: []}.
static func validate(scene_path: String, strict: bool = false) -> Dictionary:
	var result: Dictionary = {"valid": true, "errors": [], "warnings": []}
	if not ResourceLoader.exists(scene_path):
		result.valid = false
		result.errors.append("Escena no existe: %s" % scene_path)
		return result
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		result.valid = false
		result.errors.append("No se pudo cargar: %s" % scene_path)
		return result
	var instance: Node = scene.instantiate()
	if instance == null:
		result.valid = false
		result.errors.append("No se pudo instanciar: %s" % scene_path)
		return result
	_check_node_tree(instance, "", result)
	_check_collision_layers(instance, result)
	_check_scripts(instance, result)
	_check_resources(instance, result)
	instance.queue_free()
	if strict and result.warnings.size() > 0:
		result.valid = false
	return result


static func _check_node_tree(node: Node, path: String, result: Dictionary) -> void:
	var current_path: String = path + "/" + node.name if path != "" else node.name
	if node.get_script() != null:
		var script: Script = node.get_script()
		if not ResourceLoader.exists(script.resource_path):
			result.warnings.append("Script externo no encontrado: %s en %s" % [script.resource_path, current_path])
	for child: Node in node.get_children():
		_check_node_tree(child, current_path, result)


static func _check_collision_layers(node: Node, result: Dictionary) -> void:
	if node is CollisionObject3D:
		var obj := node as CollisionObject3D
		if obj.collision_layer == 0 and obj.collision_mask == 0:
			result.warnings.append("Sin capas de colision: %s" % node.get_path())
		if obj.collision_layer != 0 and obj.collision_mask == 0:
			result.warnings.append("Capa sin mascara: %s" % node.get_path())


static func _check_scripts(node: Node, result: Dictionary) -> void:
	if node.get_script() == null and node.get_child_count() == 0:
		result.warnings.append("Nodo hoja sin script: %s" % node.get_path())


static func _check_resources(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			result.warnings.append("MeshInstance3D sin mesh: %s" % node.get_path())
		if mi.mesh != null and mi.mesh.surface_get_material(0) == null:
			result.warnings.append("Mesh sin material: %s" % node.get_path())


## Valida todos los autoloads del proyecto.
static func validate_autoloads(project_settings: ConfigFile) -> Dictionary:
	var result: Dictionary = {"valid": true, "missing": [], "invalid": []}
	var keys: PackedStringArray = project_settings.get_section_keys("autoload")
	for required: StringName in REQUIRED_AUTLOADS:
		var found: bool = false
		for key: String in keys:
			if key == str(required):
				found = true
				break
			var entry: String = str(project_settings.get_value("autoload", key, ""))
			if entry.ends_with("%s.gd" % required):
				found = true
				break
		if not found:
			result.missing.append(required)
			result.valid = false
	return result
