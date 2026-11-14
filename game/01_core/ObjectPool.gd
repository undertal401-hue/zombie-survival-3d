class_name ObjectPool

extends RefCounted
## Pool generico de nodos reutilizables.
##
## Evita allocaciones en caliente (zombies, balas, decals de sangre,
## particulas). Los objetos se marcan `set_active(false`) y se reactivan con
## `reset_state()` cuando el tipo lo soporta.
##
## Uso:
##   var pool := ObjectPool.new(preload("res://03_zombies/WalkerZombie.tscn"), self, 24, 8)
##   var node := pool.acquire()
##   pool.release(node)
## Accesible globalmente via `ObjectPool` (class_name).

signal pool_grew(new_size: int)
signal pool_depleted(pool_id: StringName)

@export var pool_id: StringName = &"pool"
@export var initial_size: int = 32
@export var growth_step: int = 8
@export var max_size: int = 4096

var _scene: PackedScene
var _parent: Node
var _available: Array[Node] = []
var _active: Array[Node] = []
var _created: int = 0


## Crea el pool. No es un Node: debe pertenecer a un sistema que lo posea.
## @param scene: escena instanciable.
## @param parent: nodo padre donde se cuelgan las instancias.
## @param p_pool_id: identificador para telemetria.
## @param p_initial: tamano inicial.
## @param p_growth: cuantos objetos se crean cuando se agota.
func setup(scene: PackedScene, parent: Node, p_pool_id: StringName = &"pool",
		p_initial: int = 32, p_growth: int = 8) -> void:
	_scene = scene
	_parent = parent
	pool_id = p_pool_id
	initial_size = p_initial
	growth_step = p_growth
	_preallocate(initial_size)


## Precarga `count` instancias inactivas.
func _preallocate(count: int) -> void:
	for i: int in count:
		var node: Node = _create_instance()
		if node == null:
			return
		_available.append(node)


func _create_instance() -> Node:
	if _scene == null or _parent == null or _created >= max_size:
		return null
	var node: Node = _scene.instantiate()
	_created += 1
	_parent.add_child(node)
	_deactivate(node)
	return node


## Desactiva un nodo de forma segura (sin depender de APIs inexistentes).
func _deactivate(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	elif node is Node3D:
		(node as Node3D).visible = false
	node.set_process(false)
	node.set_physics_process(false)
	if node is Area3D:
		(node as Area3D).set_deferred("monitoring", false)
		(node as Area3D).set_deferred("monitorable", false)
	if node.has_method("on_pool_released"):
		node.on_pool_released()


## Extrae un objeto disponible. Si no queda, el pool crece.
## @return Nodo listo para usar, o null si se alcanzo `max_size`.
func acquire() -> Node:
	if _available.is_empty():
		if _created >= max_size:
			pool_depleted.emit(pool_id)
			return null
		_preallocate(growth_step)
		pool_grew.emit(_created)
	var node: Node = _available.pop_back()
	_active.append(node)
	if node is CanvasItem:
		(node as CanvasItem).visible = true
	elif node is Node3D:
		(node as Node3D).visible = true
	node.set_process(true)
	node.set_physics_process(true)
	if node is Area3D:
		(node as Area3D).set_deferred("monitoring", true)
		(node as Area3D).set_deferred("monitorable", true)
	if node.has_method("reset_state"):
		node.reset_state()
	if node.has_method("on_pool_acquired"):
		node.on_pool_acquired()
	return node


## Recicla un objeto devolviendolo al pool.
## @param node: nodo previamente adquirido.
func release(node: Node) -> void:
	if node == null:
		return
	var idx: int = _active.find(node)
	if idx == -1:
		return
	_active.remove_at(idx)
	_deactivate(node)
	_available.append(node)


## Devuelve todos los objetos activos al pool.
func release_all() -> void:
	var snapshot: Array[Node] = _active.duplicate()
	for node: Node in snapshot:
		release(node)


## Tamano total creado.
func total_size() -> int:
	return _created


## Cantidad de objetos activos.
func active_count() -> int:
	return _active.size()


## Cantidad de objetos disponibles.
func available_count() -> int:
	return _available.size()


## Libera el pool por completo (cambio de escena).
func dispose() -> void:
	release_all()
	for node: Node in _available:
		node.queue_free()
	_available.clear()
	_created = 0
