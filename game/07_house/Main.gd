extends Node2D

const ZOMBIE_SCENE: PackedScene = preload("res://03_zombies/Zombie.tscn")
const ZOMBIE_SPAWNS := [
	[Vector2(-240, -300), 0],
	[Vector2(240, -300), 0],
	[Vector2(720, 0), 1],
	[Vector2(-720, 300), 0],
	[Vector2(0, 300), 1],
	[Vector2(480, -300), 0],
	[Vector2(-480, 300), 0],
	[Vector2(960, 300), 1],
	[Vector2(720, 150), 0],
	[Vector2(-240, 0), 1],
]

@onready var neighborhood: Neighborhood = $Level/Neighborhood
@onready var navigation_region: NavigationRegion2D = $NavigationRegion2D

func _ready() -> void:
	Inventory.clear()
	Inventory.add_item("medkit", 1)
	_bake_navigation()
	_spawn_zombies()

## Genera el navmesh del barrio. El contorno caminable es el mapa completo;
## las paredes (grupo "nav_obstacles") se restan como obstaculos.
func _bake_navigation() -> void:
	var navpoly: NavigationPolygon = navigation_region.navigation_polygon
	navpoly.clear()

	var half: Vector2 = neighborhood.map_size() * 0.5
	navpoly.add_outline(PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	]))

	navigation_region.bake_navigation_polygon(false)

func _spawn_zombies() -> void:
	for i in range(ZOMBIE_SPAWNS.size()):
		var spawn: Array = ZOMBIE_SPAWNS[i]
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody2D
		zombie.name = "Zombie%d" % (i + 1)
		zombie.position = spawn[0]
		zombie.set("kind", spawn[1])
		add_child(zombie)
