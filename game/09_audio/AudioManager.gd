extends Node
## Autoload de audio: SFX espaciales, musica, mixer y pooling de voces.
## Accesible globalmente como `AudioManager` (autoload singleton).

signal sfx_played(cue_id: StringName, position: Vector3)
signal music_changed(track_id: StringName)

const MASTER_BUS: StringName = &"Master"
const MUSIC_BUS: StringName = &"Music"
const SFX_BUS: StringName = &"SFX"

var _music_player: AudioStreamPlayer = null
var _music_fade_tween: Tween = null
var _sfx_pool: Array[AudioStreamPlayer3D] = []
var _pool_size: int = 24
var _pool_index: int = 0

var master_volume_db: float = 0.0
var music_volume_db: float = -6.0
var sfx_volume_db: float = -3.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_build_sfx_pool()
	_build_music_player()
	_load_settings()
	EventBus.sfx_requested.connect(_on_sfx_requested)
	EventBus.sfx_2d_requested.connect(_on_sfx_2d_requested)
	EventBus.music_requested.connect(_on_music_requested)
	EventBus.music_stopped.connect(_on_music_stopped)
	EventBus.footstep_requested.connect(_on_footstep)


## Crea un bus de mezcla si no existe y lo enruta al master.
## @param bus_name: nombre del bus a garantizar.
func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus(AudioServer.bus_count)
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, MASTER_BUS)


func _build_sfx_pool() -> void:
	for i: int in _pool_size:
		var player := AudioStreamPlayer3D.new()
		player.name = "SFX_%d" % i
		player.bus = SFX_BUS
		player.max_distance = 30.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_sfx_pool.append(player)


func _build_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)


func _load_settings() -> void:
	master_volume_db = ProjectSettings.get_setting("audio/mix/master_volume_db", 0.0)
	music_volume_db = ProjectSettings.get_setting("audio/mix/music_volume_db", -6.0)
	sfx_volume_db = ProjectSettings.get_setting("audio/mix/sfx_volume_db", -3.0)
	_apply_volumes()


func _apply_volumes() -> void:
	for pair in [[MASTER_BUS, master_volume_db], [MUSIC_BUS, music_volume_db], [SFX_BUS, sfx_volume_db]]:
		var idx: int = AudioServer.get_bus_index(pair[0])
		if idx != -1:
			AudioServer.set_bus_volume_db(idx, pair[1])


## Reproduce un SFX espacial en posicion mundial.
## @param cue_id: identificador del cue (mapeado a stream en 16_data/SFXTable.tres).
## @param position: posicion mundial.
func _on_sfx_requested(cue_id: StringName, position: Vector3) -> void:
	var stream: AudioStream = _get_stream(cue_id)
	if stream == null:
		return
	var player: AudioStreamPlayer3D = _sfx_pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool_size
	player.stream = stream
	player.global_position = position
	player.play()
	sfx_played.emit(cue_id, position)


## Reproduce un SFX 2D (UI, pickup).
func _on_sfx_2d_requested(cue_id: StringName) -> void:
	var stream: AudioStream = _get_stream(cue_id)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.bus = SFX_BUS
	player.stream = stream
	player.play()
	add_child(player)
	player.finished.connect(func(): player.queue_free())


## Busca el stream para un cue_id en la tabla de datos.
func _get_stream(cue_id: StringName) -> AudioStream:
	var table_path: String = "res://16_data/SFXTable.tres"
	if ResourceLoader.exists(table_path):
		var table: Variant = load(table_path)
		if table is Dictionary:
			var sounds: Dictionary = table as Dictionary
			var stream: Variant = sounds.get(cue_id, null)
			if stream is AudioStream:
				return stream as AudioStream
	# Fallback: intenta cargar directo
	var path: String = "res://assets/audio/sfx/%s.ogg" % cue_id
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


## Cambia la musica con fade.
## @param track_id: identificador de la pista.
## @param fade: duracion del fade en segundos.
func _on_music_requested(track_id: StringName, fade: float = 1.0) -> void:
	var stream: AudioStream = _get_music_stream(track_id)
	if stream == null:
		return
	if _music_fade_tween != null:
		_music_fade_tween.kill()
	if _music_player.playing:
		_music_fade_tween = create_tween()
		_music_fade_tween.tween_property(_music_player, "volume_db", -80.0, fade)
		_music_fade_tween.finished.connect(func() -> void: _start_music(stream, fade))
	else:
		_start_music(stream, fade)
	music_changed.emit(track_id)


func _start_music(stream: AudioStream, fade: float) -> void:
	_music_player.stream = stream
	_music_player.volume_db = -80.0
	_music_player.play()
	_music_fade_tween = create_tween()
	_music_fade_tween.tween_property(_music_player, "volume_db", music_volume_db, fade)


func _get_music_stream(track_id: StringName) -> AudioStream:
	var table: Resource = load("res://16_data/MusicTable.tres")
	if table != null and table.has(track_id):
		return table[track_id] as AudioStream
	var path: String = "res://assets/audio/music/%s.ogg" % track_id
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


func _on_music_stopped(fade: float = 1.0) -> void:
	if _music_fade_tween != null:
		_music_fade_tween.kill()
	if _music_player.playing:
		_music_fade_tween = create_tween()
		_music_fade_tween.tween_property(_music_player, "volume_db", -80.0, fade)
		_music_fade_tween.finished.connect(func() -> void: _music_player.stop())


func _on_footstep(surface: StringName, position: Vector3) -> void:
	var cue: StringName = &"footstep_%s" % surface
	var stream: AudioStream = _get_stream(cue)
	if stream == null:
		stream = _get_stream(&"footstep_concrete")
	if stream == null:
		return
	var player: AudioStreamPlayer3D = _sfx_pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool_size
	player.stream = stream
	player.global_position = position
	player.volume_db = -6.0
	player.play()


## Ducking de musica (pausa, menu).
## @param target_db: volumen objetivo en dB.
func duck_music(target_db: float) -> void:
	if _music_fade_tween != null:
		_music_fade_tween.kill()
	_music_fade_tween = create_tween()
	_music_fade_tween.tween_property(_music_player, "volume_db", target_db, 0.5)


## Getters/Setters de volumen con persistencia.
func set_master_volume_db(db: float) -> void:
	master_volume_db = clampf(db, -80.0, 0.0)
	_apply_volumes()
	ProjectSettings.set_setting("audio/mix/master_volume_db", master_volume_db)


func set_music_volume_db(db: float) -> void:
	music_volume_db = clampf(db, -80.0, 0.0)
	_apply_volumes()
	ProjectSettings.set_setting("audio/mix/music_volume_db", music_volume_db)


func set_sfx_volume_db(db: float) -> void:
	sfx_volume_db = clampf(db, -80.0, 0.0)
	_apply_volumes()
	ProjectSettings.set_setting("audio/mix/sfx_volume_db", sfx_volume_db)


func get_master_volume_db() -> float: return master_volume_db
func get_music_volume_db() -> float: return music_volume_db
func get_sfx_volume_db() -> float: return sfx_volume_db