extends Node
## ============================================================================
## ZOMBIE RENDER CULLING TEST — culling visual reversible.
## ============================================================================
## El culling de rendimiento debe ocultar el render lejano, no desactivar el
## unico bucle que puede volver a mostrarlo. La prueba aleja al jugador,
## exige que el zombi deje de dibujarse y comprueba que su fisica siga
## activa; después lo acerca y exige que reaparezca.
## ============================================================================

const ZOMBIE_SCENE: PackedScene = preload("res://03_zombies/Zombie.tscn")

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	var player := Node2D.new()
	player.name = "CullingProbePlayer"
	player.position = Vector2(500.0, 0.0)
	player.add_to_group("player")
	add_child(player)

	var zombie: CharacterBody2D = ZOMBIE_SCENE.instantiate() as CharacterBody2D
	zombie.culling_distance = 100.0
	add_child(zombie)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(not zombie.visible,
		"El zombi lejano deja de renderizarse")
	_check(zombie.is_physics_processing(),
		"El culling no desactiva la fisica que puede revertirlo")

	player.position = Vector2(50.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(zombie.visible,
		"El zombi reaparece al entrar en el radio cercano")
	_check(zombie.is_physics_processing(),
		"La fisica sigue activa tras la reactivacion visual")

	await _finish()


func _finish() -> void:
	print("ZOMBIE_RENDER_CULLING_TEST failures=%d" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
