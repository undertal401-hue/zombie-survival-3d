class_name MusicManager


extends Node
## Gestor de lista de reproduccion y transiciones de musica.
##
## No reproduce directamente: pide a AudioManager. Mantiene estado
## de pista actual, cola y transiciones por evento de juego.
## Accesible globalmente via `MusicManager` (class_name).

var current_track: StringName = &""
var playlist: Array[StringName] = []
var is_combat: bool = false
var _transition_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.shop_phase_started.connect(_on_shop_started)
	EventBus.game_over.connect(_on_game_over)
	EventBus.game_started.connect(_on_game_started)


func _process(delta: float) -> void:
	_transition_timer = maxf(_transition_timer - delta, 0.0)


func _on_game_started() -> void:
	playlist = [&"wave_ambient", &"wave_ambient_2", &"wave_ambient_3"]
	_request(&"wave_ambient")


func _on_wave_started(wave_number: int) -> void:
	is_combat = true
	if wave_number % 10 == 0:
		_request(&"boss_theme", 2.0)
	else:
		_request(&"combat_theme", 1.0)


func _on_wave_completed(_wave_number: int, _stats: Dictionary) -> void:
	is_combat = false
	_transition_timer = 3.0
	_request(&"victory_stinger", 0.5)


func _on_shop_started(_wave_number: int) -> void:
	is_combat = false
	_request(&"shop_phase", 1.0)


func _on_game_over(_reason: StringName) -> void:
	_request(&"game_over", 2.0)


## Pide cambio de pista a AudioManager.
func _request(track_id: StringName, fade: float = 1.0) -> void:
	if current_track == track_id:
		return
	current_track = track_id
	EventBus.music_requested.emit(track_id, fade)
