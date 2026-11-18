extends Node2D

## Bosque procedural que rodea el pueblo sin modificar Neighborhood.
## Fase 1: anillo visual + colisiones por chunk. El acceso se añadirá en Fase 2.

const WORLD_HALF: Vector2 = Vector2(6300.0, 6300.0)   # 12600×12600 ≈ 11× el área urbana
const TOWN_HALF: Vector2 = Vector2(2400.0, 1500.0)
const CELL: float = 300.0
const GRID: int = 42
const CHUNK: float = 2100.0
const SEED: int = 20261117

const COL_SOIL := Color(0.055, 0.075, 0.06, 1)
const COL_URBAN := Color(0.2, 0.24, 0.16, 1)
const COL_PATH := Color(0.22, 0.18, 0.12, 1)
const COL_CLEARING := Color(0.16, 0.115, 0.06, 1)
const COL_TRUNK := Color(0.16, 0.10, 0.06, 1)
const COL_CANOPY_DARK := Color(0.055, 0.085, 0.055, 1)
const COL_CANOPY_MID := Color(0.10, 0.145, 0.085, 1)
const COL_CANOPY_LIGHT := Color(0.20, 0.16, 0.07, 0.9)
const COL_DEAD := Color(0.18, 0.11, 0.06, 1)
const COL_SHADOW := Color(0.02, 0.035, 0.025, 0.55)
const COL_LITTER := Color(0.17, 0.115, 0.06, 0.85)
const COL_FOG := Color(0.36, 0.40, 0.34, 0.09)

# Decoracion dentro del pueblo: verde visible desde el primer frame. Solo
# Polygon2D/MultiMesh, sin colisiones ni geometria de navegacion.
const COL_TOWN_GRASS := Color(0.25, 0.38, 0.17, 0.95)
const COL_TOWN_GRASS_DARK := Color(0.19, 0.30, 0.14, 0.92)
const COL_TOWN_SHRUB := Color(0.16, 0.34, 0.13, 1.0)
const COL_TOWN_SHRUB_LIT := Color(0.29, 0.44, 0.18, 1.0)
const COL_TOWN_TRUNK := Color(0.19, 0.12, 0.06, 1.0)
const TOWN_CENTER_PAD: float = 14.0   # centro lejos de casas; el dibujo va por debajo de ellas

# Fase 4: río y puentes. Puramente visuales: ni colisiones ni geometría de nav.
const RIVER_STEP: float = 150.0
const RIVER_HALF_WIDTH: float = 55.0
const RIVER_BANK_WIDTH: float = 18.0
const RIVER_TREE_CLEARANCE: float = 60.0
const RIVER_COLOR := Color(0.07, 0.12, 0.14, 0.92)
const RIVER_BANK_COLOR := Color(0.22, 0.15, 0.07, 1.0)
const BRIDGE_X_LEFT: float = -2100.0
const BRIDGE_X_RIGHT: float = 2100.0
const BRIDGE_HALF_ALONG: float = 58.0
const BRIDGE_HALF_CROSS: float = 125.0
const BRIDGE_PLANKS: int = 6
const BRIDGE_COLOR := Color(0.22, 0.16, 0.09, 1.0)
const BRIDGE_PLANK_COLOR := Color(0.30, 0.22, 0.12, 1.0)

# Fase 4: botín en claros.
const LOOT_SCENE: PackedScene = preload("res://04_items/LootContainer.tscn")

var _rng := RandomNumberGenerator.new()
var _clearings: Array[Dictionary] = []
var _paths: Array[Dictionary] = []
var _fog_bands: Array[Dictionary] = []
var _shapes: Array[Shape2D] = []
var _tree_count: int = 0
var _density_tex: ImageTexture = null
var _river_points: PackedVector2Array = PackedVector2Array()

# WorldDirector: estado del clima y registro de botín respawneable.
# Nunca se registran item_id "combustible" ni "comida": QA mide FUEL/FOOD y
# esos sectores deben permanecer exactamente como los crea _build_loot().
var _loot_records: Array[Dictionary] = []
var _weather_fog: float = 0.0
var _weather_speed: float = 1.0

func _ready() -> void:
	_rng.seed = SEED
	_build_floor()
	_build_town_decor()
	_build_clearings()
	_build_paths()
	_build_river()
	_build_trees()
	_build_litter()
	_build_nav_thickets()
	_build_fog()
	_build_loot()

func world_half() -> Vector2:
	return WORLD_HALF

func town_half() -> Vector2:
	return TOWN_HALF

func tree_count() -> int:
	return _tree_count

func in_forest(p: Vector2) -> bool:
	return not Rect2(-TOWN_HALF, TOWN_HALF * 2.0).has_point(p)

func _edge_distance(p: Vector2) -> float:
	var d := Vector2(maxf(absf(p.x) - TOWN_HALF.x, 0.0), maxf(absf(p.y) - TOWN_HALF.y, 0.0))
	return d.length()

