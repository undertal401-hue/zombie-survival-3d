extends Control
class_name HudCompass

## Brújula horizontal: muestra N/E/S/O desplazándose con el rumbo del jugador
## y un marcador azul apuntando a la zona de extracción (objetivo).

const SPAN_DEG: float = 180.0
const CARDINALS: Array[String] = ["N", "E", "S", "O"]
const CARDINAL_DEG: Array[float] = [0.0, 90.0, 180.0, 270.0]
const COL_BG: Color = Color(0.04, 0.06, 0.05, 0.72)
const COL_CENTER: Color = Color(1.0, 0.9, 0.5, 0.55)
const COL_TEXT: Color = Color(0.95, 0.9, 0.7, 0.95)
const COL_OBJECTIVE: Color = Color(0.35, 0.75, 1.0, 1.0)
const COL_VEHICLE: Color = Color(1.0, 0.62, 0.22, 1.0)
const COL_VEHICLE_LOW: Color = Color(1.0, 0.3, 0.25, 1.0)

var _player: Node2D
var _objective: Node2D

## Igual que el minimapa: caché de grupos y repintado solo cuando hay movimiento.
const CACHE_INTERVAL: float = 0.25
var _cache_timer: float = 0.0
var _dirty: bool = true
var _last_ppos: Vector2 = Vector2.INF
var _last_rotation: float = INF
var _nodes_extraction: Array = []
var _nodes_vehicles: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player = get_tree().get_first_node_in_group("player") as Node2D
	var targets: Array[Node] = get_tree().get_nodes_in_group("extraction")
	if not targets.is_empty():
		_objective = targets[0] as Node2D

func _process(delta: float) -> void:
	_cache_timer -= delta
	if _cache_timer <= 0.0:
		_cache_timer = CACHE_INTERVAL
		_refresh_caches()
		_dirty = true
	if _player == null or not is_instance_valid(_player):
		return
	var ppos: Vector2 = _player.global_position
	if ppos.distance_squared_to(_last_ppos) > 16.0 or absf(_player.global_rotation - _last_rotation) > 0.04:
		_last_ppos = ppos
		_last_rotation = _player.global_rotation
		_dirty = true
	if _dirty:
		_dirty = false
		queue_redraw()


func _refresh_caches() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	_nodes_extraction = get_tree().get_nodes_in_group("extraction")
	_nodes_vehicles = get_tree().get_nodes_in_group("player_vehicle")
	if not _nodes_extraction.is_empty():
		_objective = _nodes_extraction[0] as Node2D

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG, true)
	var center_x: float = size.x * 0.5
	draw_line(Vector2(center_x, 0.0), Vector2(center_x, size.y), COL_CENTER, 1.0)

	if _player == null or not is_instance_valid(_player):
		return

	# rotation 0 = este; sumamos 90° para que 0° sea norte (arriba, -Y).
	var bearing: float = wrapf(rad_to_deg(_player.global_rotation + PI * 0.5), 0.0, 360.0)
	var half: float = SPAN_DEG * 0.5
	var usable: float = size.x * 0.5 - 18.0
	var font: Font = ThemeDB.fallback_font

	for i in CARDINALS.size():
		var diff: float = wrapf(CARDINAL_DEG[i] - bearing + 180.0, 0.0, 360.0) - 180.0
		if absf(diff) > half:
			continue
		var x: float = center_x + (diff / half) * usable
		draw_string(font, Vector2(x - 7.0, size.y * 0.5 + 5.0), CARDINALS[i],
			HORIZONTAL_ALIGNMENT_CENTER, -1, 15, COL_TEXT)

	# Vehículo más cercano: diamante ámbar con rumbo y texto fuel/hp (%).
	_draw_vehicle_bearing(center_x, bearing, half, usable)

	if _objective == null or not is_instance_valid(_objective):
		return
	var to_obj: Vector2 = _objective.global_position - _player.global_position
	if to_obj.length() < 1.0:
		return
	var obj_bearing: float = rad_to_deg(to_obj.angle() + PI * 0.5)
	var obj_diff: float = wrapf(obj_bearing - bearing + 180.0, 0.0, 360.0) - 180.0
	var clamped: bool = absf(obj_diff) > half
	obj_diff = clampf(obj_diff, -half, half)
	var x: float = center_x + (obj_diff / half) * usable
	# Triángulo azul apuntando al objetivo; si está fuera del campo se pone en el borde.
	var tip: float = 4.0 if not clamped else 8.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(x, tip),
		Vector2(x - 5.0, tip + 10.0),
		Vector2(x + 5.0, tip + 10.0),
	]), COL_OBJECTIVE)

func _draw_vehicle_bearing(center_x: float, bearing: float, half: float,
		usable: float) -> void:
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for node in _nodes_vehicles:
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var vehicle: Node2D = node as Node2D
		var dist: float = vehicle.global_position.distance_to(_player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = vehicle
	if nearest == null:
		return

	var to_vehicle: Vector2 = nearest.global_position - _player.global_position
	if to_vehicle.length() < 1.0:
		return
	var vehicle_bearing: float = rad_to_deg(to_vehicle.angle() + PI * 0.5)
	var diff: float = wrapf(vehicle_bearing - bearing + 180.0, 0.0, 360.0) - 180.0
	var clamped: bool = absf(diff) > half
	diff = clampf(diff, -half, half)
	var x: float = center_x + (diff / half) * usable
	var y: float = size.y * 0.5
	var hp_ratio: float = _ratio(nearest, "hp", "max_hp")
	var fuel_ratio: float = _ratio(nearest, "fuel", "max_fuel")
	var color: Color = COL_VEHICLE.lerp(COL_VEHICLE_LOW, 1.0 - minf(hp_ratio, fuel_ratio))
	var edge: float = 9.0 if clamped else 6.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(x, y - edge),
		Vector2(x + edge * 0.7, y),
		Vector2(x, y + edge),
		Vector2(x - edge * 0.7, y),
	]), color)
	var label: String = "F%d H%d" % [int(fuel_ratio * 100.0), int(hp_ratio * 100.0)]
	draw_string(ThemeDB.fallback_font,
		Vector2(x - 16.0, minf(size.y - 2.0, y + 20.0)), label,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 9, color)

## Lectura defensiva de proporciones, igual que en el minimapa.
func _ratio(node: Node, value_prop: String, max_prop: String) -> float:
	var value: Variant = node.get(value_prop)
	var maximum: Variant = node.get(max_prop)
	if not (value is float or value is int) or not (maximum is float or maximum is int):
		return 1.0
	var max_value: float = float(maximum)
	if max_value <= 0.0:
		return 0.0
	return clampf(float(value) / max_value, 0.0, 1.0)
