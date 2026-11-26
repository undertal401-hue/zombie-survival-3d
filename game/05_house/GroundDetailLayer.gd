extends Node2D

## =============================================================================
## CAPA DE DETALLE DEL SUELO
## =============================================================================
## Reparte trozos REALES del atlas de Lumina (redondeados, con borde irregular)
## sobre la base continua que pinta GroundTileMapV2.
##
## Los trozos NO se colocan en rejilla: se agrupan en manchas cuyo centro lleva
## un desplazamiento pseudoaleatorio, de modo que los bordes se solapan y no
## aparece ni el patron de bloques ni una retícula de matas.
##
## Solo se dibuja lo que rodea a la camara (con margen) y se redibuja cuando la
## camara se desplaza lo suficiente: coste constante en un mundo de 12600x12600.
## =============================================================================

## Tamano de las manchas de detalle.
const CLUSTER: float = 150.0
## Trozos por mancha (minimo y maximo).
const CLUSTER_MIN: int = 3
const CLUSTER_MAX: int = 7
## Desplazamiento maximo del centro de cada mancha, en fraccion de CLUSTER.
const CLUSTER_JITTER: float = 0.6
## Probabilidad de colocar trozo por material. El pasto lleva matas sueltas;
## la losa urbana, alguna piedra; el bosque, hojarasca.
const DENSITY: Array[float] = [0.30, 0.34, 0.30, 0.30, 0.22, 0.28, 0.40]
const DEFAULT_DENSITY: float = 1.0
## Margen extra alrededor de la vista para que no aparezcan trozos al borde.
const MARGIN: float = 320.0
## Desplazamiento de cámara que fuerza un redibujado.
const REDRAW_STEP: float = 48.0

## Nodo GroundTileMapV2 del que se toman materiales y regiones del atlas.
var ground: Node = null

var _last_center: Vector2 = Vector2(1e12, 1e12)
var _last_zoom: Vector2 = Vector2(-1, -1)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# El padre (GroundTileMapV2) está en z=-8; con z relativo 1 queda en -7.
	z_index = 1
	set_process(true)


func _process(_delta: float) -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	var center: Vector2 = camera.get_screen_center_position()
	var zoom: Vector2 = camera.zoom
	if center.distance_to(_last_center) < REDRAW_STEP and zoom.is_equal_approx(_last_zoom):
		return
	_last_center = center
	_last_zoom = zoom
	queue_redraw()


func _draw() -> void:
	if ground == null:
		return
	var atlas: Texture2D = ground.get("atlas_texture") as Texture2D
	if atlas == null:
		return
	for item in visible_chunks(_visible_rect()):
		var region: Rect2 = item["region"]
		var position: Vector2 = item["position"]
		draw_texture_rect_region(atlas, Rect2(position - region.size * 0.5, region.size), region)


func _visible_rect() -> Rect2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return Rect2(-640.0, -360.0, 1280.0, 720.0).grow(MARGIN)
	var size: Vector2 = Vector2(get_viewport_rect().size) / camera.zoom
	return Rect2(camera.get_screen_center_position() - size * 0.5, size).grow(MARGIN)


## Trozos visibles en un rectángulo de mundo. Función pura y determinista:
## el mismo rectángulo devuelve siempre los mismos trozos.
func visible_chunks(rect: Rect2) -> Array:
	var items: Array = []
	if ground == null:
		return items
	var min_cell := Vector2i(floori(rect.position.x / CLUSTER) - 1, floori(rect.position.y / CLUSTER) - 1)
	var max_cell := Vector2i(ceili(rect.end.x / CLUSTER) + 1, ceili(rect.end.y / CLUSTER) + 1)
	for gy in range(min_cell.y, max_cell.y + 1):
		for gx in range(min_cell.x, max_cell.x + 1):
			var cluster_hash: int = _hash(gx, gy)
			var center := Vector2(
				(float(gx) + 0.5 + (float(cluster_hash % 1000) / 1000.0 - 0.5) * CLUSTER_JITTER) * CLUSTER,
				(float(gy) + 0.5 + (float((cluster_hash >> 10) % 1000) / 1000.0 - 0.5) * CLUSTER_JITTER) * CLUSTER)
			var count: int = CLUSTER_MIN + cluster_hash % (CLUSTER_MAX - CLUSTER_MIN + 1)
			for index in range(count):
				var h: int = _hash(gx * 131 + index * 17, gy * 197 + index * 29)
				var angle: float = float(h % 628) / 100.0
				var radius: float = sqrt(float((h >> 10) % 1000) / 1000.0) * CLUSTER * 0.45
				var position := center + Vector2(cos(angle) * radius, sin(angle) * radius)
				if not rect.has_point(position):
					continue
				var material: int = int(ground.call("material_at_world", position))
				var regions: Array = ground.call("chunk_regions_for", material)
				if regions.is_empty():
					continue
				var density: float = DENSITY[material] if material < DENSITY.size() else DEFAULT_DENSITY
				if float((h >> 7) % 1000) / 1000.0 > density:
					continue
				var region: Rect2 = regions[(h >> 20) % regions.size()]
				items.append({"position": position, "region": region, "material": material})
	return items


func _hash(x: int, y: int) -> int:
	var h: int = (x * 374761393) ^ (y * 668265263)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF
