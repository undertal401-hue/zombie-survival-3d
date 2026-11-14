class_name ImpactSystem


extends Node3D
## Sistema de impactos: chispas, polvo y decals de agujero de bala.
##
## Pool de MeshInstance3D reutilizados. Los decals se desvanecen y vuelven al
## pool. Sin gore: solo efectos de superficie.
## Accesible globalmente via `ImpactSystem` (class_name).

const MAX_IMPACT_DECALS: int = 128
const DECAL_FADE_TIME: float = 8.0

var _decal_pool: Array[MeshInstance3D] = []
var _cursor: int = 0
var _active: Array[Dictionary] = []


func _ready() -> void:
	_build_pool()
	EventBus.hit_registered.connect(_on_hit_registered)


func _build_pool() -> void:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(0.08, 0.08)
	for i: int in MAX_IMPACT_DECALS:
		var decal := MeshInstance3D.new()
		decal.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.1, 0.1, 0.9)
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		decal.material_override = mat
		decal.visible = false
		add_child(decal)
		_decal_pool.append(decal)


## Genera un impacto en una superficie.
## @param point: punto de impacto.
## @param normal: normal de la superficie.
## @param surface: "metal" | "wood" | "concrete" | "flesh".
func spawn_impact(point: Vector3, normal: Vector3, surface: StringName) -> void:
	var decal: MeshInstance3D = _decal_pool[_cursor]
	_cursor = (_cursor + 1) % MAX_IMPACT_DECALS
	decal.global_position = point + normal * 0.01
	decal.look_at(point + normal)
	decal.visible = true
	var mat := decal.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = _color_for_surface(surface)
	_active.append({"node": decal, "age": 0.0})


func _process(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for entry: Dictionary in _active:
		var node: MeshInstance3D = entry["node"]
		var age: float = float(entry["age"]) + delta
		if age >= DECAL_FADE_TIME:
			node.visible = false
			continue
		var mat := node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = clampf(1.0 - age / DECAL_FADE_TIME, 0.0, 1.0)
		entry["age"] = age
		keep.append(entry)
	_active = keep


func _color_for_surface(surface: StringName) -> Color:
	match surface:
		&"metal":
			return Color(0.7, 0.72, 0.75, 0.9)
		&"wood":
			return Color(0.35, 0.22, 0.12, 0.9)
		&"flesh":
			return Color(0.45, 0.08, 0.08, 0.9)
	return Color(0.15, 0.15, 0.15, 0.9)


func _on_hit_registered(info: DamageInfo) -> void:
	if info == null:
		return
	var surface: StringName = &"concrete"
	if info.damage_type == DamageInfo.DamageType.MELEE:
		surface = &"flesh"
	spawn_impact(info.hit_point, info.hit_normal, surface)
