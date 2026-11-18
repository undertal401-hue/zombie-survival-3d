extends Node

func _ready() -> void:
	await get_tree().process_frame
	var main: Node = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for i in range(10):
		await get_tree().process_frame
	var player: CharacterBody2D = main.get_node("Player")
	var inv = get_node("/root/Inventory")
	inv.call("clear")
	inv.call("add_item", "pistol_ammo", 200)
	inv.call("add_item", "comida", 20)
	inv.call("add_item", "medkit", 5)

	var actions: Array[String] = ["move_forward", "move_back", "move_left", "move_right", "shoot", "attack", "reload"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var errors: int = 0
	print("=== STRESS TEST START ===")
	for frame in range(600):
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
	get_tree().quit(0)
