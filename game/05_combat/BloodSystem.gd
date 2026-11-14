class_name BloodSystem


extends Node3D
## Sistema de sangre PEGI 16: decals en suelo + particulas, sin gore extremo.
##
## Usa un pool de decals y un MultiMesh para manchas persistentes en el
## suelo. Todas las peticiones llegan por EventBus y se atenuan por distancia.
## Accesible globalmente via `BloodSystem` (class_name).

const MAX_DECALS: int = 256
const MAX_PARTICLES: int = 64
const BLOOD_LIFETIME: float = 12.0
const DESPAWN_DISTANCE: float = 60.0

var _decals: Array[Node3D] = []
var _decal_index: int = 0
var _particle_pool: ObjectPool
var _multimesh: MultiMeshInstance3D
var _multimesh_index: int = 0
var _camera: Camera3D = null


func _ready() -> void:
	_build_multimesh()
	_build_particle_pool()
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.hit_registered.connect(_on_hit_registered)


## Construye el MultiMesh de manchas de sangre en suelo.
func _build_multimesh() -> void:
	_multimesh = MultiMeshInstance3D.new()
	_multimesh.name = "BloodMultiMesh"
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(0.9, 0.9)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.02, 0.02, 0.85)
	mat.roughness = 0.85
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mesh.material = mat
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = MAX_DECALS
	_multimesh.multimesh = mm
	add_child(_multimesh)


## Pool de particulas de sangre (GPUParticles3D).
func _build_particle_pool() -> void:
	var scene: PackedScene = load("res://10_effects/BloodParticles.tscn") as PackedScene
	if scene == null:
		return
	_particle_pool = ObjectPool.new()
	_particle_pool.setup(scene, self, &"blood_particles", MAX_PARTICLES, 8)


## Registra un impacto y genera sangre acorde a la cantidad.
func _on_hit_registered(info: DamageInfo) -> void:
	if info == null or info.amount <= 0.0:
		return
	var intensity: float = clampf(info.amount / 40.0, 0.2, 1.5)
	spawn_blood(info.hit_point, info.hit_normal, intensity)
	if info.is_headshot:
		spawn_blood(info.hit_point, info.hit_normal, intensity * 1.4)


func _on_damage_dealt(info: DamageInfo) -> void:
	if info == null:
		return
	# El decal de suelo se genera bajo el punto de impacto.
	var ground: Vector3 = Vector3(info.hit_point.x, 0.02, info.hit_point.z)
	spawn_ground_decal(ground, clampf(info.amount / 30.0, 0.3, 1.2))


## Genera una mancha persistente en el suelo (MultiMesh).
## @param position: posicion mundial (suelo).
## @param scale_factor: tamano relativo.
func spawn_ground_decal(position: Vector3, scale_factor: float) -> void:
	if _multimesh == null:
		return
	var mm: MultiMesh = _multimesh.multimesh
	var t: Transform3D = Transform3D(Basis(Vector3.UP, randf() * TAU)
		.scaled(Vector3.ONE * scale_factor), position)
	mm.set_instance_transform(_multimesh_index, t)
	_multimesh_index = (_multimesh_index + 1) % MAX_DECALS


## Genera particulas de sangre en el punto de impacto.
## @param point: punto de impacto.
## @param normal: normal de superficie.
## @param intensity: 0.2..1.5.
func spawn_blood(point: Vector3, normal: Vector3, intensity: float) -> void:
	if _particle_pool == null:
		return
	var fx: Node3D = _particle_pool.acquire()
	if fx == null:
		return
	fx.global_position = point
	fx.look_at(point + normal)
	if fx.has_method("emit_burst"):
		fx.emit_burst(intensity)


## Limpia decals y particulas (cambio de oleada/escena).
func clear_blood() -> void:
	if _multimesh != null:
		var mm: MultiMesh = _multimesh.multimesh
		var zero_scale := Basis().scaled(Vector3.ZERO)
		for i: int in MAX_DECALS:
			mm.set_instance_transform(i, Transform3D(zero_scale, Vector3.ZERO))
	if _particle_pool != null:
		_particle_pool.release_all()
