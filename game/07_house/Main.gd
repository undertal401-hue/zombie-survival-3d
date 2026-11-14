extends Node3D
## Escena raiz del juego (entrada principal).
##
## Instancia el jugador, la casa procedural, los sistemas de combate,
## el spawner de zombies y la UI. Coloca al jugador en la posicion
## segura del baño una vez la casa esta generada.


func _ready() -> void:
	var player: Node3D = get_node_or_null("Player") as Node3D
	var house: Node = get_node_or_null("HouseGenerator")
	if player == null or house == null:
		return
	if house.has_method("get_player_start"):
		var start: Vector3 = house.get_player_start()
		start.y = maxf(start.y + 0.6, 1.0)
		player.global_position = start
	
	# Iniciar la partida
	var gm: GameManager = get_tree().root.get_node_or_null("GameManager") as GameManager
	if gm != null:
		gm.start_run()
	
	var wm: WaveManager = get_tree().root.get_node_or_null("WaveManager") as WaveManager
	if wm != null:
		wm.start_run()
	
	# Pasar datos de oleada al spawner
	var spawner: ZombieSpawner = get_node_or_null("ZombieSpawner") as ZombieSpawner
	if spawner != null and wm != null:
		spawner.set_wave_data(wm._current_data)
