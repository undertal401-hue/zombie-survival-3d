extends GPUParticles2D
class_name ImpactParticles

## Impact particles - chispas, polvo, esquirlas según superficie
## Configuración base en .tscn, solo emitir

enum SurfaceType { METAL, CONCRETE, WOOD, FLESH, DIRT }

func _ready() -> void:
	emitting = false
	one_shot = true

func emit_at(position: Vector2, direction: Vector2 = Vector2.ZERO, surface: int = SurfaceType.CONCRETE) -> void:
	global_position = position
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	# Solo ajustar color según superficie (usando modulate en GPUParticles2D)
	match surface:
		SurfaceType.METAL:
			modulate = Color(1, 0.9, 0.7, 1)
		SurfaceType.CONCRETE:
			modulate = Color(0.8, 0.7, 0.5, 1)
		SurfaceType.WOOD:
			modulate = Color(0.6, 0.4, 0.2, 1)
		SurfaceType.FLESH:
			modulate = Color(0.7, 0.1, 0.1, 1)
		SurfaceType.DIRT:
			modulate = Color(0.4, 0.3, 0.2, 1)
	emitting = true

func emit_metal(position: Vector2, direction: Vector2) -> void:
	emit_at(position, direction, SurfaceType.METAL)

func emit_concrete(position: Vector2, direction: Vector2) -> void:
	emit_at(position, direction, SurfaceType.CONCRETE)

func emit_wood(position: Vector2, direction: Vector2) -> void:
	emit_at(position, direction, SurfaceType.WOOD)

func emit_flesh(position: Vector2, direction: Vector2) -> void:
	emit_at(position, direction, SurfaceType.FLESH)

func emit_dirt(position: Vector2, direction: Vector2) -> void:
	emit_at(position, direction, SurfaceType.DIRT)