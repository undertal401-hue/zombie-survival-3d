class_name Gizmos


extends Node3D
## Gizmos de debug: cajas de colision, raycasts, areas, spawn points.
##
## Solo visible en editor o con debug_gizmos activado. El dibujo se hace
## sobre un ImmediateMesh reconstruido cada frame (sin dependencias externas).
## Accesible globalmente via `Gizmos` (class_name).

const LINES_PER_CIRCLE: int = 24

@export var show_spawn_points: bool = true
@export var show_attack_ranges: bool = true
@export var show_vision_cones: bool = true
@export var show_hurtboxes: bool = true
@export var show_navmesh: bool = false

var _debug_draw: GizmosDebugDraw = null


func _ready() -> void:
	_debug_draw = GizmosDebugDraw.new()
	add_child(_debug_draw)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() and not OS.has_feature("debug_gizmos"):
		return
	_debug_draw.clear()
	_draw_spawn_points()
	_draw_attack_ranges()
	_draw_vision_cones()
	_draw_hurtboxes()


func _draw_spawn_points() -> void:
	if not show_spawn_points:
		return
	for node: Node in get_tree().get_nodes_in_group("spawn_points"):
		if node is Node3D:
			_debug_draw.draw_sphere(node.global_position, 0.5, Color(1.0, 0.0, 1.0, 0.5))
			_debug_draw.draw_line(node.global_position, node.global_position + Vector3.UP * 2.0, Color(1.0, 0.0, 1.0))


func _draw_attack_ranges() -> void:
	if not show_attack_ranges:
		return
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as BaseZombie
		if zombie != null and zombie.stats != null:
			_debug_draw.draw_circle(zombie.global_position, zombie.stats.attack_range, Color(1.0, 0.0, 0.0, 0.3), Vector3.UP, LINES_PER_CIRCLE)


func _draw_vision_cones() -> void:
	if not show_vision_cones:
		return
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as BaseZombie
		if zombie != null and zombie.senses != null:
			var senses: ZombieSenses = zombie.senses
			var forward: Vector3 = -zombie.global_transform.basis.z
			var center: Vector3 = zombie.global_position + forward * senses.VISION_RANGE * 0.5
			_debug_draw.draw_cone(zombie.global_position, forward, senses.VISION_RANGE, deg_to_rad(senses.VISION_HALF_ANGLE_DEG), Color(1.0, 1.0, 0.0, 0.2))


func _draw_hurtboxes() -> void:
	if not show_hurtboxes:
		return
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as BaseZombie
		if zombie != null:
			if zombie.hurtbox != null:
				_debug_draw.draw_sphere(zombie.hurtbox.global_position, 0.5, Color(0.0, 1.0, 0.0, 0.4))
			if zombie.head_hurtbox != null:
				_debug_draw.draw_sphere(zombie.head_hurtbox.global_position, 0.3, Color(1.0, 0.0, 1.0, 0.5))


## Mini debug-draw interno: lineas, circulos, esferas y conos con ImmediateMesh.
class GizmosDebugDraw extends Node3D:
	var _mesh_instance: MeshInstance3D = null
	var _mesh: ImmediateMesh = null


	func _ready() -> void:
		_mesh = ImmediateMesh.new()
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.mesh = _mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		_mesh_instance.material_override = mat
		add_child(_mesh_instance)


	## Borra todo el contenido del frame anterior.
	func clear() -> void:
		if _mesh != null:
			_mesh.clear_surfaces()


	## Dibuja un segmento de recta.
	## @param a: origen.
	## @param b: fin.
	## @param color: color del segmento.
	func draw_line(a: Vector3, b: Vector3, color: Color) -> void:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(a)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(b)
		_mesh.surface_end()


	## Dibuja un circulo aproximado en el plano con la normal indicada.
	## @param center: centro.
	## @param radius: radio.
	## @param color: color.
	## @param normal: normal del plano.
	## @param segments: numero de segmentos.
	func draw_circle(center: Vector3, radius: float, color: Color, normal: Vector3 = Vector3.UP, segments: int = LINES_PER_CIRCLE) -> void:
		if segments < 3:
			return
		var tangent: Vector3 = (Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).cross(normal).normalized()
		var bitangent: Vector3 = normal.cross(tangent).normalized()
		_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i: int in segments + 1:
			var angle: float = TAU * i / segments
			var point: Vector3 = center + (tangent * cos(angle) + bitangent * sin(angle)) * radius
			_mesh.surface_set_color(color)
			_mesh.surface_add_vertex(point)
		_mesh.surface_end()


	## Dibuja una esfera como tres circulos ortogonales.
	## @param center: centro.
	## @param radius: radio.
	## @param color: color.
	func draw_sphere(center: Vector3, radius: float, color: Color) -> void:
		draw_circle(center, radius, color, Vector3.UP)
		draw_circle(center, radius, color, Vector3.RIGHT)
		draw_circle(center, radius, color, Vector3.FORWARD)


	## Dibuja un cono de vision desde un apex.
	## @param apex: origen del cono.
	## @param direction: eje del cono.
	## @param length: longitud.
	## @param half_angle: angulo medio en radianes.
	## @param color: color.
	func draw_cone(apex: Vector3, direction: Vector3, length: float, half_angle: float, color: Color) -> void:
		var dir: Vector3 = direction.normalized()
		var tangent: Vector3 = (Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).cross(dir).normalized()
		var bitangent: Vector3 = dir.cross(tangent).normalized()
		var base_center: Vector3 = apex + dir * length
		var base_radius: float = length * tan(half_angle)
		draw_circle(base_center, base_radius, color, dir)
		var steps: int = 8
		for i: int in steps:
			var angle: float = TAU * i / steps
			var rim: Vector3 = base_center + (tangent * cos(angle) + bitangent * sin(angle)) * base_radius
			draw_line(apex, rim, color)
