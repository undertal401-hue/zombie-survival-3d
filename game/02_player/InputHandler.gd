class_name InputHandler
extends Node

var move_vector: Vector2 = Vector2.ZERO
var look_delta: Vector2 = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		look_delta += event.relative

func _process(_delta: float) -> void:
	move_vector = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	look_delta = Vector2.ZERO

func get_move_vector() -> Vector2:
	return move_vector

func consume_look_delta() -> Vector2:
	var v := look_delta
	look_delta = Vector2.ZERO
	return v
