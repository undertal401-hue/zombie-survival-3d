extends Node
## Autoload que orquesta las oleadas y la fase de compra.

enum WaveState {
	IDLE = 0,
	SPAWNING = 1,
	ACTIVE = 2,
	SHOP = 3,
	VICTORY = 4,
}

const WAVE_1: int = 1
const BASE_WAVE_COUNT: int = 10
const SHOP_DURATION: float = 480.0

var current_wave: int = 0
var state: int = WaveState.IDLE
var scaling
var composition
var timer
var alive_zombies: int = 0
var total_kills: int = 0
var _pending_spawns: int = 0
var _spawn_cooldown: float = 0.0
var _current_data


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	timer = load("res://06_waves/WaveTimer.gd").new()
	timer.name = "WaveTimer"
	add_child(timer)
	timer.timer_updated.connect(_on_timer_updated)
	EventBus.zombie_spawned.connect(_on_zombie_spawned)
	EventBus.zombie_died.connect(_on_zombie_died)
	EventBus.shop_phase_ended.connect(_on_shop_phase_ended)
	var WaveScaling = load("res://06_waves/WaveScaling.gd")
	scaling = WaveScaling.new()


func _process(delta: float) -> void:
	if state == WaveState.SPAWNING:
		_process_spawning(delta)
	elif state == WaveState.ACTIVE:
		_check_wave_complete()


func start_run() -> void:
	total_kills = 0
	alive_zombies = 0
	_start_wave(WAVE_1)


func start_wave(wave_number: int) -> void:
	current_wave = wave_number
	var WaveData = load("res://06_waves/WaveData.gd")
	var data = WaveData.new()
	data.wave_number = wave_number
	data.display_name = "Oleada %d" % wave_number
	data.spawn_count = int(scaling.base_count * pow(scaling.count_growth, wave_number - 1))
	data.spawn_interval = maxf(scaling.base_interval - wave_number * 0.05, 0.25)
	data.is_boss = wave_number % scaling.boss_every == 0
	data.reward_coins = int(scaling.base_reward * (1.0 + 0.1 * wave_number))
	data.add_type(&"walker", 10.0)
	if wave_number >= 2:
		data.add_type(&"runner", 6.0 + wave_number * 0.4)
	if wave_number >= 3:
		data.add_type(&"crawler", 5.0)
	if wave_number >= 4:
		data.add_type(&"spitter", 4.0)
	if wave_number >= 5:
		data.add_type(&"screamer", 3.0)
	if wave_number >= 6:
		data.add_type(&"tank", 2.5)
	if wave_number >= 8:
		data.add_type(&"brute", 2.0)
	if data.is_boss:
		data.add_type(&"mutated", 1.0)
	_current_data = data
	state = WaveState.SPAWNING
	_pending_spawns = _current_data.spawn_count
	_spawn_cooldown = 0.0
	if timer != null:
		timer.stop()
	EventBus.wave_started.emit(wave_number)
	if _current_data.is_boss:
		EventBus.boss_wave_started.emit(wave_number)
		EventBus.ui_notification.emit("Oleada de JEFE %d" % wave_number, &"warning")
	else:
		EventBus.ui_notification.emit(_current_data.display_name, &"info")


func _process_spawning(delta: float) -> void:
	_spawn_cooldown -= delta
	if _spawn_cooldown > 0.0:
		return
	_spawn_cooldown = _current_data.spawn_interval if _current_data != null else 1.0
	var batch: int = mini(_pending_spawns, 3)
	_pending_spawns -= batch
	EventBus.wave_spawn_batch.emit(batch, &"walker")
	if _pending_spawns <= 0:
		state = WaveState.ACTIVE


func _check_wave_complete() -> void:
	if _pending_spawns > 0 or alive_zombies > 0:
		return
	_complete_wave()


func _complete_wave() -> void:
	var stats := {"wave": current_wave, "kills": total_kills}
	EventBus.wave_completed.emit(current_wave, stats)
	_grant_reward()
	if current_wave >= BASE_WAVE_COUNT:
		state = WaveState.VICTORY
		EventBus.run_completed.emit()
		return
	_enter_shop()


func _grant_reward() -> void:
	var coins: int = 50
	Currency.add(coins, &"wave_reward")
	_drop_rare_upgrade()


func _drop_rare_upgrade() -> void:
	if scaling == null:
		return
	var chance: float = scaling.rare_drop_chance
	if randf() > chance:
		return
	var kinds: Array = [&"damage", &"speed", &"jump"]
	var kind = kinds[randi() % kinds.size()]
	var amount: float = 0.03 if kind == &"speed" else 0.05
	if kind == &"jump":
		amount = 0.10
	var PermanentUpgrade = load("res://11_items/PermanentUpgrade.gd")
	var upgrade = PermanentUpgrade.new()
	upgrade.kind = kind
	upgrade.amount = amount
	EventBus.rare_drop_acquired.emit(upgrade)


func _enter_shop() -> void:
	state = WaveState.SHOP
	if timer != null:
		timer.start(480.0)
	EventBus.shop_phase_started.emit(current_wave)
	EventBus.music_requested.emit(&"shop_phase", 1.0)


func end_shop() -> void:
	if state != WaveState.SHOP:
		return
	if timer != null:
		timer.stop()
	EventBus.music_requested.emit(&"wave_ambient", 1.0)
	_start_wave(current_wave + 1)


func reset() -> void:
	current_wave = 0
	state = WaveState.IDLE
	alive_zombies = 0
	_pending_spawns = 0
	total_kills = 0
	if timer != null:
		timer.stop()


func _on_zombie_spawned(_zombie: Node3D) -> void:
	if state == WaveState.SPAWNING or state == WaveState.ACTIVE:
		alive_zombies += 1


func _on_zombie_died(_zombie: Node3D, _killer: Node3D, _reward: int) -> void:
	alive_zombies = maxi(alive_zombies - 1, 0)
	total_kills += 1
	if state == WaveState.ACTIVE:
		_check_wave_complete()


func _on_timer_updated(remaining: float, total: float) -> void:
	EventBus.wave_timer_updated.emit(remaining, total)


func _on_shop_phase_ended(_wave_number: int) -> void:
	end_shop()


func _start_wave(wave_number: int) -> void:
	start_wave(wave_number)


func state_name() -> String:
	match state:
		WaveState.IDLE: return "IDLE"
		WaveState.SPAWNING: return "SPAWNING"
		WaveState.ACTIVE: return "ACTIVE"
		WaveState.SHOP: return "SHOP"
		WaveState.VICTORY: return "VICTORY"
	return "UNKNOWN"
