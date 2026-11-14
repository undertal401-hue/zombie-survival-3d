class_name ZombiePool


extends RefCounted
## Pools de zombies por tipo.
##
## Mantiene un ObjectPool por cada tipo para no mezclar escenas. El tamano
## inicial es pequeno; el pool crece solo si hace falta (evita picos de FPS).
## Accesible globalmente via `ZombiePool` (class_name).

const INITIAL_PER_TYPE: int = 12
const GROWTH_STEP: int = 6

var _pools: Dictionary = {}
var _parent: Node
var _types: ZombieTypes


## Crea el gestor de pools.
## @param parent: nodo donde se cuelgan las instancias.
## @param types: registro de tipos de zombie.
func setup(parent: Node, types: ZombieTypes) -> void:
	_parent = parent
	_types = types


## Adquiere un zombie de un tipo, reutilizando instancia si existe.
## @param type_name: tipo de zombie.
## @param hp_mult: multiplicador de vida.
## @param dmg_mult: multiplicador de dano.
## @param speed_mult: multiplicador de velocidad.
## @return BaseZombie listo o null.
func acquire(type_name: StringName, hp_mult: float, dmg_mult: float, speed_mult: float) -> BaseZombie:
	var pool: ObjectPool = _get_pool(type_name)
	if pool == null:
		return null
	var node: Node = pool.acquire()
	if node == null:
		return null
	var zombie := node as BaseZombie
	if zombie == null:
		pool.release(node)
		return null
	zombie.stats = _types.get_stats(type_name).scaled(hp_mult, dmg_mult, speed_mult)
	return zombie


## Recicla un zombie en su pool correspondiente.
## @param zombie: zombie a reciclar.
func release(zombie: BaseZombie) -> void:
	if zombie == null:
		return
	var pool: ObjectPool = _pools.get(zombie.zombie_type()) as ObjectPool
	if pool != null:
		pool.release(zombie)
	else:
		zombie.queue_free()


## Obtiene (o crea) el pool de un tipo.
func _get_pool(type_name: StringName) -> ObjectPool:
	if _pools.has(type_name):
		return _pools[type_name] as ObjectPool
	var scene: PackedScene = _types.get_scene(type_name)
	if scene == null:
		return null
	var pool := ObjectPool.new()
	pool.setup(scene, _parent, type_name, INITIAL_PER_TYPE, GROWTH_STEP)
	_pools[type_name] = pool
	return pool


## Estadisticas de uso de los pools (telemetria/DEBUG).
func usage_report() -> Dictionary:
	var report := {}
	for type_name: StringName in _pools:
		var pool: ObjectPool = _pools[type_name]
		report[type_name] = {
			"total": pool.total_size(),
			"active": pool.active_count(),
			"available": pool.available_count(),
		}
	return report


## Libera todos los pools (cambio de escena).
func dispose() -> void:
	for type_name: StringName in _pools:
		(_pools[type_name] as ObjectPool).dispose()
	_pools.clear()
