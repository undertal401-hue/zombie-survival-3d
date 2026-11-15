extends Node
## Reloj global del juego.
##
## Centraliza delta, delta escalado y tiempo de juego. Los sistemas leen
## `GameClock.delta` en vez de `_process(delta)` para respetar pausa/escala.
## Ademas emite `tick` para telemetry y tests.
## Accesible globalmente como `GameClock` (autoload singleton).

signal tick(delta: float, scaled_delta: float, elapsed: float)
signal time_scale_changed(scale: float)
signal clock_paused
signal clock_resumed

var delta: float = 0.0
var scaled_delta: float = 0.0
var elapsed: float = 0.0
var time_scale: float = 1.0
var is_paused: bool = false:
	set(value):
		if is_paused == value:
			return
		is_paused = value
		var _tree := get_tree()
		if _tree != null:
			_tree.paused = value
		if value:
			clock_paused.emit()
		else:
			clock_resumed.emit()


func _process(raw_delta: float) -> void:
	delta = raw_delta
	scaled_delta = raw_delta * time_scale
	if not is_paused:
		elapsed += scaled_delta
	tick.emit(delta, scaled_delta, elapsed)


## Ajusta la escala de tiempo (slow-motion, pausa de cinematica, etc).
## @param scale: factor > 0. Se limita a [0.01, 4.0].
func set_time_scale(scale: float) -> void:
	time_scale = clampf(scale, 0.01, 4.0)
	Engine.time_scale = time_scale
	time_scale_changed.emit(time_scale)


## Reinicia el reloj a cero (nueva partida).
func reset() -> void:
	delta = 0.0
	scaled_delta = 0.0
	elapsed = 0.0
	time_scale = 1.0
	Engine.time_scale = 1.0
	is_paused = false
	time_scale_changed.emit(1.0)
