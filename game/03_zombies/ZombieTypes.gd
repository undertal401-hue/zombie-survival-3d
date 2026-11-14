class_name ZombieTypes

extends RefCounted
## Registro y fabrica de tipos de zombie.
##
## Mapea `ZombieKind` / `type_name` a escena y stats base. El spawner usa esta
## unica via, evitando if/else de tipos por todo el codigo.
## Accesible globalmente via `ZombieTypes` (class_name).

const SCENE_DIR: String = "res://03_zombies/"

var _scenes: Dictionary = {}
var _stats: Dictionary = {}


func _init() -> void:
	var table: Dictionary = ZombieStats.base_table()
	for kind: ZombieStats.ZombieKind in table:
		var stats: ZombieStats = table[kind]
		_stats[stats.type_name] = stats
		_scenes[stats.type_name] = SCENE_DIR + ("%s.tscn" % stats.type_name)


## Registra una escena para un tipo.
## @param type_name: nombre del tipo.
## @param scene_path: ruta de la escena.
func register_scene(type_name: StringName, scene_path: String) -> void:
	_scenes[type_name] = scene_path


## Escena de un tipo.
## @return PackedScene o null.
func get_scene(type_name: StringName) -> PackedScene:
	var path: String = _scenes.get(type_name, "") as String
	if path.is_empty():
		path = SCENE_DIR + "WalkerZombie.tscn"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


## Stats base de un tipo.
func get_stats(type_name: StringName) -> ZombieStats:
	if _stats.has(type_name):
		return _stats[type_name] as ZombieStats
	return ZombieStats.new()


## Todos los nombres de tipo disponibles.
func available_types() -> Array[StringName]:
	return _stats.keys()


## Fabrica una instancia de zombie con stats escaladas.
## @param type_name: tipo.
## @param hp_mult: multiplicador de vida.
## @param dmg_mult: multiplicador de dano.
## @param speed_mult: multiplicador de velocidad.
## @return BaseZombie o null.
func create(type_name: StringName, hp_mult: float = 1.0, dmg_mult: float = 1.0,
		speed_mult: float = 1.0) -> BaseZombie:
	var scene: PackedScene = get_scene(type_name)
	if scene == null:
		return null
	var zombie: BaseZombie = scene.instantiate() as BaseZombie
	if zombie == null:
		return null
	var base: ZombieStats = get_stats(type_name)
	zombie.stats = base.scaled(hp_mult, dmg_mult, speed_mult) if base != null else ZombieStats.new()
	return zombie
