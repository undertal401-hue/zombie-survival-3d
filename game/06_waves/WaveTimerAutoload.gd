extends Node
## Wrapper autoload para WaveTimer.

var timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var WaveTimer = load("res://06_waves/WaveTimer.gd")
	timer = WaveTimer.new()
	timer.name = "WaveTimer"
	add_child(timer)

func start(duration: float = 480.0) -> void:
	timer.start(duration)

func stop() -> void:
	timer.stop()

func advance(delta: float) -> void:
	timer.advance(delta)

var total: float:
	get: return timer.total
var remaining: float:
	get: return timer.remaining
var is_running: bool:
	get: return timer.is_running

func format_remaining() -> String:
	return timer.format_remaining()
