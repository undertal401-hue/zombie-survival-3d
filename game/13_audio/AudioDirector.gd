extends Node2D
class_name AudioDirector

## Audio 100% procedural: ningún archivo de sonido externo. Todas las formas de
## onda se generan como PCM16 en memoria con una semilla fija, de modo que una
## partida reproduce exactamente los mismos efectos que otra.
##
## Integración: añadir AudioDirector.tscn como hijo de Main. El nodo detecta por
## grupo/ruta al jugador, al WeaponController y al director de mundo, y escucha
## EventBus de forma defensiva (si una señal no existe, simplemente no se conecta).

const SEED: int = 20261117
const SAMPLE_RATE: int = 22050
const MASTER_BUS: String = "AudioDirectorMaster"
const SFX_BUS: String = "AudioDirectorSFX"
const AMBIENCE_BUS: String = "AudioDirectorAmbience"
const UI_BUS: String = "AudioDirectorUI"
const MAX_CALLABLE_ARGS: int = 4

const ALIASES: Dictionary = {
	"fired": "pistol", "fire": "pistol", "shoot": "pistol", "gunshot": "pistol",
	"pistol_shot": "pistol", "rifle": "rifle", "rifle_shot": "rifle",
	"shotgun_shot": "shotgun", "blast": "shotgun",
	"impact": "bullet_impact", "bullet_hit": "bullet_impact", "hit_wall": "bullet_impact",
	"melee": "melee_hit", "punch": "melee_hit", "slash": "melee_hit", "swing": "melee_hit",
	"zombie_hit": "zombie_hurt", "zombie_pain": "zombie_hurt", "zombie_injured": "zombie_hurt",
	"zombie_death": "zombie_die", "zombie_died": "zombie_die",
	"step": "footstep", "steps": "footstep", "footsteps": "footstep",
	"honk": "horn", "car_horn": "horn", "claxon": "horn",
	"engine": "engine_loop", "engine_idle": "engine_loop", "car_engine": "engine_loop",
	"engine_off": "engine_stop", "engine_shutdown": "engine_stop",
	"horde": "horde_alert", "horde_warning": "horde_alert", "alarm": "horde_alert",
	"wave": "wave_start", "wave_alert": "wave_start",
	"crafting": "craft", "craft_complete": "craft", "craft_completed": "craft",
	"pickup": "loot", "loot_pickup": "loot", "pickup_item": "loot",
	"hungry": "hunger", "stomach": "hunger", "stomach_rumble": "hunger",
	"damage": "player_hurt", "hurt": "player_hurt", "player_damage": "player_hurt",
	"click": "ui_click", "ui_select": "ui_click",
	"confirm": "ui_confirm", "ui_ok": "ui_confirm",
	"cancel": "ui_cancel", "ui_back": "ui_cancel",
	"notify": "notification", "ping": "notification",
	"wind": "wind_loop", "rain": "rain_loop", "storm": "rain_loop",
	"night": "night_loop", "tension": "tension_loop", "forest": "forest_loop",
}

const UI_IDS: Dictionary = {
	"ui_click": true, "ui_confirm": true, "ui_cancel": true, "notification": true,
}
const AMBIENCE_IDS: Dictionary = {
	"wind_loop": true, "rain_loop": true, "night_loop": true,
	"tension_loop": true, "forest_loop": true,
}

@export_range(0.0, 1.0, 0.01) var master_volume: float = 0.9
@export_range(0.0, 1.0, 0.01) var sfx_volume: float = 0.95
@export_range(0.0, 1.0, 0.01) var ambience_volume: float = 0.6
@export_range(0.0, 1.0, 0.01) var ui_volume: float = 0.8
@export_range(4, 64, 1) var max_voices: int = 24
@export_range(100.0, 6000.0, 10.0) var max_2d_distance: float = 1600.0
@export var listener_follow_player: bool = true

var _streams: Dictionary = {}
var _voices: Array[Node] = []
var _layers: Dictionary = {}
var _engine_player: AudioStreamPlayer2D = null
var _listener: AudioListener2D = null
var _player_node: Node2D = null
var _muted: bool = false
var _weather_kind: String = "clear"
var _ambience_override: String = ""
var _night: bool = false
var _tension: bool = false
var _tension_left: float = 0.0
var _footstep_timer: float = 0.0
var _engine_poll_timer: float = 0.0
var _hunger_low: bool = false
var _last_horde_alert_msec: int = -100000
var _last_zombie_alert_msec: int = -100000
var _last_horn_msec: int = -100000
var _last_engine_start_msec: int = -100000

## Archivos de ambiente externos (opcional): coloca OGG/WAV en
## res://assets/audio/ambience/ con nombres rain.ogg, wind.ogg, night.ogg, forest.ogg, tension.ogg
## Si existen, se usan en lugar de la síntesis procedural para mayor realismo.
var _external_ambience: Dictionary = {}


func _ready() -> void:
	add_to_group("audio_director")
	_ensure_buses()
	set_master_volume(master_volume)
	set_sfx_volume(sfx_volume)
	set_ambience_volume(ambience_volume)
	set_ui_volume(ui_volume)
	_listener = get_node_or_null("Listener2D") as AudioListener2D
	if _listener != null:
		_listener.make_current()
	_load_external_ambience()
	_resolve_scene_nodes()
	_connect_event_bus()
	_refresh_ambience()


func _load_external_ambience() -> void:
	var dir_path: String = "res://assets/audio/ambience/"
	var names: Array[String] = ["rain", "wind", "night", "forest", "tension"]
	for ambience_name in names:
		var path: String = dir_path + ambience_name + ".ogg"
		var stream: AudioStream = null
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
		else:
			var path_wav: String = dir_path + ambience_name + ".wav"
			if ResourceLoader.exists(path_wav):
				stream = load(path_wav) as AudioStream
		if stream == null:
			continue
		# Un archivo importado no loopea por defecto: sin esto la lluvia real
		# se cortaba en seco al terminar y volvía al sintetizador procedural.
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamWAV:
			var wav: AudioStreamWAV = stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.data.size() / 2)
		_external_ambience[ambience_name] = stream


