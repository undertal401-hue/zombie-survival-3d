extends Node

func _ready() -> void:
	await get_tree().process_frame
	var main: Node = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for i in range(10):
		await get_tree().process_frame
	for i in range(5):
		await get_tree().physics_frame

	var player: CharacterBody2D = main.get_node("Player")
	var extraction = main.get_node("Extraction")
	var inv = get_node("/root/Inventory")
	var hud = main.get_node("HUD")

	print("=== VICTORY TEST ===")

	inv.call("clear")
	inv.call("add_item", "combustible", 3)
	await get_tree().process_frame

	print("Fuel count: ", inv.call("count", "combustible"))
	print("Player pos: ", player.global_position)
	print("Extraction pos: ", extraction.global_position)
	print("Distance: ", player.global_position.distance_to(extraction.global_position))

	# Teleport al centro de la zona: body_entered tarda 2-3 frames físicos en
	# detectar el solapamiento (antes solo se esperaban 2 y el test daba falso).
	player.global_position = extraction.global_position
	for i in range(6):
		await get_tree().physics_frame
		await get_tree().process_frame

	print("After moving to extraction:")
	print("  Player pos: ", player.global_position)

	var end_overlay = hud.get_node("EndOverlay")
	var end_title: Label = hud.get_node("EndOverlay/EndPanel/EndTitle")
	var end_text: Label = hud.get_node("EndOverlay/EndPanel/EndText")
	var overlay_ok: bool = end_overlay.visible
	var paused_ok: bool = get_tree().paused
	var title_ok: bool = end_title.text.contains("EXITOSA")
	print("  EndOverlay visible: ", overlay_ok)
	print("  Game paused: ", paused_ok)
	print("  Title: ", end_title.text)
	print("  Text: ", end_text.text.replace("\n", " | "))
	print("  RESULT: ", "PASS" if (overlay_ok and paused_ok and title_ok) else "FAIL")

	await get_tree().process_frame
	await get_tree().process_frame

	print("=== VICTORY TEST COMPLETE ===")
	get_tree().quit(0)
