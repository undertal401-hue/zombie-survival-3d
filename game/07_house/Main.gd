extends Node3D

@onready var player: CharacterBody3D = $Player

func _ready() -> void:
	player.add_to_group("player")
	player.position = Vector3(0, 1.2, 0)

	var zombie := preload("res://03_zombies/Zombie.gd").new()
	zombie.position = Vector3(5, 1, 5)
	add_child(zombie)
