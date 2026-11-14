extends Node
## Gestor de audio global: musica, SFX, voces y buses.

const MAX_VOICES: int = 24
const DEFAULT_FADE: float = 1.0

@export var master_volume_db: float = 0.0
@export var music_volume_db: float = -6.0
@export var sfx_volume_db: float = -3.0

var _music_player: AudioStreamPlayer
var _music_fade_tween: Tween
var _sfx_players: Array[AudioStreamPlayer3D] = []
var _voice_players: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_music_player()
	EventBus.music_requested.connect(_on_music_requested)
	EventBus.sfx_requested.connect(_on_sfx_requested)
	EventBus.voice_requested.connect(_on_voice_requested)
	EventBus.shop_phase_started.connect(_on_shop_phase)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.duck_music.connect(_on_duck_music)
	
	# Aplicar volumenes de forma segura (solo buses que existan)
	var bus_count = AudioServer.get_bus_count()
	if bus_count > 0:
		AudioServer.set_bus_volume_db(0, master_volume_db)  # Master
	if bus_count > 1:
		AudioServer.set_bus_volume_db(1, music_volume_db)   # Music
	if bus_count > 2:
		AudioServer.set_bus_volume_db(2, sfx_volume_db)     # SFX


## Crea el reproductor de musica.
func _setup_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Music"
	_music_player.autoplay = false
	add_child(_music_player)
	_music_player.finished.connect(_on_music_stopped)


## Reduce/restaura volumen de musica (para pausa, tienda).
func _on_duck_music(level: float) -> void:
	music_volume_db = level
	if _music_player != null:
		_music_player.volume_db = level


## Reproduce una pista de musica (no hace nada si no existe el archivo).
func _on_music_requested(track_id: StringName, fade: float = DEFAULT_FADE) -> void:
	var stream: AudioStream = _get_music_stream(track_id)
	if stream == null:
		# No hay musica: simplemente no reproducir nada
		return
	if _music_player.playing:
		_music_fade_tween = create_tween()
		_music_fade_tween.tween_property(_music_player, "volume_db", -80.0, fade * 0.5)
		_music_fade_tween.finished.connect(func(): _switch_music(stream, fade))
	else:
		_switch_music(stream, fade)


func _switch_music(stream: AudioStream, fade: float) -> void:
	_music_player.stream = stream
	_music_player.volume_db = -80.0
	_music_player.play()
	_music_fade_tween = create_tween()
	_music_fade_tween.tween_property(_music_player, "volume_db", music_volume_db, fade)


func _get_music_stream(track_id: StringName) -> AudioStream:
	var table: Resource = load("res://16_data/MusicTable.tres")
	if table != null and table.has(track_id):
		var track_path: String = table.get_track(track_id)
		if track_path != null and track_path != "" and ResourceLoader.exists(track_path):
			return load(track_path) as AudioStream
	var path: String = "res://assets/audio/music/%s.ogg" % track_id
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null  # No hay musica


func _on_music_stopped() -> void:
	if _music_fade_tween != null:
		_music_fade_tween.kill()
	if _music_player.playing:
		_music_fade_tween = create_tween()
		_music_fade_tween.tween_property(_music_player, "volume_db", -80.0, 1.0)
		_music_fade_tween.finished.connect(func(): _music_player.stop())


## Reproduce un efecto de sonido (SFX) en posicion 3D.
func _on_sfx_requested(sfx_id: StringName, position: Vector3, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _get_sfx_stream(sfx_id)
	if stream == null:
		return
	var player: AudioStreamPlayer3D = _get_sfx_player()
	player.stream = stream
	player.volume_db = volume_db
	player.global_position = position
	player.play()


func _get_sfx_stream(sfx_id: StringName) -> AudioStream:
	var path: String = "res://assets/audio/sfx/%s.ogg" % sfx_id
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


func _get_sfx_player() -> AudioStreamPlayer3D:
	for p in _sfx_players:
		if not p.playing:
			return p
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.bus = "SFX"
	player.unit_db = 0.0
	add_child(player)
	_sfx_players.append(player)
	return player


## Reproduce una voz (dialogo, gritos, etc).
func _on_voice_requested(voice_id: StringName, position: Vector3) -> void:
	var path: String = "res://assets/audio/voices/%s.ogg" % voice_id
	if not ResourceLoader.exists(path):
		return
	var player: AudioStreamPlayer3D = _get_voice_player()
	player.stream = load(path) as AudioStream
	player.global_position = position
	player.play()


func _get_voice_player() -> AudioStreamPlayer3D:
	for p in _voice_players:
		if not p.playing:
			return p
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.bus = "SFX"
	player.unit_db = 0.0
	add_child(player)
	_voice_players.append(player)
	return player


## Cambia el volumen master.
func set_master_volume_db(db: float) -> void:
	master_volume_db = db
	var bus_count = AudioServer.get_bus_count()
	if bus_count > 0:
		AudioServer.set_bus_volume_db(0, db)


## Cambia el volumen de musica.
func set_music_volume_db(db: float) -> void:
	music_volume_db = db
	var bus_count = AudioServer.get_bus_count()
	if bus_count > 1:
		AudioServer.set_bus_volume_db(1, db)
	if _music_player != null:
		_music_player.volume_db = db


## Cambia el volumen de SFX.
func set_sfx_volume_db(db: float) -> void:
	sfx_volume_db = db
	var bus_count = AudioServer.get_bus_count()
	if bus_count > 2:
		AudioServer.set_bus_volume_db(2, db)


## Obtiene el volumen master actual.
func get_master_volume_db() -> float:
	return master_volume_db


## Obtiene el volumen de musica actual.
func get_music_volume_db() -> float:
	return music_volume_db


## Obtiene el volumen de SFX actual.
func get_sfx_volume_db() -> float:
	return sfx_volume_db


## Fase de tienda: musica de tienda.
func _on_shop_phase(wave_number: int) -> void:
	EventBus.music_requested.emit(&"shop_phase", 2.0)


## Inicio de oleada: musica de oleada.
func _on_wave_started(wave_number: int) -> void:
	if wave_number % 10 == 0:
		EventBus.music_requested.emit(&"boss_wave", 2.0)
	else:
		EventBus.music_requested.emit(&"wave_ambient", 2.0)
