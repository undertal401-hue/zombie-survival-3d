class_name Neighborhood
extends Node2D

## Traza el barrio completo: rejilla de calles + casas colocadas de forma
## determinista. Cada casa es independiente (05_house/House.gd) y se puede
## modificar sin tocar este generador. Cambiar columns/rows/cell_size y
## llamar a build() regenera todo el barrio.

const HOUSE_SCENE: PackedScene = preload("res://05_house/House.tscn")

@export var columns: int = 5
@export var rows: int = 4
@export var cell_size: Vector2 = Vector2(480, 300)
@export var road_width: float = 110.0
@export var layout_seed: int = 1337
@export var house_min_size: Vector2 = Vector2(240, 120)
@export var house_max_size: Vector2 = Vector2(320, 150)
@export var road_color: Color = Color(0.15, 0.15, 0.16)
@export var sidewalk_color: Color = Color(0.3, 0.3, 0.3)

func _ready() -> void:
	build()

## (Re)genera calles y casas a partir de los exports actuales.
func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed

	_build_roads()
	_build_houses(rng)

func map_size() -> Vector2:
	return Vector2(cell_size.x * columns, cell_size.y * rows)

func _build_roads() -> void:
	var total: Vector2 = map_size()
	var half: Vector2 = total * 0.5
	var sidewalk_width: float = road_width + 16.0

	for c in range(1, columns):
		var x: float = -half.x + cell_size.x * c
		_add_rect(Rect2(x - sidewalk_width * 0.5, -half.y, sidewalk_width, total.y), sidewalk_color, -6)
		_add_rect(Rect2(x - road_width * 0.5, -half.y, road_width, total.y), road_color, -5)

	for r in range(1, rows):
		var y: float = -half.y + cell_size.y * r
		_add_rect(Rect2(-half.x, y - sidewalk_width * 0.5, total.x, sidewalk_width), sidewalk_color, -6)
		_add_rect(Rect2(-half.x, y - road_width * 0.5, total.x, road_width), road_color, -5)

func _build_houses(rng: RandomNumberGenerator) -> void:
	var total: Vector2 = map_size()
	var half: Vector2 = total * 0.5

	for r in range(rows):
		for c in range(columns):
			var house := HOUSE_SCENE.instantiate() as House
			house.name = "House_r%dc%d" % [r, c]
			house.position = Vector2(
				-half.x + cell_size.x * (c + 0.5),
				-half.y + cell_size.y * (r + 0.5)
			)
			house.size = Vector2(
				rng.randf_range(house_min_size.x, house_max_size.x),
				rng.randf_range(house_min_size.y, house_max_size.y)
			).round()
			# Las casas miran a la calle horizontal mas cercana: las dos
			# filas de arriba hacia abajo, las dos de abajo hacia arriba.
			house.door_side = House.DoorSide.BOTTOM if r < rows / 2 else House.DoorSide.TOP
			house.wall_color = Color(0.55, 0.52, 0.45).lerp(Color(0.45, 0.4, 0.35), rng.randf())
			house.floor_color = Color(0.24, 0.22, 0.2).lerp(Color(0.3, 0.26, 0.22), rng.randf())
			add_child(house)

func _add_rect(rect: Rect2, color: Color, z: int) -> void:
	var visual := ColorRect.new()
	visual.position = rect.position
	visual.size = rect.size
	visual.color = color
	visual.z_index = z
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(visual)