func _band(d: float) -> Dictionary:
	if d < 260.0:
		return {"density": 0.18, "r_min": 14.0, "r_max": 20.0, "h_min": 18.0, "h_max": 26.0}
	if d < 1500.0:
		return {"density": 0.72, "r_min": 22.0, "r_max": 34.0, "h_min": 28.0, "h_max": 44.0}
	if d < 2700.0:
		return {"density": 0.55, "r_min": 20.0, "r_max": 30.0, "h_min": 26.0, "h_max": 38.0}
	if d < 3900.0:
		return {"density": 0.68, "r_min": 28.0, "r_max": 42.0, "h_min": 36.0, "h_max": 52.0}
	return {"density": 0.70, "r_min": 24.0, "r_max": 36.0, "h_min": 30.0, "h_max": 46.0}

func _build_floor() -> void:
	var floor_rect := ColorRect.new()
	floor_rect.name = "ForestFloor"
	floor_rect.position = -WORLD_HALF
	floor_rect.size = WORLD_HALF * 2.0
	floor_rect.color = COL_SOIL
	floor_rect.z_index = -10
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor_rect)

	# Mismo z que Ground: se dibuja despues en el arbol y devuelve al pueblo su
	# color original, pero queda por debajo de los parches y asfalto (z=-9..-5).
	var urban := ColorRect.new()
	urban.name = "UrbanBase"
	urban.position = -TOWN_HALF
	urban.size = TOWN_HALF * 2.0
	urban.color = COL_URBAN
	urban.z_index = -10
	urban.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(urban)

# --- Decoracion urbana: vegetacion dentro de los muros, sin fisicas ni nav. ---
# z=-6 (pasto) va por encima de la base y aceras, pero por debajo del asfalto
# (z=-5). z=-4 (arbustos) queda sobre marcas/lotes y bajo casas y jugador.
func _build_town_decor() -> void:
	var neighborhood: Node = null
	if get_parent() != null:
		neighborhood = get_parent().get_node_or_null("Neighborhood")
	var road_rects: Array = []
	if neighborhood != null:
		var value: Variant = neighborhood.get("_road_rects")
		if value is Array:
			road_rects = value as Array

	var house_rects: Array[Rect2] = []
	for node in get_tree().get_nodes_in_group("houses"):
		var house := node as House
		if house == null:
			continue
		house_rects.append(Rect2(house.global_position - house.size * 0.5, house.size).grow(10.0))

	var root := Node2D.new()
	root.name = "TownDecor"
	add_child(root)
	var grass := Node2D.new()
	grass.name = "TownGrass"
	grass.z_index = -6
	root.add_child(grass)
	var shrubs := Node2D.new()
	shrubs.name = "TownShrubs"
	shrubs.z_index = -4
	root.add_child(shrubs)

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 31

	# Franjas de verde pegadas a la cara interior de los cuatro muros.
	for side in range(4):
		for i in range(30):
			var t: float = (float(i) + 0.5) / 30.0
			var p: Vector2
			match side:
				0: p = Vector2(lerp(-2310.0, -2250.0, rng.randf()), lerp(-1380.0, 1380.0, t))
				1: p = Vector2(lerp(-2300.0, 2300.0, t), lerp(1385.0, 1440.0, rng.randf()))
				2: p = Vector2(lerp(2250.0, 2310.0, rng.randf()), lerp(-1380.0, 1380.0, t))
				_: p = Vector2(lerp(-2300.0, 2300.0, t), lerp(-1440.0, -1385.0, rng.randf()))
			if not _town_spot_ok(p, 34.0, house_rects, road_rects):
				continue
			_add_grass_patch(grass, p, rng.randf_range(46.0, 84.0), rng.randf_range(24.0, 44.0),
				COL_TOWN_GRASS if rng.randf() < 0.65 else COL_TOWN_GRASS_DARK)
			if rng.randf() < 0.72:
				_add_town_shrub(shrubs, p + Vector2(rng.randf_range(-18.0, 18.0), rng.randf_range(-14.0, 14.0)),
					rng.randf_range(12.0, 22.0), rng)

	# Parches dispersos por el resto del barrio, siempre lejos de casas y calles.
	for i in range(420):
		var p := Vector2(rng.randf_range(-2320.0, 2320.0), rng.randf_range(-1420.0, 1420.0))
		if not _town_spot_ok(p, 38.0, house_rects, road_rects):
			continue
		_add_grass_patch(grass, p, rng.randf_range(34.0, 76.0), rng.randf_range(18.0, 40.0),
			COL_TOWN_GRASS if rng.randf() < 0.5 else COL_TOWN_GRASS_DARK)
		if rng.randf() < 0.32:
			_add_town_shrub(shrubs, p + Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(-12.0, 12.0)),
				rng.randf_range(10.0, 18.0), rng)

	# Refuerzo en la esquina de inicio: franjas de verde pegadas a los muros
	# oeste y sur, visibles desde el primer frame sin depender del layout.
	for i in range(14):
		var p := Vector2(-2350.0, 980.0 + float(i) * 34.0)
		if _town_spot_ok(p, 22.0, house_rects, road_rects):
			_add_grass_patch(grass, p, 44.0, 25.0, COL_TOWN_GRASS)
			var bush := p + Vector2(20.0, 0.0)
			if i % 3 == 0 and _town_spot_ok(bush, 12.0, house_rects, road_rects):
				_add_town_shrub(shrubs, bush, 13.0, rng)
	for i in range(14):
		var p := Vector2(-2300.0 + float(i) * 62.0, 1450.0)
		if _town_spot_ok(p, 20.0, house_rects, road_rects):
			_add_grass_patch(grass, p, 40.0, 20.0, COL_TOWN_GRASS_DARK)

	# Unos pocos arboles ornamentales: solo altura visual, sin colisiones.
	var trunk_xf: Array[Transform2D] = []
	var crown_xf: Array[Transform2D] = []
	for i in range(40):
		var p := Vector2(rng.randf_range(-2280.0, 2280.0), rng.randf_range(-1360.0, 1360.0))
		if not _town_spot_ok(p, 54.0, house_rects, road_rects):
			continue
		var h: float = rng.randf_range(54.0, 88.0)
		var r: float = rng.randf_range(20.0, 30.0)
		var t := Transform2D.IDENTITY.scaled(Vector2(6.0, h))
		t.origin = p + Vector2(0.0, -h * 0.5)
		trunk_xf.append(t)
		var c := Transform2D.IDENTITY.scaled(Vector2(r, r * 0.9))
		c.origin = p + Vector2(0.0, -h * 0.82)
		crown_xf.append(c)
		if trunk_xf.size() >= 10:
			break
	if not trunk_xf.is_empty():
		_make_multimesh(root, "TownTreeTrunks", _quad_mesh(), trunk_xf, COL_TOWN_TRUNK, -3)
		_make_multimesh(root, "TownTreeCrowns", _regular_polygon_mesh(10, 1.0, false), crown_xf, COL_TOWN_SHRUB, -2)