func _exit_tree() -> void:
	_stop_engine(false)


## API pública ---------------------------------------------------------------

## Reproduce un efecto por identificador. `position` acepta Vector2 o Node2D;
## sin posición el sonido no es espacial (se usa para UI y feedback del jugador).
func play_sfx(id, position = null) -> bool:
	if _muted or not is_inside_tree():
		return false
	var raw: String = String(id).to_lower()
	var canonical: String = _canonical(raw)
	var pos: Variant = _as_position(position)
	if canonical == "engine_loop":
		_start_engine(pos)
		return true
	if canonical == "engine_stop":
		_stop_engine(true)
		return true
	return _play_one_shot(canonical, pos)


func _play_one_shot(canonical: String, pos: Variant) -> bool:
	if not is_inside_tree():
		return false
	if AudioServer.get_bus_index(MASTER_BUS) < 0:
		_ensure_buses()
	var stream: AudioStreamWAV = _stream_for(canonical) as AudioStreamWAV
	if stream == null:
		return false
	var bus_name: String = SFX_BUS
	if UI_IDS.has(canonical):
		bus_name = UI_BUS
	elif AMBIENCE_IDS.has(canonical):
		bus_name = AMBIENCE_BUS
	var player: Node
	if pos != null:
		var spatial := AudioStreamPlayer2D.new()
		spatial.name = "SfxVoice2D"
		spatial.stream = stream
		spatial.bus = bus_name
		spatial.max_distance = max_2d_distance
		spatial.attenuation = 1.0
		spatial.panning_strength = 0.7
		spatial.global_position = pos
		player = spatial
	else:
		var flat := AudioStreamPlayer.new()
		flat.name = "SfxVoice"
		flat.stream = stream
		flat.bus = bus_name
		player = flat
	add_child(player)
	player.call("play")
	_register_voice(player)
	return true


## Fija la capa base de ambiente. Admite: clear/calm/none, wind/fog, rain/storm,
## night, forest, day/dawn/dusk y horde/tension (capa de tensión temporal).
func set_ambience(kind) -> void:
	var key: String = String(kind).to_lower()
	match key:
		"none", "off", "silence", "calm":
			_weather_kind = "clear"
			_night = false
			_ambience_override = ""
			_tension = false
			_tension_left = 0.0
		"clear":
			_weather_kind = "clear"
			_night = false
			_ambience_override = ""
		"rain", "storm", "drizzle":
			_weather_kind = "rain"
			_ambience_override = ""
		"wind", "fog", "mist":
			_weather_kind = "wind"
			_ambience_override = ""
		"night", "dusk":
			_night = true
			_ambience_override = ""
		"day", "dawn":
			_night = false
			_ambience_override = ""
		"forest", "woods":
			_ambience_override = "forest"
		"horde", "tension":
			_set_tension(true, 60.0)
			return
		_:
			_weather_kind = key
			_ambience_override = ""
	_refresh_ambience()


func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_set_bus_gain(MASTER_BUS, master_volume)


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_set_bus_gain(SFX_BUS, sfx_volume)


func set_ambience_volume(v: float) -> void:
	ambience_volume = clampf(v, 0.0, 1.0)
	_set_bus_gain(AMBIENCE_BUS, ambience_volume)


func set_ui_volume(v: float) -> void:
	ui_volume = clampf(v, 0.0, 1.0)
	_set_bus_gain(UI_BUS, ui_volume)


func mute(value: bool) -> void:
	_muted = value
	var index: int = AudioServer.get_bus_index(MASTER_BUS)
	if index >= 0:
		AudioServer.set_bus_mute(index, value)
	if value:
		_stop_engine(false)


## Buses y mezcla ------------------------------------------------------------

func _ensure_buses() -> void:
	_add_bus(MASTER_BUS, "Master")
	_add_bus(SFX_BUS, MASTER_BUS)
	_add_bus(AMBIENCE_BUS, MASTER_BUS)
	_add_bus(UI_BUS, MASTER_BUS)


