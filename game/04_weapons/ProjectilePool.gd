class_name ProjectilePool


extends Node
## Pool de proyectiles (balas, granadas, rayos).
##
## Cambia de escena segun el arma; mantiene un ObjectPool por escena.
## Accesible globalmente via `ProjectilePool` (class_name).

const POOL_INITIAL: int = 24
const POOL_GROWTH: int = 8

var _pools: Dictionary = {}
var _current_scene: PackedScene = null


## Precarga la escena de proyectil de un arma.
## @param scene_path: ruta de la escena.
func ensure_initialized(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		return
	_current_scene = scene
	if not _pools.has(scene_path):
		var pool := ObjectPool.new()
		pool.setup(scene, self, scene_path, POOL_INITIAL, POOL_GROWTH)
		_pools[scene_path] = pool


## Adquiere un proyectil de la escena actual.
## @return Projectile o null.
func acquire() -> Projectile:
	if _current_scene == null:
		return null
	var pool: ObjectPool = _pools.get(_current_scene.resource_path) as ObjectPool
	if pool == null:
		return null
	return pool.acquire() as Projectile


## Recicla un proyectil.
## @param projectile: proyectil a reciclar.
func release(projectile: Projectile) -> void:
	if projectile == null:
		return
	var pool: ObjectPool = _pools.get(_current_scene.resource_path) as ObjectPool if _current_scene != null else null
	if pool != null:
		pool.release(projectile)
	else:
		projectile.queue_free()


## Estadisticas de pools.
func usage_report() -> Dictionary:
	var report := {}
	for path: String in _pools:
		var pool: ObjectPool = _pools[path]
		report[path] = {"total": pool.total_size(), "active": pool.active_count()}
	return report
