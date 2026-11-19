extends Control
class_name HudMinimap

## Minimapa procedural: muestra al jugador en el centro, zombis, loot y la
## zona de extracción dentro de un radio de mundo. No usa texturas ni escenas
## nuevas: todo se dibuja con CanvasItem en _draw().

const WORLD_RADIUS: float = 520.0
const COL_BG: Color = Color(0.04, 0.06, 0.05, 0.78)
const COL_BORDER: Color = Color(0.35, 0.5, 0.35, 0.85)
const COL_GRID: Color = Color(1.0, 1.0, 1.0, 0.08)
const COL_PLAYER: Color = Color(0.4, 1.0, 0.5, 1.0)
const COL_ZOMBIE: Color = Color(0.95, 0.25, 0.22, 0.95)
const COL_LOOT: Color = Color(0.95, 0.8, 0.3, 0.95)
const COL_EXTRACTION: Color = Color(0.35, 0.75, 1.0, 1.0)
const COL_VEHICLE: Color = Color(0.95, 0.58, 0.2, 1.0)
const COL_VEHICLE_DAMAGED: Color = Color(1.0, 0.22, 0.18, 1.0)
const COL_ROUTE: Color = Color(1.0, 0.78, 0.3, 0.45)
const COL_BAR_HP: Color = Color(0.45, 1.0, 0.55, 0.95)
const COL_BAR_FUEL: Color = Color(1.0, 0.82, 0.28, 0.95)

# Capa de densidad del bosque: rejilla polar de 8 angulos x 5 anillos (40 muestras).
# Es una sobreposicion local, no altera WORLD_RADIUS ni la escala del radar.
const DENSITY_ANGLES: int = 8
const DENSITY_RINGS: int = 5
const DENSITY_WORLD_SPAN: float = 3000.0
const COL_DENSITY_CLEARING: Color = Color(0.45, 0.34, 0.14, 0.16)

var _player: Node2D
var _forest: Node = null
var _in_forest: bool = false
var _density_image: Image = null
var _density_forest: Node = null

## Redibujado sucio: los grupos se consultan 4 veces por segundo y el radar
## solo se repinta cuando el jugador se mueve o cambia de rumbo. Antes era
## queue_redraw() incondicional con 5 escaneos de grupo por frame.
const CACHE_INTERVAL: float = 0.25
var _cache_timer: float = 0.0
var _dirty: bool = true
var _last_ppos: Vector2 = Vector2.INF
var _last_rotation: float = INF
var _nodes_extraction: Array = []
var _nodes_loot: Array = []
var _nodes_pickups: Array = []
var _nodes_zombies: Array = []
var _nodes_vehicles: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player = get_tree().get_first_node_in_group("player") as Node2D
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus != null:
		var entered := Callable(self, "_on_forest_entered")
		var exited := Callable(self, "_on_forest_exited")
		if not bus.is_connected("forest_entered", entered):
			bus.connect("forest_entered", entered)
		if not bus.is_connected("forest_exited", exited):
			bus.connect("forest_exited", exited)

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
	_nodes_loot = get_tree().get_nodes_in_group("loot")
	_nodes_pickups = get_tree().get_nodes_in_group("pickups")
	_nodes_zombies = get_tree().get_nodes_in_group("zombies")
	_nodes_vehicles = get_tree().get_nodes_in_group("player_vehicle")

