class_name BloodParticles

extends GPUParticles3D
## Particulas de sangre para impactos.
## Accesible globalmente via `BloodParticles` (class_name).

func emit_burst(intensity: float) -> void:
	emitting = true
	amount = int(20 * intensity)
	# La emission es one_shot, se detendra sola
