extends Node2D

@onready var neighborhood: Neighborhood = $Level/Neighborhood
@onready var navigation_region: NavigationRegion2D = $NavigationRegion2D

func _ready() -> void:
	Inventory.add_item("llave", 1)
	Inventory.add_item("medkit", 1)
	_bake_navigation()

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
