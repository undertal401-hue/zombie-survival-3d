extends Node2D

const ZOMBIE_SCENE: PackedScene = preload("res://03_zombies/Zombie.tscn")
const NAV_INSET := 42.0

@export var zombie_count: int = 26

var bake_ms: int = 0

@onready var neighborhood: Neighborhood = $Level/Neighborhood
@onready var navigation_region: NavigationRegion2D = $NavigationRegion2D
@onready var ground: ColorRect = $Ground
@onready var player: CharacterBody2D = $Player
@onready var extraction: Area2D = $Extraction

func _ready() -> void:
	Inventory.clear()
	Inventory.add_item("medkit", 1)
	_configure_world()
	_bake_navigation()
	_spawn_zombies()

## Ajusta suelo, muros, camara, inicio y extraccion al tamano del barrio.
func _configure_world() -> void:
	var total: Vector2 = neighborhood.map_size()
	var half: Vector2 = total * 0.5

	ground.position = -half
	ground.size = total

	_configure_wall($Level/WallTop, Vector2(0.0, -half.y + 20.0), Vector2(total.x, 40.0))
	_configure_wall($Level/WallBottom, Vector2(0.0, half.y - 20.0), Vector2(total.x, 40.0))
	_configure_wall($Level/WallLeft, Vector2(-half.x + 20.0, 0.0), Vector2(40.0, total.y))
	_configure_wall($Level/WallRight, Vector2(half.x - 20.0, 0.0), Vector2(40.0, total.y))

	player.position = neighborhood.start_position()
	extraction.position = neighborhood.extraction_position()
	$Pickup1.position = neighborhood.start_position() + Vector2(90.0, -30.0)
	$Pickup2.position = neighborhood.plaza_position() + Vector2(0.0, 120.0)

	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.limit_left = int(-half.x)
		camera.limit_top = int(-half.y)
		camera.limit_right = int(half.x)
		camera.limit_bottom = int(half.y)

func _configure_wall(body: StaticBody2D, center: Vector2, wall_size: Vector2) -> void:
	body.position = center
	var collision := body.get_node("CollisionShape2D") as CollisionShape2D
	var rect := RectangleShape2D.new()
	rect.size = wall_size
	collision.shape = rect

	var visual := body.get_node("Visual") as Polygon2D
	var hx: float = wall_size.x * 0.5
	var hy: float = wall_size.y * 0.5
	visual.polygon = PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy),
	])

## Genera el navmesh del barrio. El contorno queda dentro de los muros y las
## paredes (grupo "nav_obstacles") se restan como obstaculos.
func _bake_navigation() -> void:
	var started: int = Time.get_ticks_msec()
	var navpoly: NavigationPolygon = navigation_region.navigation_polygon
	navpoly.clear()

	var half: Vector2 = neighborhood.map_size() * 0.5
	navpoly.add_outline(PackedVector2Array([
		Vector2(-half.x + NAV_INSET, -half.y + NAV_INSET),
		Vector2(half.x - NAV_INSET, -half.y + NAV_INSET),
		Vector2(half.x - NAV_INSET, half.y - NAV_INSET),
		Vector2(-half.x + NAV_INSET, half.y - NAV_INSET),
	]))

	navigation_region.bake_navigation_polygon(false)
	bake_ms = Time.get_ticks_msec() - started

func _spawn_zombies() -> void:
	var points: Array[Vector2] = neighborhood.zombie_spawn_points()
	var count: int = mini(zombie_count, points.size())
	for i in range(count):
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody2D
		zombie.name = "Zombie%d" % (i + 1)
		zombie.position = points[i]
		zombie.set("kind", 1 if i % 3 == 1 else 0)
		add_child(zombie)
