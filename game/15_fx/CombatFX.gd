extends Node2D
class_name CombatFX

## Capa de efectos procedurales: un solo CanvasItem dibuja todas las partículas
## de combate y otro CanvasItem (WeatherFX) dibuja el clima. No crea nodos por
## disparo, no toca la cámara y usa los flujos deterministas de GameState.

const MAX_PARTICLES: int = 200
const PART_SPARK: int = 0
const PART_BLOOD_GREEN: int = 1
const PART_BLOOD_AMBER: int = 2
const PART_SHELL: int = 3
const PART_DUST: int = 4
const PART_RING: int = 5

## Fuente unica del roster: el enum real del zombi. La capa de efectos NO
## mantiene una tabla posicional propia (un Kind.BOSS=1 acababa clasificado
## como un arquetipo retirado).
const ZOMBIE_SCRIPT: Script = preload("res://03_zombies/Zombie.gd")
const SURFACE_KINDS: Array = [&"metal", &"concrete", &"wood", &"flesh", &"dirt"]

var _particles: Array = []
var _cursor: int = 0
var _had_active: bool = false
var _fallback_rng := RandomNumberGenerator.new()
var _damage_pulse: float = 0.0
var _damage_time: float = 0.0
var _vignette: ColorRect = null
var _weather_fx: Node = null
var _vehicle_hp: Dictionary = {}
var _vehicle_callbacks: Dictionary = {}
var _vehicle_spark_ms: Dictionary = {}


func _init() -> void:
	_fallback_rng.seed = 20261117 + 404
	for _i in range(MAX_PARTICLES):
		_particles.append({
			"active": false,
			"p": Vector2.ZERO,
			"v": Vector2.ZERO,
			"life": 0.0,
			"ttl": 1.0,
			"type": PART_SPARK,
			"color": Color.WHITE,
			"size": 2.0,
			"rot": 0.0,
			"spin": 0.0,
			"grav": 0.0,
			"drag": 0.0,
			"bounce": 0.0,
			"ground_y": 0.0,
		})


func _ready() -> void:
	_vignette = get_node_or_null("Damage/Vignette") as ColorRect
	_weather_fx = get_node_or_null("Weather/Canvas")
	_configure_vignette()
	_connect_bus()
	call_deferred("_bind_vehicles")


func _exit_tree() -> void:
	_disconnect_bus()
	_disconnect_vehicles()


## Viñeta: ColorRect con shader radial y modulate pulsante. Sin textos y sin
## sacudida de cámara: esa ya la hace el jugador.
func _configure_vignette() -> void:
	if _vignette == null:
		return
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nrender_mode unshaded;\n\nvoid fragment() {\n\tvec2 p = UV * 2.0 - 1.0;\n\tfloat edge = smoothstep(0.35, 1.05, length(p));\n\tCOLOR = vec4(COLOR.rgb, COLOR.a * edge);\n}"
	var material := ShaderMaterial.new()
	material.shader = shader
	_vignette.material = material
	_vignette.color = Color(0.86, 0.03, 0.04, 1.0)
	_vignette.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_vignette.visible = false


func _connect_bus() -> void:
	if EventBus == null or not is_instance_valid(EventBus):
		return
	var damage_signal := StringName("player_damaged")
	var damage_callback := Callable(self, "_on_player_damaged")
	if EventBus.has_signal(damage_signal) and not EventBus.is_connected(damage_signal, damage_callback):
		EventBus.connect(damage_signal, damage_callback)
	var vehicle_signal := StringName("vehicle_state_changed")
	var vehicle_callback := Callable(self, "_on_vehicle_state")
	if EventBus.has_signal(vehicle_signal) and not EventBus.is_connected(vehicle_signal, vehicle_callback):
		EventBus.connect(vehicle_signal, vehicle_callback)


func _disconnect_bus() -> void:
	if EventBus == null or not is_instance_valid(EventBus):
		return
	var damage_signal := StringName("player_damaged")
	var damage_callback := Callable(self, "_on_player_damaged")
	if EventBus.has_signal(damage_signal) and EventBus.is_connected(damage_signal, damage_callback):
		EventBus.disconnect(damage_signal, damage_callback)
	var vehicle_signal := StringName("vehicle_state_changed")
	var vehicle_callback := Callable(self, "_on_vehicle_state")
	if EventBus.has_signal(vehicle_signal) and EventBus.is_connected(vehicle_signal, vehicle_callback):
		EventBus.disconnect(vehicle_signal, vehicle_callback)


