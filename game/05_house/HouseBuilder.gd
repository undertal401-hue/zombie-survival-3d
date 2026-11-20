extends Node
class_name HouseBuilder

## =============================================================================
## HOUSE BUILDER - Generador procedural de casas modulares
## =============================================================================

var _parts_library: Dictionary = {}
var _rng: RandomNumberGenerator

const TILE_SIZE: int = 64

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_load_parts_library()

func _load_parts_library() -> void:
	# Cargar partes desde archivos .tres o crear por defecto
	# Por ahora crear library programática
	_create_default_library()

func _create_default_library() -> void:
	# Crear materiales básicos
	var materials: Array[HousePart.WallMaterial] = [
		HousePart.WallMaterial.WOOD,
		HousePart.WallMaterial.BRICK,
		HousePart.WallMaterial.CONCRETE,
		HousePart.WallMaterial.METAL,
		HousePart.WallMaterial.PLASTER
	]
	
	for mat in materials:
		_parts_library[mat] = {}
		var lib: Dictionary = _parts_library[mat]
		
		# Paredes
		lib[HousePart.PartType.WALL] = _create_part(HousePart.PartType.WALL, mat, 1, 2)
		lib[HousePart.PartType.WALL_CORNER] = _create_part(HousePart.PartType.WALL_CORNER, mat, 1, 1)
		lib[HousePart.PartType.WALL_WINDOW] = _create_part(HousePart.PartType.WALL_WINDOW, mat, 1, 2)
		lib[HousePart.PartType.WALL_DOOR] = _create_part(HousePart.PartType.WALL_DOOR, mat, 1, 2)
		
		# Suelo/Techo
		lib[HousePart.PartType.FLOOR] = _create_part(HousePart.PartType.FLOOR, mat, 2, 2)
		lib[HousePart.PartType.ROOF_FLAT] = _create_part(HousePart.PartType.ROOF_FLAT, mat, 2, 2)
		lib[HousePart.PartType.ROOF_SLOPE] = _create_part(HousePart.PartType.ROOF_SLOPE, mat, 2, 2)
		lib[HousePart.PartType.ROOF_CORNER] = _create_part(HousePart.PartType.ROOF_CORNER, mat, 1, 1)

func _create_part(type: int, material: int, w: int, h: int) -> HousePart:
	var part: HousePart = HousePart.new()
	part.part_type = type
	part.material = material
	part.size = Vector2i(w * TILE_SIZE, h * TILE_SIZE)
	
	# Generar textura procedural por ahora
	part.texture = _generate_part_texture(type, material, w, h)
	
	# Collision shape
	var col_scene: PackedScene = PackedScene.new()
	var col_node: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(w * TILE_SIZE, h * TILE_SIZE)
	col_node.shape = rect
	col_scene.pack(col_node)
	part.collision_shape = col_scene
	# `pack()` serializa el nodo pero NO lo libera: el nodo temporal se
	# quedaba vivo con su RectangleShape2D y sus 40 RIDs (5 materiales x 8
	# tipos) se reportaban como "leaked at exit". Este modulo no lo carga
	# nadie, asi que la fuga solo aparecia al instanciarlo (lo hace
	# `CodeIntegrityTest`).
	col_node.free()
	
	# Occluder
	var hw: float = w * TILE_SIZE * 0.5
	var hh: float = h * TILE_SIZE * 0.5
	part.occluder_polygon = PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh),
		Vector2(hw, hh), Vector2(-hw, hh)
	])
	
	# Health por material
	match material:
		HousePart.WallMaterial.WOOD: part.health = 80.0
		HousePart.WallMaterial.BRICK: part.health = 150.0
		HousePart.WallMaterial.CONCRETE: part.health = 300.0
		HousePart.WallMaterial.METAL: part.health = 200.0
		HousePart.WallMaterial.PLASTER: part.health = 60.0
	
	return part

