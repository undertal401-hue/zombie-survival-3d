extends GPUParticles2D
class_name MuzzleFlashParticles

## Muzzle flash particles - destello al disparar

enum WeaponType { PISTOL, SHOTGUN, RIFLE, HEAVY }

func _ready() -> void:
	emitting = false
	one_shot = true

func emit_at(position: Vector2, direction: Vector2, weapon_type: int = WeaponType.PISTOL) -> void:
	global_position = position
	rotation = direction.angle()
	# Solo ajustar cantidad y lifetime según arma
	match weapon_type:
		WeaponType.PISTOL:
			amount = 6
			lifetime = 0.06
		WeaponType.SHOTGUN:
			amount = 12
			lifetime = 0.1
		WeaponType.RIFLE:
			amount = 8
			lifetime = 0.05
		WeaponType.HEAVY:
			amount = 15
			lifetime = 0.12
	emitting = true
	# NO auto-free - el pool maneja el ciclo de vida
	# Usar one_shot para que se detenga solo