func _process(delta: float) -> void:
	_damage_time += delta
	_damage_pulse = maxf(0.0, _damage_pulse - delta * 1.25)
	_update_vignette()
	_update_particles(delta)


func _update_vignette() -> void:
	if _vignette == null:
		return
	var visible_now: bool = _damage_pulse > 0.001
	_vignette.visible = visible_now
	if not visible_now:
		return
	var beat: float = 0.86 + 0.14 * sin(_damage_time * 17.0)
	_vignette.modulate = Color(1.0, 1.0, 1.0, clampf(_damage_pulse * 0.55 * beat, 0.0, 0.65))


func _on_player_damaged(amount = 0.0, _source = null) -> void:
	_damage_pulse = clampf(_damage_pulse + clampf(_to_float(amount, 0.0) / 45.0, 0.18, 1.0), 0.0, 1.0)
	_damage_time = 0.0


# --- API pública ------------------------------------------------------------

## Impacto de bala: chispas con dirección. `kind` admite String, StringName,
## índice de ImpactParticles.SurfaceType o un zombie (se trata como carne).
func spawn_impact(pos: Vector2, dir: Vector2, kind = &"bullet") -> void:
	var forward := _safe_direction(dir)
	var key := _normalize_surface(kind)
	if key == &"finisher" or key == &"combo" or key == &"shockwave" or key == &"combo_finisher":
		_spawn_finisher(pos, forward)
		return
	if key == &"melee" or key == &"machete" or key == &"dust":
		spawn_dust(pos, forward, 12)
		return
	if key == &"flesh" or key == &"blood" or key == &"zombie":
		var zombie_key := _normalize_zombie_kind(kind)
		_spawn_blood_particles(pos, 8, zombie_key)
	_spawn_sparks(pos, forward, key)


## Sangre de zombi: verde para el caminante y ambar para el perfil BOSS del
## Tanque Alfa. Es una distincion de PERFIL, no una familia de arquetipos.
func spawn_blood(pos: Vector2, kind = &"walker") -> void:
	_spawn_blood_particles(pos, 14, _normalize_zombie_kind(kind))


## Casquillo con gravedad, rotación y rebote sobre el suelo local del impacto.
func spawn_shell(pos: Vector2, dir: Vector2) -> void:
	var forward := _safe_direction(dir)
	var rng := _combat_rng()
	var lateral := Vector2(-forward.y, forward.x)
	var velocity: Vector2 = forward * rng.randf_range(70.0, 140.0)
	velocity += lateral * rng.randf_range(-30.0, 30.0)
	velocity += Vector2(0.0, -rng.randf_range(80.0, 140.0))
	_emit(
		PART_SHELL, pos, velocity, rng.randf_range(1.0, 1.8),
		Color(0.95, 0.78, 0.32, 1.0), rng.randf_range(3.0, 4.5),
		rng.randf_range(0.0, TAU), rng.randf_range(-12.0, 12.0),
		620.0, 0.15, rng.randf_range(0.28, 0.48), pos.y + 12.0
	)


## Polvo de melee; también se usa en los impactos de finisher.
func spawn_dust(pos: Vector2, dir: Vector2, count: int = 10) -> void:
	var forward := _safe_direction(dir)
	var rng := _combat_rng()
	var amount: int = clampi(count, 1, 40)
	for _i in range(amount):
		var angle: float = forward.angle() + rng.randf_range(-1.2, 1.2)
		var velocity: Vector2 = Vector2.RIGHT.rotated(angle) * rng.randf_range(20.0, 95.0)
		var color := Color(0.52, 0.46, 0.34, rng.randf_range(0.16, 0.34))
		_emit(
			PART_DUST, pos + Vector2.RIGHT.rotated(angle) * rng.randf_range(0.0, 6.0),
			velocity, rng.randf_range(0.35, 0.75), color, rng.randf_range(4.0, 9.0),
			0.0, 0.0, -12.0, 2.4, 0.0, pos.y
		)


