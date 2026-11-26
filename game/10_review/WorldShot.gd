extends Node

## Arnés de captura visual del mundo (offscreen, tamaño fijo).
## Uso:
##   godot --path . res://10_review/WorldShot.tscn -- --out=/tmp/shot.png --x=-2100 --y=1350
## Argumentos opcionales: --zoom=1.0 --frames=30 --hide=NodoA,NodoB

const SHOT_SIZE: Vector2i = Vector2i(1280, 720)

var _out: String = "/tmp/opencode/world_shot.png"
var _x: float = -2100.0
var _y: float = 1350.0
var _zoom: float = 1.0
var _frames: int = 30
var _hide: PackedStringArray = PackedStringArray()
var _day: bool = false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"--out": _out = parts[1]
			"--x": _x = float(parts[1])
			"--y": _y = float(parts[1])
			"--zoom": _zoom = float(parts[1])
			"--frames": _frames = int(parts[1])
			"--hide": _hide = parts[1].split(",", false)
			"--day": _day = parts[1] != "0"

	var viewport: SubViewport = SubViewport.new()
	viewport.size = SHOT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)

	# El root aún está montando la escena: se espera un frame antes de añadir Main.
	await get_tree().process_frame

	var main: Node = load("res://07_house/Main.tscn").instantiate()
	viewport.add_child(main)
	get_tree().current_scene = main
	if main.has_method("skip_menu"):
		main.call("skip_menu")
	get_tree().paused = false
	if _day:
		var director: Node = main.get_node_or_null("WaveManager")
		if director != null:
			director.set("_phase", 1)
			director.set("_phase_t", 0.5)
			director.call("_apply_lighting", 0.01)
			print("WORLD_SHOT forced_day")

	for i in range(_frames):
		await get_tree().process_frame

	for node_name in _hide:
		var node: Node = _find_named(main, node_name)
		if node is CanvasItem:
			(node as CanvasItem).visible = false
			print("WORLD_SHOT hidden=", node_name)
		elif node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			print("WORLD_SHOT disabled=", node_name)

	var player: Node2D = main.get_node_or_null("Player") as Node2D
	if player != null:
		player.global_position = Vector2(_x, _y)
		var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			camera.zoom = Vector2(_zoom, _zoom)
			camera.position_smoothing_enabled = false
			camera.reset_smoothing()
			camera.make_current()

	for i in range(12):
		await get_tree().process_frame

	var ground: TileMap = main.get_node_or_null("Ground") as TileMap
	if ground != null:
		print("WORLD_SHOT ground_cells=", ground.get_used_cells(0).size(),
			" tileset=", ground.get_tileset() != null)
	print("WORLD_SHOT player=", player.global_position if player != null else Vector2.ZERO,
		" viewport=", viewport.size)

	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var dir: String = _out.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	image.save_png(_out)
	print("WORLD_SHOT out=%s size=%s pos=(%s,%s) zoom=%s" %
		[_out, str(image.get_size()), str(_x), str(_y), str(_zoom)])
	get_tree().quit(0)


func _find_named(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for child in node.get_children():
		var found: Node = _find_named(child, target)
		if found != null:
			return found
	return null
