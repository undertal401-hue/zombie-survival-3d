extends Node

## =============================================================================
## PARTICLE MANAGER - Pool de partículas para evitar instanciar/destruir constantemente
## =============================================================================

static var instance: ParticleManager

var _blood_pool: Array[GPUParticles2D] = []
var _impact_pool: Array[GPUParticles2D] = []
var _muzzle_pool: Array[GPUParticles2D] = []

var _blood_scene: PackedScene = preload("res://assets/particles/BloodParticles.tscn")
var _impact_scene: PackedScene = preload("res://assets/particles/ImpactParticles.tscn")
var _muzzle_scene: PackedScene = preload("res://assets/particles/MuzzleFlashParticles.tscn")

const POOL_SIZE: int = 30
var _pools_initialized: bool = false
var _reuse_index: int = 0

func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Inicializar pools de forma diferida para evitar errores de "busy setting up children"
	call_deferred("_initialize_pools")

func _initialize_pools() -> void:
	# Guard temprano: _ready() agenda esta función con call_deferred(), pero un
	# _get_*() puede ejecutarse antes de que el deferred se procese. Sin este
	# guard se crearían dos veces los pools (90 partículas extra por vez).
	if _pools_initialized:
		return
	_pools_initialized = true
	for i in range(POOL_SIZE):
		_blood_pool.push_back(_create_blood())
		_impact_pool.push_back(_create_impact())
		_muzzle_pool.push_back(_create_muzzle())

func _create_blood() -> GPUParticles2D:
	var p: GPUParticles2D = _blood_scene.instantiate()
	get_tree().root.add_child(p)
	p.emitting = false
	return p

func _create_impact() -> GPUParticles2D:
	var p: GPUParticles2D = _impact_scene.instantiate()
	get_tree().root.add_child(p)
	p.emitting = false
	return p

func _create_muzzle() -> GPUParticles2D:
	var p: GPUParticles2D = _muzzle_scene.instantiate()
	get_tree().root.add_child(p)
	p.emitting = false
	return p

## Busca un emisor libre; si todos están ocupados reutiliza uno en round-robin
## en vez de instanciar otro. Sin este límite, un combate intenso (o varias
## partidas, ya que este nodo es autoload) acumula GPUParticles2D bajo root
## sin liberarlos nunca.
func _take_emitter(pool: Array[GPUParticles2D]) -> GPUParticles2D:
	if not _pools_initialized:
		_initialize_pools()
	for p in pool:
		if not p.emitting:
			return p
	if pool.is_empty():
		return null
	var reused: GPUParticles2D = pool[_reuse_index % pool.size()]
	_reuse_index += 1
	return reused

func _get_blood() -> GPUParticles2D:
	return _take_emitter(_blood_pool)

func _get_impact() -> GPUParticles2D:
	return _take_emitter(_impact_pool)

func _get_muzzle() -> GPUParticles2D:
	return _take_emitter(_muzzle_pool)

## API Pública

func spawn_blood(position: Vector2, direction: Vector2 = Vector2.ZERO, count: int = 20) -> void:
	var p: GPUParticles2D = _get_blood()
	p.global_position = position
	if direction != Vector2.ZERO:
		p.rotation = direction.angle()
	p.amount = count
	p.emitting = true

func spawn_blood_burst(position: Vector2, direction: Vector2, count: int = 10) -> void:
	spawn_blood(position, direction, count)

func spawn_wall_blood(position: Vector2, normal: Vector2, count: int = 15) -> void:
	var p: GPUParticles2D = _get_blood()
	p.global_position = position
	p.rotation = normal.angle() - PI/2
	p.amount = count
	p.emitting = true

func spawn_impact(position: Vector2, direction: Vector2, surface: int = 1) -> void:
	var p: GPUParticles2D = _get_impact()
	p.global_position = position
	if direction != Vector2.ZERO:
		p.rotation = direction.angle()
	p.emit_at(position, direction, surface)

func spawn_impact_metal(position: Vector2, direction: Vector2) -> void:
	spawn_impact(position, direction, ImpactParticles.SurfaceType.METAL)

func spawn_impact_concrete(position: Vector2, direction: Vector2) -> void:
	spawn_impact(position, direction, ImpactParticles.SurfaceType.CONCRETE)

func spawn_impact_wood(position: Vector2, direction: Vector2) -> void:
	spawn_impact(position, direction, ImpactParticles.SurfaceType.WOOD)

func spawn_impact_flesh(position: Vector2, direction: Vector2) -> void:
	spawn_impact(position, direction, ImpactParticles.SurfaceType.FLESH)

func spawn_impact_dirt(position: Vector2, direction: Vector2) -> void:
	spawn_impact(position, direction, ImpactParticles.SurfaceType.DIRT)

func spawn_muzzle_flash(position: Vector2, direction: Vector2, weapon_type: int = 0) -> void:
	var p: GPUParticles2D = _get_muzzle()
	p.global_position = position
	p.rotation = direction.angle()
	p.emit_at(position, direction, weapon_type)
