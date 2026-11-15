class_name InputHandler
extends Node

var move_vector: Vector2 = Vector2.ZERO

func _process(_delta: float) -> void:
	move_vector = Input.get_vector("move_left", "move_right", "move_back", "move_forward")

func get_move_vector() -> Vector2:
	return move_vector
