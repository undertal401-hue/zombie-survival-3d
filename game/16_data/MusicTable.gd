class_name MusicTable

extends Resource
## Tabla de pistas de musica.
## Accesible globalmente via `MusicTable` (class_name).

@export var tracks: Dictionary = {}

func has(key: StringName) -> bool:
	return tracks.has(key)

func get_track(key: StringName, default: Variant = null) -> Variant:
	return tracks.get(key, default)
