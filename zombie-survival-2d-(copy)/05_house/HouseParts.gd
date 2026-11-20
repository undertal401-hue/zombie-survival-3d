extends Resource
class_name HousePart

## =============================================================================
## HOUSE PARTS - Sistema modular de partes de casa
## =============================================================================

enum PartType {
	WALL,           # Pared recta
	WALL_CORNER,    # Esquina
	WALL_WINDOW,    # Pared con ventana
	WALL_DOOR,      # Pared con puerta
	FLOOR,          # Suelo interior
	ROOF_FLAT,      # Techo plano
	ROOF_SLOPE,     # Techo inclinado
	ROOF_CORNER,    # Esquina techo
	FRAME,          # Marco estructura
	DEBRIS          # Escombros/mobiliario
}

enum WallMaterial {
	WOOD,       # Madera
	BRICK,      # Ladrillo
	CONCRETE,   # Concreto
	METAL,      # Metal/chapa
	PLASTER     # Yeso/estuco
}

@export var part_type: PartType = PartType.WALL
@export var material: WallMaterial = WallMaterial.WOOD
@export var texture: Texture2D
@export var size: Vector2i = Vector2i(64, 64)
@export var collision_shape: PackedScene
@export var occluder_polygon: PackedVector2Array
@export var variants: Array[Texture2D] = []  # Variaciones visuales
@export var health: float = 100.0
@export var destructible: bool = true
@export var loot_spawn_points: Array[Vector2] = []

func _init() -> void:
	pass

func get_random_variant() -> Texture2D:
	if variants.size() > 0:
		return variants[randi() % variants.size()]
	return texture

func create_instance(position: Vector2, rotation: float = 0.0) -> Node2D:
	var node: Node2D = Node2D.new()
	node.position = position
	node.rotation = rotation
	
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = get_random_variant()
	sprite.offset = size * 0.5
	node.add_child(sprite)
	
	if collision_shape != null:
		var col: CollisionShape2D = collision_shape.instantiate()
		node.add_child(col)
	
	if occluder_polygon.size() > 0:
		var occ: LightOccluder2D = LightOccluder2D.new()
		var occ_poly: OccluderPolygon2D = OccluderPolygon2D.new()
		occ_poly.polygon = occluder_polygon
		occ.occluder = occ_poly
		node.add_child(occ)
	
	return node