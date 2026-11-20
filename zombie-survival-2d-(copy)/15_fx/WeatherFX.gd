extends Node2D
class_name WeatherFX

## Clima 100% procedural dibujado con CanvasItem._draw(): líneas de lluvia,
## motas de viento y niebla animada. Sigue a WorldDirector de forma defensiva
## mediante EventBus.weather_changed y, si está disponible, la señal local.

const RAIN_COUNT: int = 96
const MOTE_COUNT: int = 44
const FOG_COUNT: int = 9

var _rng := RandomNumberGenerator.new()
var _rain: Array = []
var _motes: Array = []
var _fog_blobs: Array = []
var _t: float = 0.0
var _weather: StringName = &"clear"
var _target_intensity: float = 0.0
var _rain_amount: float = 0.0
var _wind_amount: float = 0.0
var _fog_amount: float = 0.0
var _was_visible: bool = false
var _director: Node = null


func _init() -> void:
	_rng.seed = 20261117 + 77


func _ready() -> void:
	_build_layout()
	_connect_sources()


func _exit_tree() -> void:
	_disconnect_sources()


func _build_layout() -> void:
	var rng := _world_rng()
	_rain.clear()
	for _i in range(RAIN_COUNT):
		_rain.append({
			"x": rng.randf(),
			"y": rng.randf(),
			"speed": rng.randf_range(420.0, 780.0),
			"len": rng.randf_range(9.0, 20.0),
		})
	_motes.clear()
	for _i in range(MOTE_COUNT):
		_motes.append({
			"x": rng.randf(),
			"y": rng.randf(),
			"speed": rng.randf_range(45.0, 130.0),
			"phase": rng.randf_range(0.0, TAU),
			"len": rng.randf_range(4.0, 13.0),
		})
	_fog_blobs.clear()
	for _i in range(FOG_COUNT):
		_fog_blobs.append({
			"x": rng.randf(),
			"y": rng.randf_range(0.08, 0.92),
			"r": rng.randf_range(110.0, 260.0),
			"scale": rng.randf_range(0.8, 1.5),
			"speed": rng.randf_range(0.006, 0.022),
			"phase": rng.randf_range(0.0, TAU),
		})


# --- Conexiones defensivas --------------------------------------------------

func _connect_sources() -> void:
	if EventBus != null and is_instance_valid(EventBus):
		var bus_signal := StringName("weather_changed")
		var bus_callback := Callable(self, "_on_bus_weather")
		if EventBus.has_signal(bus_signal) and not EventBus.is_connected(bus_signal, bus_callback):
			EventBus.connect(bus_signal, bus_callback)
	_director = null
	if is_inside_tree():
		_director = get_tree().get_first_node_in_group("world_director")
		var parent: Node = get_parent()
		if _director == null and parent != null:
			_director = parent.get_node_or_null("WaveManager")
		if _director == null and parent != null:
			_director = parent.get_node_or_null("HordeManager")
	if _director != null and is_instance_valid(_director) and _director.has_signal("weather_changed"):
		var callback := Callable(self, "_on_director_weather")
		if not _director.is_connected("weather_changed", callback):
			_director.connect("weather_changed", callback)


func _disconnect_sources() -> void:
	if EventBus != null and is_instance_valid(EventBus):
		var bus_signal := StringName("weather_changed")
		var bus_callback := Callable(self, "_on_bus_weather")
		if EventBus.has_signal(bus_signal) and EventBus.is_connected(bus_signal, bus_callback):
			EventBus.disconnect(bus_signal, bus_callback)
	if _director != null and is_instance_valid(_director) and _director.has_signal("weather_changed"):
		var callback := Callable(self, "_on_director_weather")
		if _director.is_connected("weather_changed", callback):
			_director.disconnect("weather_changed", callback)


func _on_bus_weather(kind = null, _visibility = null, _speed = null) -> void:
	set_weather(kind, _intensity_from(kind, _visibility))


func _on_director_weather(kind = null, visibility = 1.0, _speed = 1.0) -> void:
	set_weather(kind, _intensity_from(kind, visibility))


# --- API pública ------------------------------------------------------------

func set_weather(kind, intensity = 1.0) -> void:
	var key := _normalize_weather(kind)
	var amount: float = _to_float(intensity, 1.0)
	if key == &"clear":
		amount = 0.0
	if key == _weather and absf(amount - _target_intensity) < 0.01:
		return
	_weather = key
	_target_intensity = clampf(amount, 0.0, 1.0)


func current_weather() -> String:
	return String(_weather)


func intensity() -> float:
	return _target_intensity


# --- Bucle y dibujo ---------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	var smoothing: float = 1.0 - exp(-delta / 0.7)
	var rain_target: float = 1.0 if _weather == &"rain" else 0.0
	var wind_target: float = 1.0 if _weather == &"wind" else 0.0
	var fog_target: float = 1.0 if _weather == &"fog" else 0.0
	if _weather == &"rain":
		wind_target = 0.35
		fog_target = 0.18
	elif _weather == &"wind":
		fog_target = 0.08
	rain_target *= _target_intensity
	wind_target *= _target_intensity
	fog_target *= _target_intensity
	_rain_amount = lerpf(_rain_amount, rain_target, smoothing)
	_wind_amount = lerpf(_wind_amount, wind_target, smoothing)
	_fog_amount = lerpf(_fog_amount, fog_target, smoothing)
	var visible: bool = _rain_amount + _wind_amount + _fog_amount > 0.01
	if visible:
		_advance(delta)
		queue_redraw()
	elif _was_visible:
		queue_redraw()
	_was_visible = visible