func _generate_part_texture(type: int, material: int, w: int, h: int) -> Texture2D:
	var img: Image = Image.create(w * TILE_SIZE, h * TILE_SIZE, false, Image.FORMAT_RGBA8)
	
	# Colores base por material
	var base_color: Color
	match material:
		HousePart.WallMaterial.WOOD: base_color = Color(0.55, 0.35, 0.2, 1)
		HousePart.WallMaterial.BRICK: base_color = Color(0.65, 0.25, 0.15, 1)
		HousePart.WallMaterial.CONCRETE: base_color = Color(0.5, 0.5, 0.5, 1)
		HousePart.WallMaterial.METAL: base_color = Color(0.55, 0.55, 0.6, 1)
		HousePart.WallMaterial.PLASTER: base_color = Color(0.85, 0.82, 0.78, 1)
	
	img.fill(base_color)
	
	# Añadir detalle según tipo
	match type:
		HousePart.PartType.WALL:
			_draw_wood_planks(img, w, h) if material == HousePart.WallMaterial.WOOD else _draw_brick_pattern(img, w, h) if material == HousePart.WallMaterial.BRICK else _draw_concrete_texture(img, w, h) if material == HousePart.WallMaterial.CONCRETE else _draw_metal_sheets(img, w, h) if material == HousePart.WallMaterial.METAL else _draw_plaster_texture(img, w, h)
		HousePart.PartType.WALL_WINDOW:
			_draw_window(img, w, h, base_color)
		HousePart.PartType.WALL_DOOR:
			_draw_door(img, w, h, base_color)
		HousePart.PartType.FLOOR:
			_draw_floor_texture(img, w, h, material)
		HousePart.PartType.ROOF_FLAT:
			_draw_roof_flat(img, w, h, material)
		HousePart.PartType.ROOF_SLOPE:
			_draw_roof_slope(img, w, h, material)
	
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	return tex

func _draw_wood_planks(img: Image, w: int, h: int) -> void:
	var plank_h: int = 32
	for y in range(0, h * TILE_SIZE, plank_h):
		var color_var: float = randf_range(-0.05, 0.05)
		for x in range(w * TILE_SIZE):
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r + color_var, c.g + color_var, c.b + color_var, 1))
		# Línea entre tablones
		if y + 1 < h * TILE_SIZE:
			for x in range(w * TILE_SIZE):
				img.set_pixel(x, y + 1, Color(0.2, 0.15, 0.1, 1))

func _draw_brick_pattern(img: Image, w: int, h: int) -> void:
	var brick_w: int = 48
	var brick_h: int = 20
	var mortar: Color = Color(0.4, 0.35, 0.3, 1)
	
	for by in range(0, h * TILE_SIZE, brick_h):
		var offset: int = 0 if (by / brick_h) % 2 == 0 else brick_w / 2
		for bx in range(offset, w * TILE_SIZE, brick_w):
			# Mortero horizontal
			for mx in range(brick_w):
				if bx + mx < w * TILE_SIZE:
					for my in range(2):
						if by + my < h * TILE_SIZE:
							img.set_pixel(bx + mx, by + my, mortar)
			# Mortero vertical
			for my in range(brick_h):
				if by + my < h * TILE_SIZE:
					for mx in range(2):
						if bx + mx < w * TILE_SIZE:
							img.set_pixel(bx + mx, by + my, mortar)

func _draw_concrete_texture(img: Image, w: int, h: int) -> void:
	# Ruido sutil para concreto
	for y in range(h * TILE_SIZE):
		for x in range(w * TILE_SIZE):
			var n: float = randf() * 0.03
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r + n, c.g + n, c.b + n, 1))

func _draw_metal_sheets(img: Image, w: int, h: int) -> void:
	var sheet_w: int = 64
	var seam: Color = Color(0.35, 0.35, 0.4, 1)
	for x in range(0, w * TILE_SIZE, sheet_w):
		for y in range(h * TILE_SIZE):
			if x < w * TILE_SIZE:
				img.set_pixel(x, y, seam)
				if x + 1 < w * TILE_SIZE:
					img.set_pixel(x + 1, y, seam)