func _town_spot_ok(p: Vector2, radius: float, house_rects: Array[Rect2], road_rects: Array) -> bool:
	if absf(p.x) > TOWN_HALF.x - 46.0 or absf(p.y) > TOWN_HALF.y - 46.0:
		return false
	var pad := Vector2(TOWN_CENTER_PAD, TOWN_CENTER_PAD)
	var center := Rect2(p - pad, pad * 2.0)
	var safe := Rect2(p - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	# El campamento del inicio y la zona de extraccion se dejan limpios.
	if center.intersects(Rect2(Vector2(-2130.0, 1320.0), Vector2(150.0, 140.0))):
		return false
	if center.intersects(Rect2(Vector2(1990.0, -1430.0), Vector2(340.0, 200.0))):
		return false
	# El centro no cae sobre una casa; el parche se dibuja por debajo de ella.
	for rect in house_rects:
		if center.intersects(rect as Rect2):
			return false
	# El parche completo evita el asfalto y sus aceras.
	for road in road_rects:
		if safe.intersects((road as Rect2).grow(18.0)):
			return false
	if road_rects.is_empty():
		# Respaldo: evitar la retícula vial 480x300 si aun no hay rects.
		for k in range(11):
			if absf(p.x - (-TOWN_HALF.x + 480.0 * float(k))) < radius + 70.0:
				return false
			if absf(p.y - (-TOWN_HALF.y + 300.0 * float(k))) < radius + 70.0:
				return false
	return true

func _add_grass_patch(parent: Node2D, p: Vector2, rx: float, ry: float, color: Color) -> void:
	var poly := Polygon2D.new()
	poly.name = "GrassPatch"
	poly.position = p
	poly.scale = Vector2(rx, ry)
	poly.polygon = _circle_points(1.0, 10)
	poly.color = color
	parent.add_child(poly)

func _add_town_shrub(parent: Node2D, p: Vector2, radius: float, rng: RandomNumberGenerator) -> void:
	var poly := Polygon2D.new()
	poly.name = "Shrub"
	poly.position = p
	poly.scale = Vector2(radius, radius * rng.randf_range(0.72, 1.0))
	poly.polygon = _circle_points(1.0, 7)
	poly.color = COL_TOWN_SHRUB_LIT if rng.randf() < 0.35 else COL_TOWN_SHRUB
	parent.add_child(poly)

func _build_clearings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	for i in range(14):
		for attempt in range(40):
			var a: float = rng.randf() * TAU
			var radius: float = rng.randf_range(1800.0, 5600.0)
			var p := Vector2(cos(a) * radius * 0.78, sin(a) * radius)
			if _edge_distance(p) < 400.0:
				continue
			var ok := true
			for c in _clearings:
				if p.distance_to(Vector2(c["pos"])) < 520.0:
					ok = false
					break
			if not ok:
				continue
			_clearings.append({"pos": p, "radius": rng.randf_range(180.0, 420.0)})
			break

	var clear_node := Node2D.new()
	clear_node.name = "Clearings"
	clear_node.z_index = -7
	add_child(clear_node)
	for c in _clearings:
		var p := Vector2(c["pos"])
		var r: float = float(c["radius"])
		var poly := Polygon2D.new()
		poly.position = p
		poly.polygon = _circle_points(r, 20)
		poly.color = COL_CLEARING
		poly.z_index = -7
		clear_node.add_child(poly)

func _build_paths() -> void:
	# Tres accesos futuros: norte, oeste y sur. Se dibuja un sendero hacia los
	# dos claros más cercanos para que el bosque tenga dirección legible.
	var gates := [
		Vector2(1200.0, -1500.0),
		Vector2(-2400.0, -600.0),
		Vector2(1200.0, 1500.0),
	]
	for gate in gates:
		var sorted: Array[Dictionary] = _clearings.duplicate()
		sorted.sort_custom(func(a, b):
			return Vector2(a["pos"]).distance_to(gate) < Vector2(b["pos"]).distance_to(gate)
		)
		for i in range(mini(2, sorted.size())):
			var dest := Vector2(sorted[i]["pos"])
			_paths.append({"a": gate, "b": dest})

	var paths_node := Node2D.new()
	paths_node.name = "Paths"
	paths_node.z_index = -6
	add_child(paths_node)
	for path in _paths:
		_add_thick_segment(paths_node, Vector2(path["a"]), Vector2(path["b"]), 90.0, COL_PATH, -6)

func _add_thick_segment(parent: Node2D, a: Vector2, b: Vector2, width: float, color: Color, z: int) -> void:
	var dir := (b - a).normalized()
	var normal := Vector2(-dir.y, dir.x) * width * 0.5
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([a + normal, b + normal, b - normal, a - normal])
	poly.color = color
	poly.z_index = z
	parent.add_child(poly)

func _dist_to_path(p: Vector2) -> float:
	var best: float = INF
	for path in _paths:
		best = minf(best, _point_segment_distance(p, Vector2(path["a"]), Vector2(path["b"])))
	return best

func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2: float = ab.length_squared()
	if len2 <= 0.0:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# --- Río y puentes: solo Polygon2D, sin cuerpos ni obstáculos de navegación. ---
func _river_y(x: float) -> float:
	return -3600.0 + 380.0 * sin((x + WORLD_HALF.x) / 2600.0 * TAU)

func _build_river_points() -> void:
	_river_points.clear()
	var x: float = -WORLD_HALF.x
	while x <= WORLD_HALF.x + 0.1:
		_river_points.append(Vector2(x, _river_y(x)))
		x += RIVER_STEP

func _river_strip(half_width: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n: int = _river_points.size()
	for i in range(n):
		var p: Vector2 = _river_points[i]
		var tangent: Vector2 = Vector2.RIGHT
		if i == 0 and n > 1:
			tangent = (_river_points[1] - p).normalized()
		elif i == n - 1 and n > 1:
			tangent = (p - _river_points[i - 1]).normalized()
		elif n > 2:
			tangent = (_river_points[i + 1] - _river_points[i - 1]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		left.append(p - normal * half_width)
		right.append(p + normal * half_width)
	var poly := PackedVector2Array()
	poly.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	return poly

## Verdadero si el punto cae dentro del canal (margen extra en píxeles).
func _in_river(p: Vector2, margin: float = 0.0) -> bool:
	var limit: float = RIVER_HALF_WIDTH + margin
	if _river_points.size() < 2:
		return absf(p.y - _river_y(p.x)) <= limit + 1.0
	for i in range(_river_points.size() - 1):
		var a: Vector2 = _river_points[i]
		var b: Vector2 = _river_points[i + 1]
		if p.x < minf(a.x, b.x) - limit or p.x > maxf(a.x, b.x) + limit:
			continue
		if _point_segment_distance(p, a, b) <= limit:
			return true
	return false

func _build_river() -> void:
	_build_river_points()
	var root := Node2D.new()
	root.name = "River"
	add_child(root)

	var banks := Polygon2D.new()
	banks.name = "Riverbanks"
	banks.polygon = _river_strip(RIVER_HALF_WIDTH + RIVER_BANK_WIDTH)
	banks.color = RIVER_BANK_COLOR
	banks.z_index = -3
	root.add_child(banks)

	var water := Polygon2D.new()
	water.name = "Water"
	water.polygon = _river_strip(RIVER_HALF_WIDTH)
	water.color = RIVER_COLOR
	water.z_index = -2
	root.add_child(water)

	var bridges := Node2D.new()
	bridges.name = "Bridges"
	root.add_child(bridges)
	_add_bridge(bridges, BRIDGE_X_LEFT)
	_add_bridge(bridges, BRIDGE_X_RIGHT)

func _add_bridge(parent: Node2D, x: float) -> void:
	var bridge := Node2D.new()
	bridge.name = "Bridge_%s" % ("West" if x < 0.0 else "East")
	bridge.position = Vector2(x, _river_y(x))
	# El nodo se alinea con la tangente del río; el tablero cruza en local Y.
	var slope: float = 380.0 * (TAU / 2600.0) * cos((x + WORLD_HALF.x) / 2600.0 * TAU)
	bridge.rotation = atan(slope)
	parent.add_child(bridge)

	var deck := Polygon2D.new()
	deck.name = "Deck"
	deck.polygon = PackedVector2Array([
		Vector2(-BRIDGE_HALF_ALONG, -BRIDGE_HALF_CROSS),
		Vector2(BRIDGE_HALF_ALONG, -BRIDGE_HALF_CROSS),
		Vector2(BRIDGE_HALF_ALONG, BRIDGE_HALF_CROSS),
		Vector2(-BRIDGE_HALF_ALONG, BRIDGE_HALF_CROSS),
	])
	deck.color = BRIDGE_COLOR
	deck.z_index = -1
	bridge.add_child(deck)

	# Listones transversales: dibujan las tablas sobre el tablero.
	var step: float = 2.0 * BRIDGE_HALF_ALONG / float(BRIDGE_PLANKS)
	for i in range(BRIDGE_PLANKS):
		var cx: float = -BRIDGE_HALF_ALONG + step * (float(i) + 0.5)
		var half: float = step * 0.30
		var plank := Polygon2D.new()
		plank.name = "Plank_%02d" % i
		plank.polygon = PackedVector2Array([
			Vector2(cx - half, -BRIDGE_HALF_CROSS),
			Vector2(cx + half, -BRIDGE_HALF_CROSS),
			Vector2(cx + half, BRIDGE_HALF_CROSS),
			Vector2(cx - half, BRIDGE_HALF_CROSS),
		])
		plank.color = BRIDGE_PLANK_COLOR
		plank.z_index = 0
		bridge.add_child(plank)

func _build_trees() -> void:
	var trees: Array[Dictionary] = []
	for cy in range(GRID):
		for cx in range(GRID):
			var base := Vector2(cx, cy) * CELL - WORLD_HALF + Vector2(CELL * 0.5, CELL * 0.5)
			var p := base + Vector2(_rng.randf_range(-110.0, 110.0), _rng.randf_range(-110.0, 110.0))
			if Rect2(-TOWN_HALF, TOWN_HALF * 2.0).grow(40.0).has_point(p):
				continue
			# El canal queda despejado: ni un árbol a menos de 60 px de la orilla.
			if _in_river(p, RIVER_TREE_CLEARANCE):
				continue

			var d: float = _edge_distance(p)
			var band: Dictionary = _band(d)
			var mult := 1.0
			for c in _clearings:
				if p.distance_to(Vector2(c["pos"])) < float(c["radius"]):
					mult = 0.12
					break
			if _dist_to_path(p) < 70.0:
				mult = minf(mult, 0.02)
			if _rng.randf() >= float(band["density"]) * mult:
				continue

			var roll: float = _rng.randf()
			var kind: int = 2 if roll < 0.08 else (1 if roll < 0.50 else 0)
			var r: float = _rng.randf_range(float(band["r_min"]), float(band["r_max"]))
			var h: float = _rng.randf_range(float(band["h_min"]), float(band["h_max"]))
			trees.append({"pos": p, "r": r, "h": h, "kind": kind})

	_tree_count = trees.size()
	_build_tree_colliders(trees)

	var trunk_xf: Array[Transform2D] = []
	var round_xf: Array[Transform2D] = []
	var ragged_xf: Array[Transform2D] = []
	var light_xf: Array[Transform2D] = []
	var dead_xf: Array[Transform2D] = []
	var shadow_xf: Array[Transform2D] = []

	for t in trees:
		var p := Vector2(t["pos"])
		var r: float = float(t["r"])
		var h: float = float(t["h"])
		var kind: int = int(t["kind"])

		var trunk := Transform2D.IDENTITY
		trunk = trunk.scaled(Vector2(maxf(4.0, r * 0.28), h))
		trunk.origin = p + Vector2(0.0, -h * 0.5)
		trunk_xf.append(trunk)

		var canopy := Transform2D.IDENTITY
		canopy = canopy.scaled(Vector2(r * _rng.randf_range(0.85, 1.15), r * _rng.randf_range(0.9, 1.1)))
		canopy.origin = p + Vector2(0.0, -h * 0.78)
		match kind:
			0: round_xf.append(canopy)
			1: ragged_xf.append(canopy)
			2:
				var dead := Transform2D.IDENTITY
				dead = dead.scaled(Vector2(h * 0.42, h * 0.42))
				dead.origin = p + Vector2(0.0, -h * 0.62)
				dead_xf.append(dead)
		if kind != 2 and _rng.randf() < 0.12:
			light_xf.append(canopy)

		var shadow := Transform2D.IDENTITY
		shadow = shadow.scaled(Vector2(r * 1.4, r * 0.45))
		shadow.origin = p + Vector2(-14.0, 10.0)
		shadow_xf.append(shadow)

	var visual := Node2D.new()
	visual.name = "TreeMeshes"
	add_child(visual)

	var quad := _quad_mesh()
	var circle := _regular_polygon_mesh(12, 1.0, false)
	var ragged := _regular_polygon_mesh(12, 1.0, true)
	var branches := _branch_mesh(5)

	_make_multimesh(visual, "Shadows", circle, shadow_xf, COL_SHADOW, -5)
	_make_multimesh(visual, "Trunks", quad, trunk_xf, COL_TRUNK, 0)
	_make_multimesh(visual, "CanopyRound", circle, round_xf, COL_CANOPY_DARK, 2)
	_make_multimesh(visual, "CanopyRagged", ragged, ragged_xf, COL_CANOPY_MID, 2)
	_make_multimesh(visual, "CanopyLight", circle, light_xf, COL_CANOPY_LIGHT, 3)
	_make_multimesh(visual, "CanopyDead", branches, dead_xf, COL_DEAD, 2)

func _build_tree_colliders(trees: Array[Dictionary]) -> void:
	var bodies: Dictionary = {}
	for t in trees:
		var p := Vector2(t["pos"])
		var key := Vector2i(int((p.x + WORLD_HALF.x) / CHUNK), int((p.y + WORLD_HALF.y) / CHUNK))
		if not bodies.has(key):
			var body := StaticBody2D.new()
			body.name = "Chunk_r%dc%d" % [key.x, key.y]
			body.collision_layer = 1
			body.collision_mask = 1
			add_child(body)
			bodies[key] = body
		var shape := CircleShape2D.new()
		shape.radius = clampf(float(t["r"]) * 0.30, 7.0, 12.0)
		_shapes.append(shape)
		var xf := Transform2D.IDENTITY
		xf.origin = p
		PhysicsServer2D.body_add_shape((bodies[key] as StaticBody2D).get_rid(), shape.get_rid(), xf)

func _build_litter() -> void:
	var xf: Array[Transform2D] = []
	for i in range(1200):
		var p := Vector2(
			_rng.randf_range(-WORLD_HALF.x + 80.0, WORLD_HALF.x - 80.0),
			_rng.randf_range(-WORLD_HALF.y + 80.0, WORLD_HALF.y - 80.0)
		)
		if not in_forest(p):
			continue
		var s: float = _rng.randf_range(3.0, 8.0)
		var t := Transform2D.IDENTITY
		t = t.rotated(_rng.randf_range(0.0, TAU)).scaled(Vector2(s, s * 0.6))
		t.origin = p
		xf.append(t)
	var litter := Node2D.new()
	litter.name = "Litter"
	litter.z_index = -4
	add_child(litter)
	_make_multimesh(litter, "Leaves", _regular_polygon_mesh(5, 1.0, false), xf, COL_LITTER, -4)

func _build_nav_thickets() -> void:
	# Matorrales que recortan el navmesh. No son StaticBody2D: solo aportan
	# geometria al parser de navegacion, nunca colision fisica ni QA de spawns.
	var root := Node2D.new()
	root.name = "NavThickets"
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 5
	var gates := [
		Vector2(1200.0, -TOWN_HALF.y), Vector2(-TOWN_HALF.x, -600.0),
		Vector2(1200.0, TOWN_HALF.y),
	]
	var placed: int = 0
	for i in range(160):
		if placed >= 42:
			break
		var p := Vector2(
			rng.randf_range(-WORLD_HALF.x + 500.0, WORLD_HALF.x - 500.0),
			rng.randf_range(-WORLD_HALF.y + 500.0, WORLD_HALF.y - 500.0)
		)
		if not in_forest(p):
			continue
		var radius: float = rng.randf_range(170.0, 320.0)
		var blocked := false
		for gate in gates:
			if p.distance_to(Vector2(gate)) < radius + 380.0:
				blocked = true
				break
		if blocked or _dist_to_path(p) < radius + 140.0:
			continue
		var poly := CollisionPolygon2D.new()
		poly.position = p
		poly.polygon = _circle_points(radius, 10)
		root.add_child(poly)
		placed += 1

func _density_at(p: Vector2) -> float:
	if not in_forest(p):
		return 0.0
	var value: float = float(_band(_edge_distance(p))["density"])
	for c in _clearings:
		if p.distance_to(Vector2(c["pos"])) < float(c["radius"]):
			value *= 0.25
			break
	if _dist_to_path(p) < 70.0:
		value *= 0.05
	return value

## Textura 84x84 para la capa de densidad del minimapa. Se crea una vez.
func get_density_texture() -> ImageTexture:
	if _density_tex != null:
		return _density_tex
	var size: int = 84
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var p := Vector2(
				lerp(-WORLD_HALF.x, WORLD_HALF.x, float(x) / float(size - 1)),
				lerp(-WORLD_HALF.y, WORLD_HALF.y, float(y) / float(size - 1))
			)
			var dens: float = _density_at(p)
			if dens <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				img.set_pixel(x, y, Color(0.10, 0.16, 0.10, clampf(dens * 0.75, 0.0, 0.75)))
	_density_tex = ImageTexture.create_from_image(img)
	return _density_tex

func _build_fog() -> void:
	var fog_root := Node2D.new()
	fog_root.name = "FogBands"
	add_child(fog_root)
	for i in range(6):
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(-400, -110), Vector2(400, -110), Vector2(400, 110), Vector2(-400, 110),
		])
		poly.color = COL_FOG
		poly.z_index = 9
		var p := Vector2(
			_rng.randf_range(-WORLD_HALF.x, WORLD_HALF.x),
			_rng.randf_range(-WORLD_HALF.y, WORLD_HALF.y)
		)
		if not in_forest(p):
			p.x += 3000.0 if p.x < 0.0 else -3000.0
		poly.position = p
		fog_root.add_child(poly)
		_fog_bands.append({"node": poly, "speed": _rng.randf_range(6.0, 16.0)})

# --- Fase 4: botín en claros y spawn de zombies del bosque. ---
func _forest_gates() -> Array[Vector2]:
	return [
		Vector2(1200.0, -1500.0),
		Vector2(-2400.0, -600.0),
		Vector2(1200.0, 1500.0),
	]

func _build_loot() -> void:
	if _clearings.is_empty():
		return
	# Sin combustible: no debe falsificar los sectores de QA.
	var definitions: Array[Dictionary] = [
		{"id": "comida", "amount": 2, "name": "mochila"},
		{"id": "comida", "amount": 3, "name": "mochila"},
		{"id": "comida", "amount": 2, "name": "caja"},
		{"id": "comida", "amount": 3, "name": "mochila"},
		{"id": "pistol_ammo", "amount": 8, "name": "caja"},
		{"id": "pistol_ammo", "amount": 6, "name": "caja"},
		{"id": "pistol_ammo", "amount": 10, "name": "mochila"},
		{"id": "medkit", "amount": 1, "name": "botiquín"},
		{"id": "medkit", "amount": 1, "name": "botiquín"},
		{"id": "", "amount": 0, "name": "caja"},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 11
	var gates: Array[Vector2] = _forest_gates()
	var root := Node2D.new()
	root.name = "ForestLoot"
	add_child(root)
	var placed: Array[Vector2] = []

	for di in range(definitions.size()):
		var def: Dictionary = definitions[di]
		var spot := Vector2.ZERO
		var found := false
		for attempt in range(240):
			var c: Dictionary = _clearings[rng.randi_range(0, _clearings.size() - 1)]
			var center: Vector2 = Vector2(c["pos"])
			var radius: float = float(c["radius"]) * 0.7
			var ang: float = rng.randf() * TAU
			var dist: float = sqrt(rng.randf()) * radius
			var p: Vector2 = center + Vector2(cos(ang), sin(ang)) * dist
			if not _loot_spot_ok(p, placed, gates):
				continue
			spot = p
			found = true
			break
		if not found:
			# Respaldo determinista: anillos concéntricos dentro de los claros.
			for fc in _clearings:
				var fcenter: Vector2 = Vector2(fc["pos"])
				for ring in [0.0, 0.35, 0.7, 1.0]:
					for k in range(8):
						var fang: float = TAU * float(k) / 8.0 + float(di) * 0.17
						var fp: Vector2 = fcenter + Vector2(cos(fang), sin(fang)) * (float(fc["radius"]) * float(ring) * 0.8)
						if not _loot_spot_ok(fp, placed, gates):
							continue
						spot = fp
						found = true
						break
					if found:
						break
				if found:
					break
		if not found:
			continue
		var loot_node: Node = _spawn_forest_loot(root, LOOT_SCENE, def, di, spot)
		var loot_id: String = str(def["id"])
		# Solo se puede regenerar botín que no sea FUEL ni FOOD de QA.
		if loot_node != null and loot_id != "combustible" and loot_id != "comida":
			_loot_records.append({
				"node": loot_node,
				"parent": root,
				"def": def.duplicate(),
				"index": di,
				"pos": spot,
			})
		placed.append(spot)

func _loot_spot_ok(p: Vector2, placed: Array[Vector2], gates: Array[Vector2]) -> bool:
	if _in_river(p, 20.0):
		return false
	for gate in gates:
		if p.distance_to(gate) <= 400.0:
			return false
	for q in placed:
		if p.distance_to(q) < 120.0:
			return false
	return true

func _spawn_forest_loot(parent: Node2D, scene: PackedScene, def: Dictionary, index: int, p: Vector2) -> Node:
	var container: Node = scene.instantiate()
	if container == null:
		return null
	container.name = "Loot_%02d" % index
	container.set("item_id", str(def["id"]))
	container.set("amount", int(def["amount"]))
	container.set("container_name", str(def["name"]))
	container.position = p
	parent.add_child(container)
	return container

## Puntos deterministas para zombies del bosque; no se mezclan con Neighborhood.
func forest_zombie_spawn_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	if _clearings.is_empty():
		return points
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	var gates: Array[Vector2] = _forest_gates()
	var order: Array[int] = []
	for i in range(_clearings.size()):
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	var target: int = 7
	var tries: int = 0
	while points.size() < target and tries < 240:
		var c: Dictionary = _clearings[order[tries % order.size()]]
		tries += 1
		var center: Vector2 = Vector2(c["pos"])
		var radius: float = float(c["radius"]) * rng.randf_range(0.4, 1.05)
		var ang: float = rng.randf() * TAU
		var p: Vector2 = center + Vector2(cos(ang), sin(ang)) * radius
		if _edge_distance(p) <= 900.0:
			continue
		var blocked := false
		for gate in gates:
			if p.distance_to(gate) <= 600.0:
				blocked = true
				break
		if blocked or _in_river(p, 30.0):
			continue
		points.append(p)

	# Respaldos acotados por si algún claro queda cerca de los límites.
	var fallback: int = 0
	while points.size() < 6 and fallback < 200:
		fallback += 1
		var bc: Dictionary = _clearings[rng.randi_range(0, _clearings.size() - 1)]
		var bp: Vector2 = Vector2(bc["pos"]) + Vector2(
			rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)
		) * float(bc["radius"])
		if _edge_distance(bp) <= 900.0 or _in_river(bp, 30.0):
			continue
		var fb_blocked := false
		for gate in gates:
			if bp.distance_to(gate) <= 600.0:
				fb_blocked = true
				break
		if not fb_blocked:
			points.append(bp)
	return points

# --- API para WorldDirector (clima, eventos y regeneración de loot). ---

## Centros de los claros, en coordenadas de mundo. Solo lectura.
func clearing_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for c in _clearings:
		points.append(Vector2(c["pos"]))
	return points

## Comprueba que un punto sirve para un evento dinámico: dentro del bosque,
## fuera del río y lejos de las tres puertas. No crea colisiones ni nav.
func is_valid_event_point(p: Vector2) -> bool:
	if not in_forest(p):
		return false
	if _in_river(p, 24.0):
		return false
	for gate in _forest_gates():
		if p.distance_to(gate) <= 420.0:
			return false
	return true

## Intensidad de niebla 0..1. Solo modula el alpha de las bandas ya existentes.
func set_weather_fog(amount: float) -> void:
	_weather_fog = clampf(amount, 0.0, 1.0)
	var alpha: float = COL_FOG.a * (1.0 + _weather_fog * 3.5)
	for band in _fog_bands:
		var node: Polygon2D = band["node"] as Polygon2D
		if node != null:
			node.color = Color(COL_FOG.r, COL_FOG.g, COL_FOG.b, alpha)

## Multiplicador de velocidad del ambiente (deriva de las bandas de niebla).
func set_weather_speed_multiplier(multiplier: float) -> void:
	_weather_speed = clampf(multiplier, 0.4, 1.6)

## Regenera únicamente el botín no-FUEL y no-FOOD que ya fue saqueado.
## Devuelve cuántos contenedores se han restaurado.
func respawn_forest_loot() -> int:
	var restored: int = 0
	for record in _loot_records:
		var old_node: Node = record.get("node") as Node
		if old_node != null and is_instance_valid(old_node):
			if not bool(old_node.get("_looted")):
				continue
			record["node"] = null
			old_node.free()
		var parent: Node2D = record.get("parent") as Node2D
		if parent == null or not is_instance_valid(parent):
			continue
		var def: Dictionary = record.get("def", {})
		if def.is_empty():
			continue
		var index: int = int(record.get("index", 0))
		var p: Vector2 = record.get("pos", Vector2.ZERO)
		var fresh: Node = _spawn_forest_loot(parent, LOOT_SCENE, def, index, p)
		record["node"] = fresh
		if fresh != null:
			restored += 1
	return restored

func _process(delta: float) -> void:
	for band in _fog_bands:
		var node: Polygon2D = band["node"] as Polygon2D
		if node == null:
			continue
		node.position.x += float(band["speed"]) * _weather_speed * delta
		if node.position.x > WORLD_HALF.x + 400.0:
			node.position.x = -WORLD_HALF.x - 400.0

func _make_multimesh(parent: Node2D, name: String, mesh: Mesh,
		transforms: Array[Transform2D], color: Color, z: int) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform_2d(i, transforms[i])
	var inst := MultiMeshInstance2D.new()
	inst.name = name
	inst.multimesh = mm
	inst.modulate = color
	inst.z_index = z
	parent.add_child(inst)

func _quad_mesh() -> ArrayMesh:
	return _mesh_from_quads([PackedVector2Array([
		Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5),
	])])