func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 8.0
	if radius <= 4.0:
		return
	var scale: float = radius / WORLD_RADIUS

	draw_circle(center, radius, COL_BG)
	# La capa va antes del borde, la rejilla y los marcadores para no taparlos.
	if _player != null and is_instance_valid(_player):
		_draw_forest_density(center, radius, _player.global_position)
	draw_arc(center, radius, 0.0, TAU, 64, COL_BORDER, 2.0)
	draw_line(center + Vector2(-radius, 0.0), center + Vector2(radius, 0.0), COL_GRID, 1.0)
	draw_line(center + Vector2(0.0, -radius), center + Vector2(0.0, radius), COL_GRID, 1.0)

	if _player == null or not is_instance_valid(_player):
		return
	var ppos: Vector2 = _player.global_position

	# Extracción: anillo azul (se marca en el borde si está fuera de rango).
	for node in _nodes_extraction:
		if is_instance_valid(node) and node is Node2D:
			_draw_marker(center, radius, scale, ppos, (node as Node2D).global_position, COL_EXTRACTION, 6.0, true)

	# Objetos saqueables.
	for group_nodes: Array in [_nodes_loot, _nodes_pickups]:
		for node in group_nodes:
			if is_instance_valid(node) and node is Node2D:
				_draw_marker(center, radius, scale, ppos, (node as Node2D).global_position, COL_LOOT, 2.5, false)

	# Zombis.
	for node in _nodes_zombies:
		if is_instance_valid(node) and node is Node2D:
			_draw_marker(center, radius, scale, ppos, (node as Node2D).global_position, COL_ZOMBIE, 3.0, false)

	# Vehículos: icono orientado, barras de chasis/fuel y ruta al más cercano.
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for node in _nodes_vehicles:
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var vehicle: Node2D = node as Node2D
		var dist: float = vehicle.global_position.distance_to(ppos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = vehicle
		var hp_ratio: float = _ratio(vehicle, "hp", "max_hp")
		var fuel_ratio: float = _ratio(vehicle, "fuel", "max_fuel")
		var icon_color: Color = COL_VEHICLE.lerp(COL_VEHICLE_DAMAGED, 1.0 - hp_ratio)
		var vpos: Vector2 = _map_pos(center, radius, scale, ppos, vehicle.global_position)
		_draw_vehicle_icon(vpos, vehicle.global_rotation, icon_color)
		_draw_status_bar(vpos + Vector2(9.0, -8.0), hp_ratio, COL_BAR_HP)
		_draw_status_bar(vpos + Vector2(9.0, -4.0), fuel_ratio, COL_BAR_FUEL)
	if nearest != null and nearest_dist > 12.0:
		var vpos: Vector2 = _map_pos(center, radius, scale, ppos, nearest.global_position)
		draw_line(center, vpos, COL_ROUTE, 1.5)

	# Jugador: flecha en el centro orientada igual que en el mundo.
	var forward: Vector2 = Vector2.RIGHT.rotated(_player.global_rotation) * 8.0
	var side: Vector2 = Vector2.DOWN.rotated(_player.global_rotation) * 4.0
	draw_colored_polygon(PackedVector2Array([
		center + forward,
		center - forward * 0.6 + side,
		center - forward * 0.6 - side,
	]), COL_PLAYER)

func _draw_marker(center: Vector2, radius: float, scale: float, ppos: Vector2,
		target: Vector2, color: Color, dot_size: float, is_ring: bool) -> void:
	var offset: Vector2 = (target - ppos) * scale
	if offset.length() > radius:
		if not is_ring:
			return
		offset = offset.normalized() * (radius - 3.0)
	var pos: Vector2 = center + offset
	if is_ring:
		draw_arc(pos, maxf(dot_size, 4.0), 0.0, TAU, 12, color, 2.0)
	else:
		draw_circle(pos, dot_size, color)

## Posición en el radar, recortada al borde como _draw_marker().
func _map_pos(center: Vector2, radius: float, scale: float, ppos: Vector2,
		target: Vector2) -> Vector2:
	var offset: Vector2 = (target - ppos) * scale
	if offset.length() > radius:
		offset = offset.normalized() * (radius - 3.0)
	return center + offset

## Icono de camioneta: rectángulo orientado con el vehículo.
func _draw_vehicle_icon(pos: Vector2, rot: float, color: Color) -> void:
	var forward: Vector2 = Vector2.RIGHT.rotated(rot) * 7.0
	var side: Vector2 = Vector2.DOWN.rotated(rot) * 4.0
	draw_colored_polygon(PackedVector2Array([
		pos + forward + side,
		pos + forward - side,
		pos - forward - side,
		pos - forward + side,
	]), color)

func _draw_status_bar(origin: Vector2, ratio: float, color: Color) -> void:
	draw_rect(Rect2(origin, Vector2(12.0, 2.0)), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(origin, Vector2(12.0 * clampf(ratio, 0.0, 1.0), 2.0)), color)

## Lectura defensiva de proporciones: un vehículo sin estas propiedades se
## muestra como sano y lleno en lugar de provocar un error de script.
func _ratio(node: Node, value_prop: String, max_prop: String) -> float:
	var value: Variant = node.get(value_prop)
	var maximum: Variant = node.get(max_prop)
	if not (value is float or value is int) or not (maximum is float or maximum is int):
		return 1.0
	var max_value: float = float(maximum)
	if max_value <= 0.0:
		return 0.0
	return clampf(float(value) / max_value, 0.0, 1.0)

func _on_forest_entered() -> void:
	_in_forest = true
	_dirty = true

func _on_forest_exited() -> void:
	_in_forest = false
	_dirty = true

## Hasta 40 muestras de densidad, siempre dentro del circulo del radar.
func _draw_forest_density(center: Vector2, radius: float, ppos: Vector2) -> void:
	if radius < 12.0:
		return
	var forest: Node = _forest
	if forest == null or not is_instance_valid(forest):
		forest = get_tree().get_first_node_in_group("forest")
		_forest = forest
	if forest == null or not is_instance_valid(forest):
		return

	# Las señales marcan la zona; in_forest() manda cuando el nodo existe, para
	# cubrir tambien movimientos directos del jugador sin señal.
	var active: bool = _in_forest
	if forest.has_method("in_forest"):
		active = bool(forest.call("in_forest", ppos))
	if not active:
		return

	# La imagen se crea y se lee una sola vez; get_image() no se repite por frame.
	if _density_image == null or _density_forest != forest:
		_density_forest = forest
		_density_image = null
		if forest.has_method("get_density_texture"):
			var tex: ImageTexture = forest.call("get_density_texture") as ImageTexture
			if tex != null:
				_density_image = tex.get_image()
	if _density_image == null:
		return
	var img_w: int = _density_image.get_width()
	var img_h: int = _density_image.get_height()
	if img_w < 2 or img_h < 2:
		return

	var half: Vector2 = Vector2(6300.0, 6300.0)
	if forest.has_method("world_half"):
		var h: Variant = forest.call("world_half")
		if h is Vector2 and (h as Vector2).x > 0.0 and (h as Vector2).y > 0.0:
			half = h

	var sample_r: float = radius / float(DENSITY_RINGS) * 0.55
	for ring in range(DENSITY_RINGS):
		var ring_r: float = radius * float(ring + 1) / float(DENSITY_RINGS) - sample_r - 1.0
		if ring_r <= 0.0:
			continue
		var world_r: float = DENSITY_WORLD_SPAN * float(ring + 1) / float(DENSITY_RINGS)
		for a in range(DENSITY_ANGLES):
			var ang: float = TAU * float(a) / float(DENSITY_ANGLES)
			var dir := Vector2(cos(ang), sin(ang))
			var world: Vector2 = ppos + dir * world_r
			var ix: int = clampi(int((world.x + half.x) / (2.0 * half.x) * float(img_w - 1)), 0, img_w - 1)
			var iy: int = clampi(int((world.y + half.y) / (2.0 * half.y) * float(img_h - 1)), 0, img_h - 1)
			var dens: float = _density_image.get_pixel(ix, iy).a
			if dens <= 0.001:
				continue
			var pos: Vector2 = center + dir * ring_r
			if dens < 0.12:
				draw_circle(pos, sample_r, COL_DENSITY_CLEARING)
			else:
				var alpha: float = clampf(0.15 + dens * 0.35, 0.15, 0.5)
				draw_circle(pos, sample_r, Color(0.10, 0.16, 0.10, alpha))
