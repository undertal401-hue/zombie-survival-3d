extends Node
## ============================================================================
## ZOMBIE RENDER CULLING TEST — culling visual reversible.
## ============================================================================
## El culling de rendimiento debe ocultar el render lejano, no desactivar la
## simulacion que puede volver a mostrarlo. La puerta comprueba la banda de
## histéresis, colision, IA y el caso en que el zombi muere mientras esta
## oculto; ese cadaver debe poder reaparecer si el jugador se acerca antes
## de que termine su animacion.
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
	player.add_to_group("player")
	add_child(player)

	var zombie: CharacterBody2D = _make_probe_zombie("CullingProbeZombie")
	_place_player(player, zombie, 500.0)
	await _settle()

	_check(not zombie.visible,
		"El zombi lejano deja de renderizarse")
	_check(zombie.is_physics_processing(),
		"El culling no desactiva la fisica que puede revertirlo")
	_check(zombie.is_processing(),
		"El culling conserva vivo el actualizador visual")
	_check(not (zombie.get_node("Collision") as CollisionShape2D).disabled,
		"La colision permanece activa mientras el zombi esta oculto")
	_check(zombie.collision_layer == 2,
		"La capa de colision permanece activa mientras el zombi esta oculto")

	zombie.attack_cooldown = 1.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(zombie.attack_cooldown < 1.0,
		"La IA y sus temporizadores siguen avanzando mientras el zombi esta oculto")

	# Un cambio de culling no debe reiniciar el temporizador de repath. Se usa
	# una sonda aislada para invocar la transicion sincronamente y evitar que
	# el frame de fisica altere el valor antes de la asercion.
	var timer_zombie: CharacterBody2D = _make_probe_zombie("CullingTimerZombie")
	_place_player(player, timer_zombie, 500.0)
	await _settle()
	timer_zombie.set("_repath_timer", 0.2)
	timer_zombie.call("_update_render_culling", 50.0)
	_check(is_equal_approx(float(timer_zombie.get("_repath_timer")), 0.2),
		"La transicion de culling conserva el temporizador de repath")

	# Histéresis: dentro de la banda baja sigue oculto; al cruzar el limite
	# inferior reaparece y no vuelve a ocultarse hasta superar el superior.
	_place_player(player, zombie, 80.0)
	await _settle()
	_check(not zombie.visible,
		"El zombi permanece oculto dentro de la banda de histéresis")

	_place_player(player, zombie, 50.0)
	await _settle()
	_check(zombie.visible,
		"El zombi reaparece al entrar en el radio cercano")

	_place_player(player, zombie, 80.0)
	await _settle()
	_check(zombie.visible,
		"El zombi permanece visible al volver a la banda de histéresis")

	_place_player(player, zombie, 101.0)
	await _settle()
	_check(not zombie.visible,
		"El zombi se oculta de nuevo al superar el radio exterior")

	# Muerte mientras esta oculto: la muerte apaga la fisica por diseño, pero
	# no puede eliminar el unico bucle que puede restaurar el render.
	var dead_zombie: CharacterBody2D = _make_probe_zombie("CulledDeadZombie")
	_place_player(player, dead_zombie, 500.0)
	await _settle()
	_check(not dead_zombie.visible,
		"El zombi que va a morir empieza oculto")
	dead_zombie.take_damage(1000.0, player)
	_check(bool(dead_zombie.get("_dead")),
		"El zombi oculto muere por dano")
	_check(not dead_zombie.visible,
		"El cadaver permanece oculto mientras el jugador esta lejos")
	_check(dead_zombie.is_processing(),
		"La muerte conserva vivo el actualizador de visibilidad")
	_place_player(player, dead_zombie, 50.0)
	await _settle()
	_check(dead_zombie.visible,
		"El cadaver reaparece si el jugador se acerca durante su muerte")

	zombie.culling_distance = 0.0
	_check(zombie.culling_distance >= 1.0,
		"Una distancia de culling no positiva se normaliza")
	zombie.culling_distance = -25.0
	_check(zombie.culling_distance >= 1.0,
		"Una distancia de culling negativa se normaliza")

	await _finish()


func _make_probe_zombie(node_name: String) -> CharacterBody2D:
	var zombie: CharacterBody2D = ZOMBIE_SCENE.instantiate() as CharacterBody2D
	zombie.name = node_name
	zombie.culling_distance = 100.0
	# El alcance y la deteccion se anulan para que el propio zombi no modifique
	# la distancia de prueba; el culling y los timers siguen siendo reales.
	zombie.speed = 0.0
	zombie.detect_radius = 0.0
	zombie.close_sense_radius = 0.0
	zombie.lose_radius = 0.0
	add_child(zombie)
	return zombie


func _place_player(player: Node2D, zombie: Node2D, distance: float) -> void:
	player.global_position = zombie.global_position + Vector2(distance, 0.0)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _finish() -> void:
	print("ZOMBIE_RENDER_CULLING_TEST failures=%d" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