## Reenvía el clima al CanvasItem de clima; no modifica WorldDirector.
func set_weather(kind, intensity = 1.0) -> void:
	if _weather_fx == null or not is_instance_valid(_weather_fx):
		return
	if not _weather_fx.has_method("set_weather"):
		return
	_weather_fx.call("set_weather", kind, intensity)


func current_weather() -> String:
	if _weather_fx == null or not is_instance_valid(_weather_fx):
		return "clear"
	if _weather_fx.has_method("current_weather"):
		return String(_weather_fx.call("current_weather"))
	return "clear"


func active_particle_count() -> int:
	var total: int = 0
	for data in _particles:
		if bool(data["active"]):
			total += 1
	return total


# --- Emisión ----------------------------------------------------------------

func _spawn_sparks(pos: Vector2, forward: Vector2, key: StringName) -> void:
	var rng := _combat_rng()
	var count: int = 10
	var base := Color(1.0, 0.78, 0.30, 1.0)
	match key:
		&"metal", &"spark":
			count = 12
			base = Color(1.0, 0.86, 0.42, 1.0)
		&"concrete":
			count = 9
			base = Color(0.86, 0.73, 0.48, 1.0)
		&"wood":
			count = 8
			base = Color(0.74, 0.45, 0.20, 1.0)
		&"dirt":
			count = 7
			base = Color(0.56, 0.44, 0.28, 1.0)
		&"flesh":
			count = 5
			base = Color(0.66, 0.86, 0.36, 1.0)
	for _i in range(count):
		var angle: float = forward.angle() + rng.randf_range(-0.75, 0.75)
		var speed: float = rng.randf_range(90.0, 320.0)
		var color: Color = base
		color.a = rng.randf_range(0.65, 1.0)
		_emit(
			PART_SPARK, pos + Vector2.RIGHT.rotated(angle) * rng.randf_range(0.0, 4.0),
			Vector2.RIGHT.rotated(angle) * speed, rng.randf_range(0.16, 0.42),
			color, rng.randf_range(1.2, 2.6), 0.0, 0.0,
			rng.randf_range(120.0, 320.0), 1.2, 0.0, pos.y + 8.0
		)


func _spawn_blood_particles(pos: Vector2, count: int, kind_key: StringName) -> void:
	var amber: bool = kind_key == &"boss"
	var base := Color(0.24, 0.74, 0.20, 1.0) if not amber else Color(0.96, 0.56, 0.12, 1.0)
	var rng := _combat_rng()
	var amount: int = clampi(count, 1, 40)
	for _i in range(amount):
		var angle: float = rng.randf_range(0.0, TAU)
		var velocity: Vector2 = Vector2.RIGHT.rotated(angle) * rng.randf_range(40.0, 210.0)
		velocity += Vector2(0.0, -rng.randf_range(10.0, 60.0))
		var color: Color = base
		color.a = rng.randf_range(0.55, 0.95)
		_emit(
			PART_BLOOD_AMBER if amber else PART_BLOOD_GREEN,
			pos + Vector2.RIGHT.rotated(angle) * rng.randf_range(0.0, 5.0),
			velocity, rng.randf_range(0.35, 0.85), color,
			rng.randf_range(1.4, 3.2), 0.0, 0.0, 480.0, 0.8, 0.0, pos.y + 14.0
		)


func _spawn_finisher(pos: Vector2, forward: Vector2) -> void:
	var rng := _combat_rng()
	_emit(
		PART_RING, pos, Vector2.ZERO, 0.42, Color(1.0, 0.86, 0.38, 0.85), 34.0,
		0.0, 0.0, 0.0, 0.0, 0.0, pos.y
	)
	_emit(
		PART_RING, pos, Vector2.ZERO, 0.30, Color(1.0, 0.62, 0.24, 0.55), 20.0 + rng.randf_range(0.0, 6.0),
		0.0, 0.0, 0.0, 0.0, 0.0, pos.y
	)
	_spawn_sparks(pos, forward, &"spark")
	spawn_dust(pos, forward, 16)