func _regular_polygon_mesh(sides: int, radius: float, ragged: bool) -> ArrayMesh:
	var points := PackedVector2Array()
	for i in range(sides):
		var a: float = TAU * float(i) / float(sides)
		var r: float = radius * (0.72 if (ragged and i % 3 == 0) else 1.0)
		points.append(Vector2(cos(a), sin(a)) * r)
	return _mesh_from_polygon(points)

func _branch_mesh(count: int) -> ArrayMesh:
	var quads: Array = []
	for i in range(count):
		var a: float = TAU * float(i) / float(count) + 0.2
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x) * 0.035
		quads.append(PackedVector2Array([
			-side, side, dir * 0.95 + side * 0.5, dir * 0.95 - side * 0.5,
		]))
	return _mesh_from_quads(quads)

func _mesh_from_polygon(points: PackedVector2Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, points.size() - 1):
		st.add_vertex(Vector3(points[0].x, points[0].y, 0.0))
		st.add_vertex(Vector3(points[i].x, points[i].y, 0.0))
		st.add_vertex(Vector3(points[i + 1].x, points[i + 1].y, 0.0))
	return st.commit()

func _mesh_from_quads(quads: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in quads:
		var quad: PackedVector2Array = q
		st.add_vertex(Vector3(quad[0].x, quad[0].y, 0.0))
		st.add_vertex(Vector3(quad[1].x, quad[1].y, 0.0))
		st.add_vertex(Vector3(quad[2].x, quad[2].y, 0.0))
		st.add_vertex(Vector3(quad[0].x, quad[0].y, 0.0))
		st.add_vertex(Vector3(quad[2].x, quad[2].y, 0.0))
		st.add_vertex(Vector3(quad[3].x, quad[3].y, 0.0))
	return st.commit()

func _circle_points(radius: float, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(sides):
		var a: float = TAU * float(i) / float(sides)
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points
