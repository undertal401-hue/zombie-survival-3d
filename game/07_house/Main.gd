extends Node3D
class_name Main


func _ready() -> void:
	var player: Node3D = get_node_or_null("Player") as Node3D
	if player == null:
		return

	_generate_house(player)

	# Solo una vez
	var gm: GameManager = get_tree().root.get_node_or_null("GameManager") as GameManager
	if gm != null:
		gm.start_run()

	var wm: WaveManager = get_tree().root.get_node_or_null("WaveManager") as WaveManager
	if wm != null:
		wm.start_run()

	var spawner: ZombieSpawner = get_node_or_null("ZombieSpawner") as ZombieSpawner
	if spawner != null and wm != null:
		spawner.set_wave_data(wm._current_data)


func _generate_house(player: Node3D) -> void:
	var generator: RuntimeHouseGenerator = RuntimeHouseGenerator.new()
	generator.name = "HouseGenerator"

	generator.seed = 36000
	generator.grid_size = Vector2i(3, 3)
	generator.room_size = Vector3(8, 3.5, 8)
	generator.floor_count = 2
	generator.branch_count = 4
	generator.critical_path_min = 3
	generator.wall_thickness = 0.2
	generator.door_width = 1.6
	generator.door_height = 2.3

	generator.wall_material = StandardMaterial3D.new()
	generator.wall_material.albedo_color = Color(0.65, 0.67, 0.59, 1)
	generator.floor_material = StandardMaterial3D.new()
	generator.floor_material.albedo_color = Color(0.32, 0.23, 0.16, 1)
	generator.ceiling_material = StandardMaterial3D.new()
	generator.ceiling_material.albedo_color = Color(0.82, 0.80, 0.72, 1)

	add_child(generator)
	generator.generate()

	var start_pos: Vector3 = _find_player_start(generator)
	if start_pos == Vector3.ZERO:
		start_pos = Vector3(0.0, 1.0, 0.0)

	start_pos.y = 0.9
	player.global_position = start_pos

	var spawner: ZombieSpawner = get_node_or_null("ZombieSpawner") as ZombieSpawner
	if spawner != null:
		spawner._refresh_spawn_points()


func _find_player_start(generator: Node3D) -> Vector3:
	for child in generator.get_children():
		if child.name.begins_with("Room_0"):
			return child.global_position

	for child in generator.get_children():
		if child.name.begins_with("Room_"):
			return child.global_position

	return Vector3.ZERO