func _emit(type: int, p: Vector2, v: Vector2, ttl: float, color: Color, size: float,
		rot: float, spin: float, grav: float, drag: float, bounce: float, ground_y: float) -> void:
	var data: Dictionary = _particles[_cursor]
	_cursor = (_cursor + 1) % MAX_PARTICLES
	data["active"] = true
	data["p"] = p
	data["v"] = v
	data["life"] = ttl
	data["ttl"] = ttl
	data["type"] = type
	data["color"] = color
	data["size"] = size
	data["rot"] = rot
	data["spin"] = spin
	data["grav"] = grav
	data["drag"] = drag
	data["bounce"] = bounce
	data["ground_y"] = ground_y


func _update_particles(delta: float) -> void:
	var any_active: bool = false
	for data in _particles:
		if not bool(data["active"]):
			continue
		var life: float = float(data["life"]) - delta
		if life <= 0.0:
			data["active"] = false
			continue
		data["life"] = life
		var type: int = int(data["type"])
		if type == PART_RING:
			any_active = true
			continue
		var p: Vector2 = data["p"]
		var v: Vector2 = data["v"]
		v.y += float(data["grav"]) * delta
		v *= maxf(0.0, 1.0 - float(data["drag"]) * delta)
		p += v * delta
		var ground: float = float(data["ground_y"])
		if float(data["bounce"]) > 0.0 and p.y >= ground and v.y > 0.0:
			p.y = ground
			v.y = -v.y * float(data["bounce"])
			v.x *= 0.72
			data["rot"] = float(data["rot"]) + 0.35
			if absf(v.y) < 8.0:
				v.y = 0.0
				data["bounce"] = 0.0
		data["p"] = p
		data["v"] = v
		data["rot"] = float(data["rot"]) + float(data["spin"]) * delta
		any_active = true
	if any_active or _had_active:
		queue_redraw()
	_had_active = any_active


