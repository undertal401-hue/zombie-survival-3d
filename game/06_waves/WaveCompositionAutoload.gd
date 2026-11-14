extends Node
const WaveComposition := preload("res://06_waves/WaveComposition.gd")
var composition: WaveComposition

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	composition = WaveComposition.new()

func build(data) -> Array:
	return composition.build(data)

func set_seed(seed_value: int) -> void:
	composition.set_seed(seed_value)
