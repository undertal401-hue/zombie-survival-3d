extends Node

## Captura temporal del HUD/inventario abierto para inspección visual.

## Default EXACTAMENTE igual al path usado hoy (user://), para no romper a quien consume el PNG.
const DEFAULT_CAPTURE_DIR := "user://"
## QA_CAPTURE_DIR permite redirigir la captura; sin entorno se usa el default.
var capture_dir: String = OS.get_environment("QA_CAPTURE_DIR") if not OS.get_environment("QA_CAPTURE_DIR").is_empty() else DEFAULT_CAPTURE_DIR

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
	if capture_dir != DEFAULT_CAPTURE_DIR:
		DirAccess.make_dir_recursive_absolute(capture_dir)
	var path: String = capture_dir.path_join("ui_after.png")
	image.save_png(path)
	print("CAPTURE path=", path, " global=", ProjectSettings.globalize_path(path), " size=", image.get_size())
	get_tree().quit(0)
