class_name RoomLayout

extends Resource
## Layout de la casa (data-driven).
## Accesible globalmente via `RoomLayout` (class_name).

@export var room_count: int = 6
@export var corridor_count: int = 10
@export var room_sizes: Array[Vector2i] = [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 4)]
@export var min_room_distance: float = 1.0


## Layout por defecto si no hay recurso.
static func default_layout() -> RoomLayout:
	var layout := RoomLayout.new()
	return layout
