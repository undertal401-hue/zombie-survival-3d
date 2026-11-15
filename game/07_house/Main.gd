extends Node3D
## Escena raiz del juego (entrada principal) con generador de casa runtime.
##
## Genera la casa procedural usando RuntimeHouseGenerator (basado en algoritmos Atrium)
## y coloca al jugador en la posicion segura.

class_name Main


func _ready() -> void:
	var player: Node3D = get_node_or_null("Player") as Node3D
	if player == null:
		return
	
	# Generar la casa con RuntimeHouseGenerator
	_generate_house(player)
	
	# Iniciar la partida
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
	
	# Configurar con materiales del preset Atrium
	generator.seed = 36000  # Seed fijo para reproducibilidad
	generator.grid_size = Vector2i(3, 3)
	generator.room_size = Vector3(8, 3.5, 8)
	generator.floor_count = 2
	generator.branch_count = 4
	generator.critical_path_min = 3
	generator.wall_thickness = 0.2
	generator.door_width = 1.6
	generator.door_height = 2.3
	
	# Materiales estilo Atrium house
	generator.wall_material = StandardMaterial3D.new()
	generator.wall_material.albedo_color = Color(0.65, 0.67, 0.59, 1)
	generator.floor_material = StandardMaterial3D.new()
	generator.floor_material.albedo_color = Color(0.32, 0.23, 0.16, 1)
	generator.ceiling_material = StandardMaterial3D.new()
	generator.ceiling_material.albedo_color = Color(0.82, 0.80, 0.72, 1)
	
	add_child(generator)
	generator.generate()
	
	# Buscar punto de spawn del jugador
	var start_pos := _find_player_start(generator)
	start_pos.y = 0.9 # El origen del CharacterBody queda a la altura del centro de la cápsula.
	player.global_position = start_pos
	
	# Refrescar spawn points del spawner
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


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	pass # Replace with function body.
