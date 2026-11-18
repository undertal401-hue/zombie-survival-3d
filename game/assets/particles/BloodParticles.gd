extends GPUParticles2D
class_name BloodParticles

## Blood particle effect - se instancia en posición de impacto

func _ready() -> void:
	emitting = false
	one_shot = true

func emit_at(position: Vector2, direction: Vector2 = Vector2.ZERO, count: int = 20) -> void:
	global_position = position
	if direction != Vector2.ZERO:
		rotation = direction.angle()
	amount = count
	emitting = true

func emit_burst(position: Vector2, direction: Vector2, count: int = 10) -> void:
	emit_at(position, direction, count)

func emit_wall_splash(position: Vector2, normal: Vector2, count: int = 15) -> void:
	global_position = position
	rotation = normal.angle() - PI/2
	amount = count
	emitting = true