func _draw_plaster_texture(img: Image, w: int, h: int) -> void:
	# Textura sutil de estuco
	for y in range(h * TILE_SIZE):
		for x in range(w * TILE_SIZE):
			var n: float = randf() * 0.02
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r + n, c.g + n, c.b + n, 1))
	# Grietas ocasionales
	for i in range(3):
		var cx: int = randi() % (w * TILE_SIZE)
		var cy: int = randi() % (h * TILE_SIZE)
		for j in range(randi() % 20 + 10):
			var nx: int = cx + randi() % 5 - 2
			var ny: int = cy + randi() % 5 - 2
			if nx >= 0 and nx < w * TILE_SIZE and ny >= 0 and ny < h * TILE_SIZE:
				img.set_pixel(nx, ny, Color(0.4, 0.38, 0.35, 1))

func _draw_window(img: Image, w: int, h: int, base: Color) -> void:
	# Fondo pared
	img.fill(base)
	# Ventana
	var win_w: int = w * TILE_SIZE - 32
	var win_h: int = h * TILE_SIZE - 32
	var win_x: int = 16
	var win_y: int = 16
	var glass: Color = Color(0.2, 0.3, 0.45, 1)
	var frame: Color = Color(0.25, 0.2, 0.15, 1)
	
	for y in range(win_y, win_y + win_h):
		for x in range(win_x, win_x + win_w):
			if x < win_x + 4 or x >= win_x + win_w - 4 or y < win_y + 4 or y >= win_y + win_h - 4:
				img.set_pixel(x, y, frame)
			else:
				img.set_pixel(x, y, glass)

func _draw_door(img: Image, w: int, h: int, base: Color) -> void:
	img.fill(base)
	var door_w: int = 48
	var door_h: int = h * TILE_SIZE - 16
	var door_x: int = (w * TILE_SIZE - door_w) / 2
	var door_y: int = 8
	var door_color: Color = Color(0.3, 0.18, 0.1, 1)
	var handle: Color = Color(0.6, 0.5, 0.3, 1)
	
	for y in range(door_y, door_y + door_h):
		for x in range(door_x, door_x + door_w):
			if x < door_x + 4 or x >= door_x + door_w - 4 or y < door_y + 4:
				img.set_pixel(x, y, Color(0.2, 0.15, 0.1, 1))
			else:
				img.set_pixel(x, y, door_color)
	# Manija
	img.set_pixel(door_x + door_w - 8, door_y + door_h / 2, handle)

func _draw_floor_texture(img: Image, w: int, h: int, material: int) -> void:
	match material:
		HousePart.WallMaterial.WOOD: _draw_wood_planks(img, w, h)
		HousePart.WallMaterial.CONCRETE: _draw_concrete_texture(img, w, h)
		HousePart.WallMaterial.METAL: _draw_metal_sheets(img, w, h)
		_: _draw_concrete_texture(img, w, h)

func _draw_roof_flat(img: Image, w: int, h: int, material: int) -> void:
	var base: Color
	match material:
		HousePart.WallMaterial.WOOD: base = Color(0.3, 0.2, 0.1, 1)
		HousePart.WallMaterial.BRICK: base = Color(0.4, 0.2, 0.1, 1)
		HousePart.WallMaterial.CONCRETE: base = Color(0.35, 0.35, 0.35, 1)
		HousePart.WallMaterial.METAL: base = Color(0.4, 0.4, 0.45, 1)
		_: base = Color(0.45, 0.4, 0.35, 1)
	img.fill(base)
	# Detalles techo
	for i in range(10):
		var x: int = randi() % (w * TILE_SIZE)
		var y: int = randi() % (h * TILE_SIZE)
		var c: Color = img.get_pixel(x, y)
		img.set_pixel(x, y, Color(c.r * 0.8, c.g * 0.8, c.b * 0.8, 1))

func _draw_roof_slope(img: Image, w: int, h: int, material: int) -> void:
	_draw_roof_flat(img, w, h, material)
	# Gradiente para pendiente
	for y in range(h * TILE_SIZE):
		var factor: float = y / (h * TILE_SIZE)
		for x in range(w * TILE_SIZE):
			var c: Color = img.get_pixel(x, y)
			var darken: float = 0.1 * factor
			img.set_pixel(x, y, Color(c.r - darken, c.g - darken, c.b - darken, 1))

## API pública

