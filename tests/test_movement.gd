## Test headless de movimiento: carga Main.tscn, pulsa W y comprueba que
## el jugador avanza y queda tocando el suelo. Salida != 0 si falla.
extends SceneTree

var player: CharacterBody3D
var frames: int = 0

func _init() -> void:
	var scene: PackedScene = load("res://Main.tscn")
	var main: Node3D = scene.instantiate() as Node3D
	root.add_child(main)
	player = main.get_node("Player") as CharacterBody3D
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	frames += 1
	if frames == 1:
		Input.action_press("move_forward")
		return
	if frames < 46:
		return
	Input.action_release("move_forward")
	var pos := player.global_position
	var moved := Vector3(0.0, 0.0, pos.z).length()
	print("[test] pos=", pos, " moved=", moved, " is_on_floor=", player.is_on_floor())
	if moved < 1.0 or not player.is_on_floor():
		printerr("[test] FALLO: el jugador no se movio o no esta en el suelo")
		quit(1)
		return
	print("[test] MOVIMIENTO OK")
	quit(0)
