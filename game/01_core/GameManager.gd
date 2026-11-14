extends Node
## Maquina de estados del flujo de partida.

enum GameState {
	MENU,
	PLAYING,
	SHOP,
	PAUSED,
	GAME_OVER,
	VICTORY,
	CHECKPOINT,
}

const STATE_NAMES: Dictionary = {
	GameState.MENU: "MENU",
	GameState.PLAYING: "PLAYING",
	GameState.SHOP: "SHOP",
	GameState.PAUSED: "PAUSED",
	GameState.GAME_OVER: "GAME_OVER",
	GameState.VICTORY: "VICTORY",
	GameState.CHECKPOINT: "CHECKPOINT",
}

signal state_will_change(next_state: int)
signal run_stat_recorded(stat_id: StringName, value: float)

var current_state: int = GameState.MENU
var previous_state: int = GameState.MENU
var is_run_active: bool = false
var run_start_elapsed: float = 0.0
var difficulty = &"normal"
var run_stats: Dictionary = {}
var checkpoint_id = &""


func _ready() -> void:
	get_tree().paused = false
	EventBus.game_state_changed.connect(_on_game_state_changed)
	EventBus.run_completed.connect(victory)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if current_state == GameState.PLAYING:
			pause()
		elif current_state == GameState.PAUSED:
			resume()


func start_run(start_wave: int = 1) -> void:
	run_stats.clear()
	is_run_active = true
	run_start_elapsed = GameClock.elapsed
	checkpoint_id = &""
	set_state(GameState.PLAYING)
	EventBus.game_started.emit()
	EventBus.ui_notification.emit("Oleada %d" % start_wave, &"info")


func pause() -> void:
	if current_state != GameState.PLAYING:
		return
	set_state(GameState.PAUSED)
	EventBus.pause_requested.emit()


func resume() -> void:
	if current_state != GameState.PAUSED:
		return
	set_state(GameState.PLAYING)
	EventBus.resume_requested.emit()


func enter_shop_phase(wave_number: int = 1) -> void:
	if current_state != GameState.PLAYING:
		return
	set_state(GameState.SHOP)
	EventBus.shop_phase_started.emit(wave_number)


func exit_shop_phase() -> void:
	if current_state != GameState.SHOP:
		return
	set_state(GameState.PLAYING)


func game_over(reason: StringName = &"killed") -> void:
	if not is_run_active:
		return
	is_run_active = false
	record_stat("duration", GameClock.elapsed - run_start_elapsed)
	set_state(GameState.GAME_OVER)
	EventBus.game_over.emit(reason)


func victory() -> void:
	is_run_active = false
	set_state(GameState.VICTORY)
	EventBus.game_victory.emit()


func record_stat(stat_id: StringName, value: float) -> void:
	if run_stats.has(stat_id):
		run_stats[stat_id] = maxf(float(run_stats[stat_id]), value)
	else:
		run_stats[stat_id] = value
	run_stat_recorded.emit(stat_id, value)


func set_state(next_state: int) -> void:
	if next_state == current_state:
		return
	state_will_change.emit(next_state)
	previous_state = current_state
	current_state = next_state
	EventBus.game_state_changed.emit(previous_state, current_state)


## True si el juego esta en estado PLAYING.
func is_playing() -> bool:
	return current_state == GameState.PLAYING


func state_name(state: int = current_state) -> String:
	return STATE_NAMES.get(state, "UNKNOWN")


func _on_game_state_changed(previous: int, current: int) -> void:
	match current:
		GameState.PAUSED:
			AudioManager.duck_music(0.35)
		GameState.PLAYING:
			AudioManager.duck_music(1.0)