func _add_bus(bus_name: String, send_to: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(index, bus_name)
	if AudioServer.get_bus_index(send_to) >= 0:
		AudioServer.set_bus_send(index, send_to)


func _set_bus_gain(bus_name: String, gain: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, -80.0 if gain <= 0.001 else linear_to_db(gain))


## Conexiones defensivas -----------------------------------------------------

func _resolve_scene_nodes() -> void:
	var found: Node = get_tree().get_first_node_in_group("player")
	if found == null:
		found = get_node_or_null("../Player")
	if found is Node2D:
		_player_node = found as Node2D
	var weapons: Node = null
	if found != null:
		weapons = found.get_node_or_null("WeaponController")
	if weapons != null:
		_connect_local(weapons, "fire_requested", "_on_weapon_fired")
		_connect_local(weapons, "melee_attack", "_on_weapon_melee")
	var director: Node = get_tree().get_first_node_in_group("world_director")
	if director == null:
		for candidate in ["WaveManager", "HordeManager", "WorldDirector"]:
			director = get_node_or_null("../" + candidate)
			if director != null:
				break
	if director != null and _signal_arg_count(director, "phase_changed") <= 2:
		_connect_local(director, "phase_changed", "_on_world_phase")


func _connect_event_bus() -> void:
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus == null or not is_instance_valid(bus):
		return
	_connect_bus_signal(bus, "fired", "_on_bus_fired")
	_connect_bus_signal(bus, "zombie_died", "_on_bus_zombie_died")
	_connect_bus_signal(bus, "wave_started", "_on_bus_wave_started")
	_connect_bus_signal(bus, "horde_started", "_on_bus_horde_started")
	_connect_bus_signal(bus, "weather_changed", "_on_bus_weather_changed")
	_connect_bus_signal(bus, "craft_completed", "_on_bus_craft_completed")
	_connect_bus_signal(bus, "vehicle_state_changed", "_on_bus_vehicle_state_changed")
	_connect_bus_signal(bus, "zombie_alerted", "_on_bus_zombie_alerted")
	_connect_bus_signal(bus, "player_damaged", "_on_bus_player_damaged")
	_connect_bus_signal(bus, "player_hunger_changed", "_on_bus_player_hunger_changed")


func _connect_bus_signal(bus: Node, signal_name: String, method_name: String) -> void:
	if not bus.has_signal(signal_name):
		return
	var expected: int = _signal_arg_count(bus, signal_name)
	if expected > MAX_CALLABLE_ARGS:
		return
	var callback := Callable(self, method_name)
	if not bus.is_connected(signal_name, callback):
		bus.connect(signal_name, callback)


func _connect_local(node: Node, signal_name: String, method_name: String) -> void:
	if node == null or not is_instance_valid(node) or not node.has_signal(signal_name):
		return
	var callback := Callable(self, method_name)
	if not node.is_connected(signal_name, callback):
		node.connect(signal_name, callback)


func _signal_arg_count(node: Node, signal_name: String) -> int:
	for info in node.get_signal_list():
		if String(info.get("name", "")) == signal_name:
			return (info.get("args", []) as Array).size()
	return -1


func _on_bus_fired(a = null, b = null, c = null, _d = null) -> void:
	var pos: Variant = _as_position(a)
	if pos == null:
		pos = _as_position(b)
	if pos == null:
		pos = _as_position(c)
	var id: String = "pistol"
	if a is String and ALIASES.has(String(a).to_lower()):
		id = String(a).to_lower()
	elif a != null and not (a is Node2D) and not (a is Vector2):
		id = _weapon_sfx_id(a)
	play_sfx(id, pos)


func _on_bus_zombie_died(a = null, _b = null, _c = null, _d = null) -> void:
	play_sfx("zombie_die", _as_position(a))


func _on_bus_wave_started(a = null, b = null, c = null, d = null) -> void:
	_on_bus_horde_started(a, b, c, d)


func _on_bus_horde_started(_a = null, _b = null, _c = null, _d = null) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_horde_alert_msec >= 1200:
		_last_horde_alert_msec = now
		play_sfx("horde_alert")
	_set_tension(true, 60.0)


func _on_bus_weather_changed(kind = null, _b = null, _c = null, _d = null) -> void:
	set_ambience(kind)


func _on_bus_craft_completed(_a = null, _b = null, _c = null, _d = null) -> void:
	play_sfx("craft")


func _on_bus_vehicle_state_changed(vehicle = null, fuel = null, hp = null, _d = null) -> void:
	if vehicle == null or not (vehicle is Node2D):
		return
	var has_fuel: bool = true
	var has_hp: bool = true
	if fuel != null and (fuel is float or fuel is int):
		has_fuel = float(fuel) > 0.0
	if hp != null and (hp is float or hp is int):
		has_hp = float(hp) > 0.0
	if has_fuel and has_hp:
		_start_engine((vehicle as Node2D).global_position)
	else:
		_stop_engine(true)


func _on_bus_zombie_alerted(a = null, b = null, _c = null, _d = null) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_zombie_alert_msec < 320:
		return
	_last_zombie_alert_msec = now
	var pos: Variant = _as_position(a)
	if pos == null:
		pos = _as_position(b)
	if a is Vector2 and (b is float or b is int) and float(b) >= 800.0:
		if now - _last_horn_msec >= 900:
			_last_horn_msec = now
			play_sfx("horn", pos)
		return
	play_sfx("zombie_alert", pos)


func _on_bus_player_damaged(_a = null, _b = null, _c = null, _d = null) -> void:
	play_sfx("player_hurt")


func _on_bus_player_hunger_changed(hunger = null, _max_hunger = null, threshold = null, _d = null) -> void:
	if not (hunger is float or hunger is int):
		return
	var limit: float = 30.0
	if threshold != null and (threshold is float or threshold is int):
		limit = float(threshold)
	var hungry: bool = float(hunger) <= limit
	if hungry and not _hunger_low:
		_hunger_low = true
		play_sfx("hunger")
	elif not hungry and float(hunger) > limit + 5.0:
		_hunger_low = false


func _on_weapon_fired(weapon = null, from = null, _to = null) -> void:
	play_sfx(_weapon_sfx_id(weapon), from)


func _on_weapon_melee(_weapon = null, _direction = null) -> void:
	play_sfx("melee_hit", _player_position())


func _on_world_phase(phase = null, _progress = null) -> void:
	_night = String(phase).to_lower() == "night"
	_refresh_ambience()


## Bucle principal -----------------------------------------------------------

func _process(delta: float) -> void:
	_update_listener()
	_update_voices()
	_update_layers(delta)
	_update_footsteps(delta)
	_update_engine_poll(delta)
	if _tension:
		_tension_left -= delta
		if _tension_left <= 0.0:
			_set_tension(false, 0.0)


func _update_listener() -> void:
	if _listener == null or not is_instance_valid(_listener) or not listener_follow_player:
		return
	if _player_node == null or not is_instance_valid(_player_node):
		var candidate: Node = get_tree().get_first_node_in_group("player")
		if candidate is Node2D:
			_player_node = candidate as Node2D
	if _player_node != null:
		_listener.global_position = _player_node.global_position


func _update_voices() -> void:
	for i in range(_voices.size() - 1, -1, -1):
		var voice: Node = _voices[i]
		if not is_instance_valid(voice):
			_voices.remove_at(i)


func _register_voice(player: Node) -> void:
	while _voices.size() >= max_voices:
		var oldest: Node = _voices.pop_front()
		if is_instance_valid(oldest):
			oldest.call("stop")
			oldest.queue_free()
	_voices.append(player)
	if player.has_signal("finished"):
		player.connect("finished", func(): _on_voice_finished(player))


func _on_voice_finished(player: Node) -> void:
	_voices.erase(player)
	if is_instance_valid(player):
		player.queue_free()


func _update_footsteps(delta: float) -> void:
	if _player_node == null or not is_instance_valid(_player_node):
		return
	var velocity: Variant = _player_node.get("velocity")
	if not (velocity is Vector2):
		return
	var driving: bool = bool(_player_node.get("is_driving"))
	var speed: float = (velocity as Vector2).length()
	if driving or speed < 30.0:
		_footstep_timer = 0.0
		return
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_footstep_timer = lerpf(0.52, 0.27, clampf(speed / 340.0, 0.0, 1.0))
		play_sfx("footstep", _player_node.global_position)


func _update_engine_poll(delta: float) -> void:
	_engine_poll_timer -= delta
	if _engine_poll_timer > 0.0:
		return
	_engine_poll_timer = 0.5
	var position_now: Variant = null
	for node in get_tree().get_nodes_in_group("player_vehicle"):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		if not bool(node.get("occupied")):
			continue
		var fuel: float = float(node.get("fuel"))
		var hp: float = float(node.get("hp"))
		if fuel > 0.0 and hp > 0.0:
			position_now = (node as Node2D).global_position
			break
	if position_now != null:
		_start_engine(position_now)
	else:
		_stop_engine(true)


## Ambiente ------------------------------------------------------------------

func _refresh_ambience() -> void:
	var wanted: Dictionary = {}
	if _ambience_override != "":
		wanted[_ambience_override] = 0.85
	else:
		if _weather_kind == "rain" or _weather_kind == "storm":
			wanted["rain"] = 0.9
		elif _weather_kind == "wind" or _weather_kind == "fog":
			wanted["wind"] = 0.8
		if _night:
			wanted["night"] = 0.55
	if _tension:
		wanted["tension"] = 0.75
	for key in ["wind", "rain", "night", "tension", "forest"]:
		_set_layer_target(String(key), float(wanted.get(key, 0.0)))


func _set_tension(active: bool, seconds: float) -> void:
	_tension = active
	_tension_left = maxf(seconds, 0.0)
	_refresh_ambience()


func _set_layer_target(kind: String, target: float) -> void:
	if AudioServer.get_bus_index(MASTER_BUS) < 0:
		_ensure_buses()
	var layer: Dictionary
	if _layers.has(kind):
		layer = _layers[kind]
	else:
		var player := AudioStreamPlayer.new()
		player.name = "Ambience" + kind.capitalize()
		player.stream = _stream_for(kind + "_loop")
		player.bus = AMBIENCE_BUS
		player.volume_db = -80.0
		add_child(player)
		layer = { "player": player, "gain": 0.0, "target": 0.0 }
		_layers[kind] = layer
	layer["target"] = clampf(target, 0.0, 1.0)
	_layers[kind] = layer


func _update_layers(delta: float) -> void:
	var smoothing: float = 1.0 - exp(-delta / 0.28)
	for key in _layers.keys():
		var layer: Dictionary = _layers[key]
		var player: AudioStreamPlayer = layer["player"] as AudioStreamPlayer
		if player == null or not is_instance_valid(player):
			_layers.erase(key)
			continue
		var gain: float = float(layer["gain"])
		var target: float = float(layer["target"])
		gain = lerpf(gain, target, smoothing)
		layer["gain"] = gain
		_layers[key] = layer
		player.volume_db = -80.0 if gain <= 0.001 else linear_to_db(gain)
		if target > 0.0 and not player.playing and player.is_inside_tree():
			player.play()
		elif target <= 0.0 and gain <= 0.002 and player.playing:
			player.stop()


func _start_engine(pos: Variant) -> void:
	if _muted or not is_inside_tree():
		return
	if AudioServer.get_bus_index(MASTER_BUS) < 0:
		_ensure_buses()
	if _engine_player == null or not is_instance_valid(_engine_player):
		var player := AudioStreamPlayer2D.new()
		player.name = "EngineLoop"
		player.stream = _stream_for("engine_loop")
		player.bus = SFX_BUS
		player.max_distance = max_2d_distance * 2.0
		player.attenuation = 0.8
		add_child(player)
		_engine_player = player
	if pos != null:
		_engine_player.global_position = pos
	if not _engine_player.playing:
		_engine_player.play()
		var now: int = Time.get_ticks_msec()
		if now - _last_engine_start_msec >= 1500:
			_last_engine_start_msec = now
			play_sfx("engine_start", pos)


func _stop_engine(with_shutdown: bool) -> void:
	if _engine_player == null:
		return
	var last_position: Variant = _engine_player.global_position
	_engine_player.stop()
	_engine_player.queue_free()
	_engine_player = null
	if with_shutdown:
		_play_one_shot("engine_stop", last_position)


## Utilidades de posición ----------------------------------------------------

func _as_position(value: Variant, depth: int = 0) -> Variant:
	if value is Vector2:
		return value
	if value is Node2D and is_instance_valid(value):
		return (value as Node2D).global_position
	if depth < 2 and value is Array:
		for item in (value as Array):
			var found: Variant = _as_position(item, depth + 1)
			if found != null:
				return found
	return null


func _player_position() -> Variant:
	if _player_node != null and is_instance_valid(_player_node):
		return _player_node.global_position
	return null


func _weapon_sfx_id(weapon: Variant) -> String:
	if weapon == null or not (weapon is Object):
		return "pistol"
	var ammo: String = String(weapon.get("ammo_type")).to_lower()
	if ammo.contains("shotgun") or ammo.contains("shell"):
		return "shotgun"
	if ammo.contains("rifle") or ammo.contains("5.56"):
		return "rifle"
	return "pistol"


func _canonical(raw: String) -> String:
	var key: String = raw.to_lower()
	if ALIASES.has(key):
		return String(ALIASES[key])
	return key


## Síntesis ------------------------------------------------------------------

func _rng_for(id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_seed(id)
	return rng


func _stable_seed(id: String) -> int:
	var hash_value: int = 2166136261
	for i in range(id.length()):
		hash_value ^= id.unicode_at(i)
		hash_value = (hash_value * 16777619) & 0xFFFFFFFF
	return (SEED ^ hash_value) & 0xFFFFFFFF


func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(1, int(seconds * float(SAMPLE_RATE))))
	for i in range(out.size()):
		out[i] = 0.0
	return out


func _env(t: float, duration: float, attack: float) -> float:
	var a: float = maxf(attack, 0.0001)
	if t < a:
		return t / a
	var u: float = clampf((t - a) / maxf(duration - a, 0.0001), 0.0, 1.0)
	return exp(-4.0 * u) * (1.0 - u)


func _add_sweep(buf: PackedFloat32Array, from_hz: float, to_hz: float, amp: float,
		start: float, duration: float, shape: String, attack: float) -> void:
	var begin: int = int(start * float(SAMPLE_RATE))
	var count: int = int(duration * float(SAMPLE_RATE))
	var phase: float = 0.0
	for j in range(count):
		var i: int = begin + j
		if i >= buf.size():
			break
		var t: float = float(j) / float(SAMPLE_RATE)
		var u: float = clampf(t / maxf(duration, 0.0001), 0.0, 1.0)
		phase += TAU * lerpf(from_hz, to_hz, u) / float(SAMPLE_RATE)
		var cycle: float = phase - TAU * floor(phase / TAU)
		var wave: float = sin(phase)
		if shape == "saw":
			wave = cycle * 2.0 - 1.0
		elif shape == "square":
			wave = 1.0 if cycle < TAU * 0.5 else -1.0
		elif shape == "tri":
			wave = 1.0 - 4.0 * absf(cycle / TAU - 0.5)
		buf[i] += wave * amp * _env(t, duration, attack)


func _add_burst(buf: PackedFloat32Array, amp: float, start: float, duration: float,
		rng: RandomNumberGenerator, decay: float) -> void:
	var begin: int = int(start * float(SAMPLE_RATE))
	var count: int = int(duration * float(SAMPLE_RATE))
	for j in range(count):
		var i: int = begin + j
		if i >= buf.size():
			break
		var t: float = float(j) / float(SAMPLE_RATE)
		buf[i] += rng.randf_range(-1.0, 1.0) * amp * exp(-decay * t)


func _add_plateau_tone(buf: PackedFloat32Array, freq: float, amp: float,
		start: float, duration: float, attack: float, shape: String) -> void:
	var begin: int = int(start * float(SAMPLE_RATE))
	var count: int = int(duration * float(SAMPLE_RATE))
	for j in range(count):
		var i: int = begin + j
		if i >= buf.size():
			break
		var t: float = float(j) / float(SAMPLE_RATE)
		var rise: float = clampf(t / maxf(attack, 0.0001), 0.0, 1.0)
		var fall: float = clampf((duration - t) / 0.06, 0.0, 1.0)
		var wave: float = sin(TAU * freq * t)
		if shape == "square":
			wave = signf(wave) * 0.7
		elif shape == "saw":
			wave = fmod(t * freq, 1.0) * 2.0 - 1.0
		buf[i] += wave * amp * rise * fall


func _lowpass_in_place(buf: PackedFloat32Array, cutoff: float) -> void:
	var a: float = clampf(1.0 - exp(-TAU * cutoff / float(SAMPLE_RATE)), 0.0, 1.0)
	var y: float = 0.0
	for i in range(buf.size()):
		y += a * (buf[i] - y)
		buf[i] = y


func _highpass_in_place(buf: PackedFloat32Array, cutoff: float) -> void:
	var a: float = clampf(1.0 - exp(-TAU * cutoff / float(SAMPLE_RATE)), 0.0, 1.0)
	var previous_x: float = 0.0
	var previous_y: float = 0.0
	for i in range(buf.size()):
		var x: float = buf[i]
		previous_y = a * (previous_y + x - previous_x)
		previous_x = x
		buf[i] = previous_y


func _tremolo_in_place(buf: PackedFloat32Array, rate: float, depth: float) -> void:
	for i in range(buf.size()):
		var t: float = float(i) / float(SAMPLE_RATE)
		buf[i] *= 1.0 - depth + depth * (0.5 + 0.5 * sin(TAU * rate * t))


func _normalize(buf: PackedFloat32Array, peak: float) -> void:
	var maximum: float = 0.0
	for i in range(buf.size()):
		maximum = maxf(maximum, absf(buf[i]))
	if maximum <= 0.00001:
		return
	var scale: float = peak / maximum
	for i in range(buf.size()):
		buf[i] = clampf(buf[i] * scale, -0.98, 0.98)


func _periodic_noise(seconds: float, grid_hz: float, rng: RandomNumberGenerator,
		period: float = 0.0) -> PackedFloat32Array:
	var count: int = maxi(2, int(seconds * float(SAMPLE_RATE)))
	var repeat_seconds: float = period if period > 0.0 else seconds
	var grid_count: int = maxi(2, int(repeat_seconds * grid_hz))
	var values := PackedFloat32Array()
	values.resize(grid_count)
	for i in range(grid_count):
		values[i] = rng.randf_range(-1.0, 1.0)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		var p: float = float(i) / float(SAMPLE_RATE) * grid_hz
		var base: int = int(floor(p))
		var fraction: float = p - float(base)
		var i0: int = base % grid_count
		var i1: int = (i0 + 1) % grid_count
		fraction = fraction * fraction * (3.0 - 2.0 * fraction)
		out[i] = lerpf(values[i0], values[i1], fraction)
	return out


func _loop_slice(long_buf: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var period: int = maxi(1, int(seconds * float(SAMPLE_RATE)))
	var fade: int = maxi(1, mini(int(0.02 * float(SAMPLE_RATE)), period / 4))
	var start: int = maxi(0, long_buf.size() - period - fade)
	var out := PackedFloat32Array()
	out.resize(period)
	for j in range(period):
		if j < fade:
			var weight: float = float(j) / float(fade)
			out[j] = lerpf(long_buf[start + j + period], long_buf[start + j], weight)
		else:
			out[j] = long_buf[start + j]
	return out


func _add_loop_tone(buf: PackedFloat32Array, freq: float, amp: float, period: float) -> void:
	for i in range(buf.size()):
		var t: float = float(i) / float(SAMPLE_RATE)
		var pulse: float = 0.9 + 0.1 * sin(TAU * (2.0 / period) * t)
		buf[i] += sin(TAU * freq * t) * amp * pulse


func _add_wrap_tone(buf: PackedFloat32Array, period: float, start: float,
		freq: float, amp: float, duration: float, decay: float) -> void:
	var count: int = int(duration * float(SAMPLE_RATE))
	var begin: int = int(start * float(SAMPLE_RATE))
	var total: int = buf.size()
	for j in range(count):
		var i: int = (begin + j) % total
		var t: float = float(j) / float(SAMPLE_RATE)
		buf[i] += sin(TAU * freq * t) * amp * exp(-decay * t)


func _to_stream(buf: PackedFloat32Array, peak: float, loop: bool) -> AudioStreamWAV:
	_normalize(buf, peak)
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in range(buf.size()):
		var sample: int = int(round(clampf(buf[i], -1.0, 1.0) * 32767.0))
		data[2 * i] = sample & 0xFF
		data[2 * i + 1] = (sample >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = buf.size()
	return stream


func _stream_for(canonical: String) -> AudioStream:
	if _streams.has(canonical):
		return _streams[canonical] as AudioStream
	
	# Para bucles de ambiente: priorizar archivos externos (OGG/WAV) si existen.
	# Debe devolver AudioStream: castear este OGG a AudioStreamWAV daba null.
	if _external_ambience.has(canonical.replace("_loop", "")):
		var stream: AudioStream = _external_ambience[canonical.replace("_loop", "")]
		_streams[canonical] = stream
		return stream
	
	var rng: RandomNumberGenerator = _rng_for(canonical)
	var buf: PackedFloat32Array
	var loop: bool = false
	match canonical:
		"pistol": buf = _fx_pistol(rng)
		"shotgun": buf = _fx_shotgun(rng)
		"rifle": buf = _fx_rifle(rng)
		"bullet_impact": buf = _fx_impact(rng)
		"melee_hit": buf = _fx_melee(rng)
		"zombie_hurt": buf = _fx_zombie_hurt(rng)
		"zombie_die": buf = _fx_zombie_die(rng)
		"zombie_alert": buf = _fx_zombie_alert(rng)
		"footstep": buf = _fx_footstep(rng)
		"horn": buf = _fx_horn(rng)
		"engine_start": buf = _fx_engine_start(rng)
		"engine_stop": buf = _fx_engine_stop(rng)
		"horde_alert": buf = _fx_horde(rng)
		"wave_start": buf = _fx_wave(rng)
		"craft": buf = _fx_craft(rng)
		"loot": buf = _fx_loot(rng)
		"hunger": buf = _fx_hunger(rng)
		"player_hurt": buf = _fx_player_hurt(rng)
		"ui_click": buf = _fx_ui_click(rng)
		"ui_confirm": buf = _fx_ui_confirm(rng)
		"ui_cancel": buf = _fx_ui_cancel(rng)
		"notification": buf = _fx_notification(rng)
		"wind_loop": buf = _loop_wind(rng); loop = true
		"rain_loop": buf = _loop_rain(rng); loop = true
		"night_loop": buf = _loop_night(rng); loop = true
		"tension_loop": buf = _loop_tension(rng); loop = true
		"forest_loop": buf = _loop_forest(rng); loop = true
		"engine_loop": buf = _loop_engine(rng); loop = true
		_: return null
	var stream: AudioStreamWAV = _to_stream(buf, 0.88 if loop else 0.9, loop)
	_streams[canonical] = stream
	return stream


# --- Efectos de un solo disparo --------------------------------------------

func _fx_pistol(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.24)
	_add_sweep(buf, 1250.0, 190.0, 0.55, 0.0, 0.10, "sine", 0.001)
	_add_sweep(buf, 210.0, 65.0, 0.35, 0.0, 0.17, "tri", 0.002)
	_add_burst(buf, 0.9, 0.0, 0.05, rng, 55.0)
	_add_burst(buf, 0.25, 0.03, 0.14, rng, 22.0)
	_lowpass_in_place(buf, 4200.0)
	return buf


func _fx_shotgun(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.42)
	_add_sweep(buf, 850.0, 90.0, 0.55, 0.0, 0.18, "saw", 0.001)
	_add_sweep(buf, 160.0, 45.0, 0.5, 0.0, 0.32, "tri", 0.002)
	_add_burst(buf, 1.1, 0.0, 0.09, rng, 34.0)
	_add_burst(buf, 0.45, 0.04, 0.30, rng, 12.0)
	_lowpass_in_place(buf, 3000.0)
	return buf


## Fusil 5.56: crack más seco y agudo que la pistola, con cola metálica corta.
func _fx_rifle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.32)
	_add_sweep(buf, 2100.0, 320.0, 0.62, 0.0, 0.09, "sine", 0.001)
	_add_sweep(buf, 330.0, 80.0, 0.40, 0.0, 0.20, "saw", 0.002)
	_add_burst(buf, 1.0, 0.0, 0.045, rng, 72.0)
	_add_burst(buf, 0.35, 0.02, 0.18, rng, 30.0)
	_lowpass_in_place(buf, 5600.0)
	return buf


func _fx_impact(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.18)
	_add_burst(buf, 0.8, 0.0, 0.025, rng, 160.0)
	_add_plateau_tone(buf, 1720.0, 0.25, 0.0, 0.10, 0.001, "sine")
	_add_plateau_tone(buf, 2480.0, 0.16, 0.0, 0.07, 0.001, "sine")
	_add_sweep(buf, 150.0, 80.0, 0.3, 0.0, 0.11, "tri", 0.001)
	return buf


func _fx_melee(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.22)
	_add_burst(buf, 0.55, 0.0, 0.11, rng, 20.0)
	_highpass_in_place(buf, 260.0)
	_lowpass_in_place(buf, 2600.0)
	_add_sweep(buf, 130.0, 70.0, 0.45, 0.035, 0.15, "tri", 0.002)
	return buf


func _fx_zombie_hurt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.48)
	_add_sweep(buf, 125.0, 72.0, 0.6, 0.0, 0.40, "saw", 0.01)
	_add_burst(buf, 0.4, 0.0, 0.34, rng, 8.0)
	_lowpass_in_place(buf, 900.0)
	_tremolo_in_place(buf, 17.0, 0.25)
	return buf


func _fx_zombie_die(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.92)
	_add_sweep(buf, 160.0, 48.0, 0.65, 0.0, 0.72, "saw", 0.02)
	_add_burst(buf, 0.5, 0.0, 0.40, rng, 7.0)
	_add_sweep(buf, 105.0, 42.0, 0.45, 0.55, 0.32, "tri", 0.01)
	_lowpass_in_place(buf, 780.0)
	_tremolo_in_place(buf, 13.0, 0.2)
	return buf


func _fx_zombie_alert(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.40)
	_add_sweep(buf, 240.0, 95.0, 0.5, 0.0, 0.30, "saw", 0.006)
	_add_burst(buf, 0.45, 0.0, 0.18, rng, 18.0)
	_lowpass_in_place(buf, 1400.0)
	return buf


func _fx_footstep(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.16)
	_add_burst(buf, 0.6, 0.0, 0.06, rng, 70.0)
	_add_burst(buf, 0.28, 0.045, 0.05, rng, 90.0)
	_lowpass_in_place(buf, 750.0)
	_add_sweep(buf, 92.0, 55.0, 0.35, 0.0, 0.10, "sine", 0.001)
	return buf


func _fx_horn(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.62)
	_add_plateau_tone(buf, 418.0, 0.34, 0.0, 0.52, 0.025, "square")
	_add_plateau_tone(buf, 432.0, 0.28, 0.0, 0.52, 0.03, "square")
	_add_plateau_tone(buf, 209.0, 0.16, 0.0, 0.54, 0.02, "saw")
	_add_burst(buf, 0.08, 0.0, 0.03, rng, 100.0)
	_lowpass_in_place(buf, 2000.0)
	return buf


func _fx_engine_start(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.78)
	_add_sweep(buf, 55.0, 210.0, 0.45, 0.0, 0.62, "saw", 0.03)
	_add_burst(buf, 0.32, 0.0, 0.55, rng, 5.0)
	_lowpass_in_place(buf, 900.0)
	return buf


func _fx_engine_stop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.55)
	_add_sweep(buf, 190.0, 42.0, 0.45, 0.0, 0.48, "saw", 0.01)
	_add_burst(buf, 0.2, 0.0, 0.28, rng, 12.0)
	_lowpass_in_place(buf, 700.0)
	return buf


