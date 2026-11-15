extends Node

var delta: float = 0.0
var elapsed: float = 0.0
var time_scale: float = 1.0

func _process(raw_delta: float) -> void:
	delta = raw_delta
	elapsed += raw_delta * time_scale