func get_part(type: int, material: int) -> HousePart:
	# La biblioteca se indexa por el ENUM de material (int) y, dentro, por el
	# enum de tipo de pieza (int): no por nombres. Antes esta línea pedía
	# `material.keys()[material]`, es decir, `.keys()` sobre un int: error de
	# parseo ("Cannot find member 'keys' in base 'int'") que dejaba TODO el
	# script sin compilar y que solo se veía al abrir el editor.
	if _parts_library.has(material) and _parts_library[material].has(type):
		return _parts_library[material][type]
	return null

func build_house(plan: Dictionary, position: Vector2) -> Node2D:
	# plan = { "size": Vector2i(w,h), "material": mat, "rooms": [], "doors": [], "windows": [] }
	var house: Node2D = Node2D.new()
	house.position = position
	
	var mat: int = plan.get("material", HousePart.WallMaterial.WOOD)
	var size: Vector2i = plan.get("size", Vector2i(4, 4))
	var w: int = size.x
	var h: int = size.y
	
	# Suelo
	for gx in range(w):
		for gy in range(h):
			var floor: HousePart = get_part(HousePart.PartType.FLOOR, mat)
			if floor != null:
				var node: Node2D = floor.create_instance(Vector2(gx * TILE_SIZE, gy * TILE_SIZE))
				house.add_child(node)
	
	# Paredes exteriores
	for gx in range(w):
		# Pared norte
		var wall_n: HousePart = get_part(HousePart.PartType.WALL, mat)
		if wall_n != null:
			var node_n: Node2D = wall_n.create_instance(Vector2(gx * TILE_SIZE, 0), -PI/2)
			house.add_child(node_n)
		# Pared sur
		var wall_s: HousePart = get_part(HousePart.PartType.WALL, mat)
		if wall_s != null:
			var node_s: Node2D = wall_s.create_instance(Vector2(gx * TILE_SIZE, (h-1) * TILE_SIZE), PI/2)
			house.add_child(node_s)
	
	for gy in range(h):
		# Pared oeste
		var wall_w: HousePart = get_part(HousePart.PartType.WALL, mat)
		if wall_w != null:
			var node_w: Node2D = wall_w.create_instance(Vector2(0, gy * TILE_SIZE), 0)
			house.add_child(node_w)
		# Pared este
		var wall_e: HousePart = get_part(HousePart.PartType.WALL, mat)
		if wall_e != null:
			var node_e: Node2D = wall_e.create_instance(Vector2((w-1) * TILE_SIZE, gy * TILE_SIZE), 0)
			house.add_child(node_e)
	
	# Esquinas
	var corners: Array[Vector2i] = [Vector2i(0,0), Vector2i(w-1,0), Vector2i(0,h-1), Vector2i(w-1,h-1)]
	var rotations: Array[float] = [PI, PI/2, -PI/2, 0]
	for i in range(4):
		var corner: HousePart = get_part(HousePart.PartType.WALL_CORNER, mat)
		if corner != null:
			var node_c: Node2D = corner.create_instance(Vector2(corners[i].x * TILE_SIZE, corners[i].y * TILE_SIZE), rotations[i])
			house.add_child(node_c)
	
	# Puertas y ventanas según plan
	if plan.has("doors"):
		for door_pos in plan.doors:
			var door: HousePart = get_part(HousePart.PartType.WALL_DOOR, mat)
			if door != null:
				var node_d: Node2D = door.create_instance(Vector2(door_pos.x * TILE_SIZE, door_pos.y * TILE_SIZE), door_pos.z if door_pos is Vector3 else 0)
				house.add_child(node_d)
	
	if plan.has("windows"):
		for win_pos in plan.windows:
			var win: HousePart = get_part(HousePart.PartType.WALL_WINDOW, mat)
			if win != null:
				var node_w: Node2D = win.create_instance(Vector2(win_pos.x * TILE_SIZE, win_pos.y * TILE_SIZE), win_pos.z if win_pos is Vector3 else 0)
				house.add_child(node_w)
	
	# Techo
	var roof_type: int = plan.get("roof_type", HousePart.PartType.ROOF_FLAT)
	for gx in range(w):
		for gy in range(h):
			var roof: HousePart = get_part(roof_type, mat)
			if roof != null:
				var node_r: Node2D = roof.create_instance(Vector2(gx * TILE_SIZE, gy * TILE_SIZE))
				node_r.z_index = 10
				house.add_child(node_r)
	
	return house