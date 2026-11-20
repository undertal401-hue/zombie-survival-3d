extends Node

var _main: Node

func _ready() -> void:
	await get_tree().process_frame
	_main = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	for i in range(10):
		await get_tree().process_frame
	var player: CharacterBody2D = _main.get_node("Player")
	var inv = get_node("/root/Inventory")
	inv.call("clear")
	inv.call("add_item", "pistol_ammo", 200)
	inv.call("add_item", "comida", 20)
	inv.call("add_item", "medkit", 5)

	var actions: Array[String] = ["move_forward", "move_back", "move_left", "move_right", "shoot", "attack", "reload"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var errors: int = 0
	# Comprobaciones reales del estado base, antes de estresar: cuentan fallos
	# para la salida del proceso y se guardan como booleanos para los asserts
	# finales (programados despues del quit, patron HARD_GATE de R1).
	var player_valid: bool = is_instance_valid(player)
	var not_paused: bool = not get_tree().paused
	var time_scale_ok: bool = is_equal_approx(Engine.time_scale, 1.0)
	var has_zombies: bool = not get_tree().get_nodes_in_group("zombies").is_empty()
	var has_pickups: bool = not get_tree().get_nodes_in_group("pickups").is_empty()
	if not player_valid:
		errors += 1
	if not not_paused:
		errors += 1
	if not time_scale_ok:
		errors += 1
	if not has_zombies:
		errors += 1
	if not has_pickups:
		errors += 1
	print("=== STRESS TEST START ===")
	print("STRESS_TEST failures=%d" % errors)
	for frame in range(600):
		# Tope de frames de proceso: --quit-after 700 cortaria el arnes antes
		# de STRESS END y su codigo de salida. Con esta guardia el arnes
		# termina por si mismo y el quit(code) del final es real.
		if Engine.get_process_frames() >= 600:
			break
		if frame % 20 == 0:
			for a in actions:
				if rng.randf() < 0.3:
					Input.action_press(a)
				else:
					Input.action_release(a)
		if frame % 7 == 0:
			inv.call("add_item", "pistol_ammo", 5)
		await get_tree().physics_frame
		await get_tree().process_frame
	for a in actions:
		Input.action_release(a)
	var zombies: int = get_tree().get_nodes_in_group("zombies").size()
	var pickups: int = get_tree().get_nodes_in_group("pickups").size()
	var projectiles: int = get_tree().get_nodes_in_group("projectiles").size()
	var puddles: int = get_tree().get_nodes_in_group("acid_puddles").size()
	print("STRESS END hp=", int(player.hp), " zombies=", zombies, " pickups=", pickups,
		" projectiles=", projectiles, " puddles=", puddles,
		" paused=", get_tree().paused, " time_scale=", Engine.time_scale)
	if is_instance_valid(_main):
		_main.queue_free()
		_main = null
	# Dar tiempo al árbol a liberar el mundo instanciado antes de salir,
	# evitando "ObjectDB instances were leaked at exit" en headless.
	for i in range(3):
		await get_tree().process_frame
	# La salida se programa ANTES de los assert: si uno falla en debug el
	# proceso ya tiene su codigo y el CI no puede dar verde aunque el arnes
	# se detenga. En release los asserts se compilan fuera y los `errors`
	# de arriba siguen gobernando la salida.
	get_tree().quit(1 if errors > 0 else 0)
	assert(player_valid, "STRESS TEST: jugador no valido al inicio")
	assert(not_paused, "STRESS TEST: arbol pausado al inicio")
	assert(time_scale_ok, "STRESS TEST: time_scale != 1.0 al inicio")
	assert(has_zombies, "STRESS TEST: sin zombis al inicio")
	assert(has_pickups, "STRESS TEST: sin pickups al inicio")