func _fx_horde(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(1.35)
	for i in range(3):
		var at: float = float(i) * 0.36
		_add_sweep(buf, 310.0, 740.0, 0.34, at, 0.20, "saw", 0.015)
		_add_sweep(buf, 700.0, 280.0, 0.20, at + 0.16, 0.18, "sine", 0.01)
		_add_sweep(buf, 82.0, 48.0, 0.4, at, 0.22, "tri", 0.005)
	_add_burst(buf, 0.18, 0.02, 0.9, rng, 3.0)
	_lowpass_in_place(buf, 2600.0)
	return buf


func _fx_wave(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.80)
	_add_plateau_tone(buf, 520.0, 0.3, 0.0, 0.22, 0.01, "square")
	_add_plateau_tone(buf, 660.0, 0.3, 0.28, 0.26, 0.01, "square")
	_add_sweep(buf, 90.0, 60.0, 0.28, 0.0, 0.55, "tri", 0.01)
	_add_burst(buf, 0.12, 0.0, 0.06, rng, 60.0)
	return buf


func _fx_craft(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.40)
	_add_burst(buf, 0.32, 0.0, 0.03, rng, 140.0)
	_add_burst(buf, 0.24, 0.10, 0.03, rng, 140.0)
	_add_sweep(buf, 480.0, 960.0, 0.32, 0.14, 0.22, "sine", 0.01)
	_add_plateau_tone(buf, 1320.0, 0.14, 0.32, 0.07, 0.002, "sine")
	return buf


func _fx_loot(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.52)
	_add_plateau_tone(buf, 660.0, 0.28, 0.0, 0.12, 0.002, "sine")
	_add_plateau_tone(buf, 880.0, 0.26, 0.11, 0.14, 0.002, "sine")
	_add_plateau_tone(buf, 1320.0, 0.22, 0.24, 0.22, 0.002, "sine")
	_add_burst(buf, 0.10, 0.0, 0.04, rng, 160.0)
	return buf


func _fx_hunger(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.78)
	_add_sweep(buf, 78.0, 126.0, 0.45, 0.0, 0.36, "sine", 0.06)
	_add_sweep(buf, 126.0, 64.0, 0.4, 0.36, 0.36, "sine", 0.03)
	_add_burst(buf, 0.22, 0.0, 0.60, rng, 4.0)
	_lowpass_in_place(buf, 360.0)
	_tremolo_in_place(buf, 6.5, 0.3)
	return buf


func _fx_player_hurt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.40)
	_add_burst(buf, 0.7, 0.0, 0.08, rng, 60.0)
	_add_sweep(buf, 200.0, 88.0, 0.45, 0.0, 0.24, "saw", 0.004)
	_add_sweep(buf, 120.0, 62.0, 0.3, 0.04, 0.28, "tri", 0.01)
	_lowpass_in_place(buf, 1700.0)
	return buf


