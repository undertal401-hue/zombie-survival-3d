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