func _draw() -> void:
	for data in _particles:
		if not bool(data["active"]):
			continue
		var alpha: float = clampf(float(data["life"]) / maxf(float(data["ttl"]), 0.001), 0.0, 1.0)
		var color: Color = data["color"]
		color.a *= alpha
		var p: Vector2 = data["p"]
		match int(data["type"]):
			PART_SPARK:
				var v: Vector2 = data["v"]
				var tail: Vector2 = -v.normalized() * clampf(v.length() * 0.025, 2.0, 10.0)
				draw_line(p, p + tail, color, maxf(1.0, float(data["size"]) * 0.5), true)
			PART_BLOOD_GREEN, PART_BLOOD_AMBER:
				draw_circle(p, float(data["size"]) * (0.55 + 0.45 * alpha), color)
			PART_SHELL:
				var size: float = float(data["size"])
				draw_set_transform(p, float(data["rot"]), Vector2.ONE)
				draw_rect(Rect2(-size * 0.5, -size * 0.21, size, size * 0.42), color)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			PART_DUST:
				draw_circle(p, float(data["size"]) * (1.4 - 0.4 * alpha), color)
			PART_RING:
				var grow: float = 1.0 - alpha
				var radius: float = float(data["size"]) * (0.6 + 3.4 * grow)
				draw_arc(p, radius, 0.0, TAU, 28, color, maxf(1.0, 4.0 * alpha), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Vehículos: solo chispas de colisión, sin humo ni parpadeo --------------

func _bind_vehicles() -> void:
	if not is_inside_tree():
		return
	for vehicle in get_tree().get_nodes_in_group("player_vehicle"):
		_bind_vehicle(vehicle as Node2D)


func _bind_vehicle(vehicle: Node2D) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if not vehicle.has_signal("damage_changed"):
		return
	var callback := Callable(self, "_on_vehicle_damage").bind(vehicle)
	if not vehicle.is_connected("damage_changed", callback):
		vehicle.connect("damage_changed", callback)
	_vehicle_callbacks[vehicle] = callback
	var raw: Variant = vehicle.get("hp")
	if raw is float or raw is int:
		_vehicle_hp[vehicle] = float(raw)


func _disconnect_vehicles() -> void:
	for vehicle in _vehicle_callbacks.keys():
		var node: Node = vehicle as Node
		var callback: Callable = _vehicle_callbacks[vehicle]
		if node != null and is_instance_valid(node) and node.has_signal("damage_changed") \
				and node.is_connected("damage_changed", callback):
			node.disconnect("damage_changed", callback)
	_vehicle_callbacks.clear()
	_vehicle_hp.clear()
	_vehicle_spark_ms.clear()


func _on_vehicle_damage(hp = 0.0, _max_hp = 0.0, vehicle = null) -> void:
	_vehicle_sparks_from(vehicle as Node2D, _to_float(hp, 0.0))


func _on_vehicle_state(vehicle = null, _fuel = 0.0, hp = 0.0) -> void:
	_vehicle_sparks_from(vehicle as Node2D, _to_float(hp, 0.0))


func _vehicle_sparks_from(vehicle: Node2D, hp: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var previous: float = _to_float(_vehicle_hp.get(vehicle, hp), hp)
	_vehicle_hp[vehicle] = hp
	if hp >= previous:
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_vehicle_spark_ms.get(vehicle, -9999)) < 140:
		return
	_vehicle_spark_ms[vehicle] = now
	var raw_velocity: Variant = vehicle.get("velocity")
	var velocity: Vector2 = raw_velocity if raw_velocity is Vector2 else Vector2.ZERO
	var direction := -velocity.normalized() if velocity.length_squared() > 1.0 else Vector2.UP
	spawn_impact(vehicle.global_position + direction * 18.0, direction, &"spark")


# --- Utilidades deterministas y defensivas ----------------------------------

func _combat_rng() -> RandomNumberGenerator:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and is_instance_valid(gs) and gs.has_method("rng"):
		var candidate: Variant = gs.call("rng", &"combat")
		if candidate is RandomNumberGenerator:
			return candidate as RandomNumberGenerator
	return _fallback_rng


func _safe_direction(dir: Vector2) -> Vector2:
	if dir.length_squared() > 0.0001:
		return dir.normalized()
	return Vector2.RIGHT


func _to_float(value, fallback: float = 0.0) -> float:
	if value is float or value is int:
		return float(value)
	return fallback


func _normalize_surface(value) -> StringName:
	# `value is Node` sobre una instancia ya liberada aborta la funcion en
	# Godot 4.7. Primero se comprueba que el objeto sigue vivo.
	if typeof(value) == TYPE_OBJECT and is_instance_valid(value) and value is Node:
		return &"flesh"
	if value is int or value is float:
		var index: int = clampi(int(value), 0, SURFACE_KINDS.size() - 1)
		return SURFACE_KINDS[index] as StringName
	var text: String = String(str(value)).to_lower()
	match text:
		"metal", "chispa", "spark", "acero":
			return &"metal"
		"concrete", "hormigon", "piedra", "stone", "bullet", "bala":
			return &"concrete"
		"wood", "madera":
			return &"wood"
		"flesh", "blood", "sangre", "carne", "zombie":
			return &"flesh"
		"dirt", "tierra", "polvo":
			return &"dirt"
		"melee", "cuchillo", "machete":
			return &"melee"
		"finisher", "combo", "shockwave", "onda", "remate":
			return &"finisher"
		"dust", "impact", "impacto":
			return &"dust"
	return &"concrete"


func _normalize_zombie_kind(value) -> StringName:
	if typeof(value) == TYPE_OBJECT and is_instance_valid(value) and value is Node:
		value = (value as Node).get("kind")
	if value is int or value is float:
		return _zombie_kind_name(int(value))
	var text: String = String(str(value)).to_lower()
	match text:
		"boss", "jefe", "tanque alfa", "amber", "ambar":
			return &"boss"
		"walker", "caminante", "normal", "green", "verde":
			return &"walker"
	return &"walker"


## Traduce el indice real de `Zombie.Kind` al perfil visual. El enum es la
## fuente de verdad; no hay posiciones magicas en esta capa.
func _zombie_kind_name(index: int) -> StringName:
	var kinds: Dictionary = ZOMBIE_SCRIPT.get_script_constant_map().get(
		"Kind", {}) as Dictionary
	if kinds.has("BOSS") and index == int(kinds["BOSS"]):
		return &"boss"
	return &"walker"
