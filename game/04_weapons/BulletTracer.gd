class_name BulletTracer


extends Node3D
## Pool de estelas de bala (líneas estiradas).
##
## Reutiliza MeshInstance3D con un BoxMesh fino. Las estelas duran ~60 ms.
## Accesible globalmente via `BulletTracer` (class_name).

const MAX_TRACERS: int = 64
const TRACER_LIFE: float = 0.06
const TRACER_THICKNESS: float = 0.012

var _pool: Array[MeshInstance3D] = []
var _cursor: int = 0
var _active: Array[Dictionary] = []


func _ready() -> void:
	_build_pool()


func _build_pool() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(TRACER_THICKNESS, TRACER_THICKNESS, 1.0)
	for i: int in MAX_TRACERS:
		var tracer := MeshInstance3D.new()
		tracer.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.9, 0.55, 0.75)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tracer.material_override = mat
		tracer.visible = false
		add_child(tracer)
		_pool.append(tracer)


## Crea una estela entre dos puntos.
## @param from: origen.
## @param to: destino.
func spawn(from: Vector3, to: Vector3) -> void:
	var tracer: MeshInstance3D = _pool[_cursor]
	_cursor = (_cursor + 1) % MAX_TRACERS
	var mid: Vector3 = (from + to) * 0.5
	var length: float = from.distance_to(to)
	tracer.global_position = mid
	tracer.look_at(to)
	tracer.scale = Vector3.ONE
	tracer.scale.z = maxf(length, 0.01)
	tracer.visible = true
	_active.append({"node": tracer, "age": 0.0})


func _process(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for entry: Dictionary in _active:
		var node: MeshInstance3D = entry["node"]
		var age: float = float(entry["age"]) + delta
		if age >= TRACER_LIFE:
			node.visible = false
			continue
		entry["age"] = age
		keep.append(entry)
	_active = keep
