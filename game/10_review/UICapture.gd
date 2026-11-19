extends Node

## Captura temporal del HUD/inventario abierto para inspección visual.

func _ready() -> void:
	await get_tree().process_frame
	var main: Node = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for i in range(10):
		await get_tree().process_frame

	var menu: CanvasLayer = main.get_node("InventoryMenu") as CanvasLayer
	menu.call("open")
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "user://ui_after.png"
	image.save_png(path)
	print("CAPTURE path=", path, " global=", ProjectSettings.globalize_path(path), " size=", image.get_size())
	get_tree().quit(0)