func _fx_ui_click(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.07)
	_add_plateau_tone(buf, 1250.0, 0.3, 0.0, 0.045, 0.001, "sine")
	return buf


func _fx_ui_confirm(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.26)
	_add_plateau_tone(buf, 740.0, 0.26, 0.0, 0.10, 0.002, "sine")
	_add_plateau_tone(buf, 1110.0, 0.24, 0.10, 0.14, 0.002, "sine")
	return buf


func _fx_ui_cancel(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.22)
	_add_sweep(buf, 760.0, 380.0, 0.3, 0.0, 0.18, "sine", 0.002)
	return buf


func _fx_notification(_rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.42)
	_add_plateau_tone(buf, 880.0, 0.23, 0.0, 0.16, 0.004, "sine")
	_add_plateau_tone(buf, 1170.0, 0.19, 0.14, 0.24, 0.004, "sine")
	return buf


# --- Bucles ambientales (sin costuras) -------------------------------------

func _loop_wind(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var period: float = 4.0
	var long_buf: PackedFloat32Array = _periodic_noise(period * 3.0, 7.0, rng, period)
	var gust: PackedFloat32Array = _periodic_noise(period * 3.0, 0.5, rng, period)
	_lowpass_in_place(long_buf, 520.0)
	for i in range(long_buf.size()):
		var t: float = float(i) / float(SAMPLE_RATE)
		var mod: float = 0.55 + 0.5 * gust[i] + 0.12 * sin(TAU * 0.25 * t)
		long_buf[i] *= clampf(mod, 0.05, 1.2)
	return _loop_slice(long_buf, period)


func _loop_rain(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var period: float = 2.0
	var long_buf: PackedFloat32Array = _periodic_noise(period * 3.0, 240.0, rng, period)
	_highpass_in_place(long_buf, 850.0)
	var drops: int = 22
	for k in range(drops):
		var at: float = rng.randf_range(0.0, period)
		var freq: float = rng.randf_range(950.0, 2700.0)
		for repetition in range(3):
			var begin: int = int((at + float(repetition) * period) * float(SAMPLE_RATE))
			for j in range(int(0.02 * float(SAMPLE_RATE))):
				var index: int = (begin + j) % long_buf.size()
				var t: float = float(j) / float(SAMPLE_RATE)
				long_buf[index] += sin(TAU * freq * t) * exp(-t * 190.0) * 0.18
	return _loop_slice(long_buf, period)


func _loop_night(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var period: float = 4.0
	var long_buf: PackedFloat32Array = _buffer(period * 3.0)
	_add_loop_tone(long_buf, 55.0, 0.45, period)
	_add_loop_tone(long_buf, 82.5, 0.24, period)
	_add_loop_tone(long_buf, 110.0, 0.10, period)
	for k in range(18):
		var at: float = (float(k) / 18.0 + rng.randf_range(-0.008, 0.008)) * period
		var freq: float = rng.randf_range(3600.0, 4600.0)
		for repetition in range(3):
			_add_wrap_tone(long_buf, period, at + float(repetition) * period,
					freq, 0.14, 0.055, 85.0)
	return _loop_slice(long_buf, period)


func _loop_tension(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var period: float = 2.0
	var long_buf: PackedFloat32Array = _buffer(period * 3.0)
	var hiss: PackedFloat32Array = _periodic_noise(period * 3.0, 30.0, rng, period)
	_lowpass_in_place(hiss, 260.0)
	for i in range(long_buf.size()):
		var t: float = float(i) / float(SAMPLE_RATE)
		var pulse: float = 0.5 + 0.5 * sin(TAU * 1.0 * t)
		long_buf[i] += sin(TAU * 50.0 * t) * (0.34 + 0.26 * pulse)
		long_buf[i] += sin(TAU * 100.0 * t) * 0.09 * pulse
		long_buf[i] += hiss[i] * (0.5 + pulse)
	return _loop_slice(long_buf, period)


func _loop_forest(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var period: float = 4.0
	var long_buf: PackedFloat32Array = _periodic_noise(period * 3.0, 5.0, rng, period)
	_lowpass_in_place(long_buf, 900.0)
	for k in range(8):
		var at: float = rng.randf_range(0.0, period)
		var freq: float = rng.randf_range(1800.0, 3200.0)
		for repetition in range(3):
			_add_wrap_tone(long_buf, period, at + float(repetition) * period,
					freq, 0.1, 0.09, 45.0)
	return _loop_slice(long_buf, period)


func _loop_engine(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var period: float = 1.0
	var long_buf: PackedFloat32Array = _buffer(period * 3.0)
	var rumble: PackedFloat32Array = _periodic_noise(period * 3.0, 140.0, rng, period)
	_lowpass_in_place(rumble, 190.0)
	for i in range(long_buf.size()):
		var t: float = float(i) / float(SAMPLE_RATE)
		var mod: float = 0.86 + 0.14 * sin(TAU * 2.0 * t)
		var value: float = sin(TAU * 42.0 * t) * 0.42
		value += sin(TAU * 84.0 * t) * 0.20
		value += sin(TAU * 126.0 * t) * 0.09
		value += rumble[i] * 0.55
		long_buf[i] = value * mod
	return _loop_slice(long_buf, period)