func _advance(delta: float) -> void:
	var viewport: Vector2 = get_viewport_rect().size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return
	var wind_push: float = (_wind_amount * 260.0 + _rain_amount * 90.0) * delta / viewport.x
	for drop in _rain:
		drop["y"] = fmod(float(drop["y"]) + float(drop["speed"]) * delta / viewport.y + 1.0, 1.0)
		drop["x"] = fmod(float(drop["x"]) + wind_push + 1.0, 1.0)
	for mote in _motes:
		var speed: float = float(mote["speed"]) * (0.35 + _wind_amount)
		mote["x"] = fmod(float(mote["x"]) + speed * delta / viewport.x + 1.0, 1.0)
		mote["y"] = fmod(float(mote["y"]) + 0.02 * _wind_amount * delta / viewport.y + 1.0, 1.0)


func _draw() -> void:
	var viewport: Vector2 = get_viewport_rect().size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return
	if _fog_amount > 0.01:
		_draw_fog(viewport)
	if _rain_amount > 0.01:
		_draw_rain(viewport)
	if _wind_amount > 0.01:
		_draw_wind(viewport)


func _draw_rain(viewport: Vector2) -> void:
	var slant: float = 5.0 + _wind_amount * 14.0
	var color := Color(0.62, 0.76, 0.95, 0.42 * _rain_amount)
	for drop in _rain:
		var from := Vector2(float(drop["x"]) * viewport.x, float(drop["y"]) * viewport.y)
		var to: Vector2 = from + Vector2(-slant, float(drop["len"]))
		draw_line(from, to, color, 1.0, true)


func _draw_wind(viewport: Vector2) -> void:
	var color := Color(0.92, 0.96, 1.0, 0.22 * _wind_amount)
	for mote in _motes:
		var phase: float = float(mote["phase"])
		var from := Vector2(
			float(mote["x"]) * viewport.x,
			float(mote["y"]) * viewport.y + sin(_t * 2.0 + phase) * 8.0
		)
		var length: float = float(mote["len"]) * (0.6 + _wind_amount)
		draw_line(from, from + Vector2(length, 0.0), color, 1.0, true)


func _draw_fog(viewport: Vector2) -> void:
	var tint := Color(0.72, 0.80, 0.76, 0.045 * _fog_amount)
	draw_rect(Rect2(Vector2.ZERO, viewport), tint)
	var outer := Color(0.78, 0.83, 0.79, 0.045 * _fog_amount)
	var inner := Color(0.74, 0.80, 0.76, 0.050 * _fog_amount)
	for blob in _fog_blobs:
		var phase: float = float(blob["phase"])
		var x: float = fmod(float(blob["x"]) + _t * float(blob["speed"]) + 1.0, 1.2) - 0.1
		var y: float = float(blob["y"]) + sin(_t * 0.35 + phase) * 0.03
		var radius: float = float(blob["r"]) * (1.0 + 0.12 * sin(_t * 0.7 + phase))
		var scale: float = float(blob["scale"])
		draw_set_transform(Vector2(x * viewport.x, y * viewport.y), 0.0, Vector2(scale, scale * 0.42))
		draw_circle(Vector2.ZERO, radius, outer)
		draw_circle(Vector2.ZERO, radius * 0.62, inner)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Utilidades -------------------------------------------------------------

func _world_rng() -> RandomNumberGenerator:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and is_instance_valid(gs) and gs.has_method("rng"):
		var candidate: Variant = gs.call("rng", &"world")
		if candidate is RandomNumberGenerator:
			return candidate as RandomNumberGenerator
	return _rng


func _to_float(value, fallback: float = 0.0) -> float:
	if value is float or value is int:
		return float(value)
	return fallback


func _normalize_weather(value) -> StringName:
	if value is int or value is float:
		var names: Array = [&"clear", &"fog", &"rain", &"wind"]
		var index: int = clampi(int(value), 0, names.size() - 1)
		return names[index] as StringName
	var text: String = String(str(value)).to_lower()
	match text:
		"fog", "niebla", "bruma":
			return &"fog"
		"rain", "lluvia", "storm":
			return &"rain"
		"wind", "viento", "breeze":
			return &"wind"
	return &"clear"


func _intensity_from(kind, visibility) -> float:
	var key := _normalize_weather(kind)
	var fallback: float = 1.0
	match key:
		&"clear":
			fallback = 0.0
		&"fog":
			fallback = 0.85
		&"rain":
			fallback = 0.80
		&"wind":
			fallback = 0.75
	if visibility is float or visibility is int:
		var value: float = clampf(float(visibility), 0.0, 1.0)
		if key == &"fog":
			return clampf(1.0 - value, 0.20, 1.0)
		return clampf(fallback * (0.60 + 0.40 * value), 0.0, 1.0)
	return fallback
