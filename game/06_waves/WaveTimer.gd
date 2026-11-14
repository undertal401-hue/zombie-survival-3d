extends Node
## Temporizador de fase de compra con duracion exacta (8:00 por defecto).
##
## Usa un nodo Timer real y expone `remaining`, `total` y senales de fin.
## Se pausa con el arbol (process_mode heredado) y es determinista.
## Accesible globalmente via `WaveTimer` (class_name).

signal timer_updated(remaining: float, total: float)
signal timer_finished
signal timer_started(duration: float)

var total: float = 480.0
var remaining: float = 480.0
var is_running: bool = false
var wave_number: int = 0
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.name = "Timer"
	_timer.one_shot = true
	_timer.wait_time = total
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)


## Inicia el temporizador.
## @param duration: segundos (480 = 8:00).
func start(duration: float = 480.0) -> void:
	total = maxf(duration, 0.0)
	remaining = total
	_timer.wait_time = total
	_timer.start()
	is_running = true
	timer_started.emit(total)
	timer_updated.emit(remaining, total)


## Detiene el temporizador.
func stop() -> void:
	_timer.stop()
	is_running = false
	remaining = total


## Pausa/reanudacion explicita (ademas de la pausa del arbol).
func set_paused(paused: bool) -> void:
	_timer.set_paused(paused)


## Avanza manualmente (tests): descuenta y emite.
## @param delta: incremento de tiempo.
func advance(delta: float) -> void:
	if not is_running:
		return
	remaining = maxf(remaining - delta, 0.0)
	timer_updated.emit(remaining, total)
	if remaining <= 0.0:
		_finish()


func _process(_delta: float) -> void:
	if is_running:
		remaining = maxf(_timer.time_left, 0.0)
		timer_updated.emit(remaining, total)


func _on_timeout() -> void:
	remaining = 0.0
	is_running = false
	timer_updated.emit(0.0, total)
	_finish()


func _finish() -> void:
	timer_finished.emit()
	EventBus.shop_phase_ended.emit(wave_number)


## Formatea el tiempo como M:SS.
func format_remaining() -> String:
	return format_remaining_static(remaining)


## Formatea segundos como M:SS sin necesidad de instancia.
## @param sec: segundos a formatear.
## @return cadena "M:SS".
static func format_remaining_static(sec: float) -> String:
	var seconds: int = int(ceil(sec))
	return "%d:%02d" % [seconds / 60, seconds % 60]
