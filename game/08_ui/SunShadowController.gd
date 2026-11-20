extends Node2D
class_name SunShadowController

## ============================================================================
## SOMBRAS SOLARES ACOTADAS (R3 / ADR-006)
## ============================================================================
## POR QUE EXISTE ESTE NODO
## -------------------------
## La sombra de una `DirectionalLight2D` en Godot 4 NO TIENE LARGO. En el
## motor (`servers/rendering/renderer_rd/renderer_canvas_render_rd.cpp`,
## `light_update_directional_shadow()`) el `z_far` del atlas de sombra es
## `to_edge_distance * 2.0 + cull_distance` y un fragmento queda en sombra si
## su profundidad supera la del oclusor: la sombra se prolonga hasta el BORDE
## DE LA PANTALLA en la direccion opuesta a la luz.
##
## `DirectionalLight2D.max_distance` NO acorta la sombra: solo (a) amplia el
## rectangulo de oclusores considerados y (b) suma al `z_far`. Y
## `Light2D.shadow_max_distance` NO EXISTE en Godot 4 (comprobado con
## `ClassDB.class_get_property_list("Light2D")` en 4.7.2): el limite de 800 px
## que se leia en `SolarLighting.tscn` era una CONCEPCION ERRONEA.
##
## CONCLUSION: la unica forma de ACOTAR la sombra diurna en 2D cenital es no
## usar la sombra direccional y dibujar una MANCHA (blob) por emisor de
## sombra, con longitud maxima constante. Es el patron estandar de los juegos
## 2D cenitales y es lo que el usuario pidio ("acotar las sombras: hoy llegan
## hasta el borde de pantalla").
##
## LO QUE NO SE TOCA
## ------------------
## El faro nocturno (`PointLight2D` del jugador, `Player.tscn`) conserva sus
## sombras REALES del motor: las acota la textura del cono y el usuario las
## valora expresamente. Este controlador dibuja SOLO las sombras DIURNAS.
##
## INVARIANTES (exigibles por `game/10_review/SunShadowTest.gd`)
## ------------------------------------------------------------------
##   1. Cada `LightOccluder2D` vivo tiene como maximo UNA mancha.
##   2. La mancha mide como maximo `MAX_SHADOW_LENGTH` px en su eje largo:
##      nunca llega al borde de la pantalla (1280x720).
##   3. La mancha NO recibe luz (`light_mask = 0`): es una mancha de
##      oscuridad, no una superficie iluminada.
##   4. De noche la mancha es INVISIBLE (alpha 0) y el sol no aporta energia.
##   5. La mancha se desplaza en la direccion OPUESTA a la luz y se alarga
##      en esa misma direccion.
## ============================================================================

## Mascara de la mancha (generada de forma determinista por
## `tools/gen_art.py --check`).
const BLOB_TEXTURE: String = "res://assets/art/shadows/sun_shadow.png"

## Cada cuanto se revisa que oclusores hay. Los oclusores se crean y se
## destruyen con el mundo (zombis que mueren, bosque que se carga), asi que
## un rastreoperiodico es mas barato y seguro que hooking de cada nodo.
const REFRESH_INTERVAL: float = 0.5

## COTA DURA de la sombra diurna en pixeles. Ninguna mancha pasa de aqui.
const MAX_SHADOW_LENGTH: float = 48.0
const MIN_SHADOW_LENGTH: float = 16.0
const MIN_SHADOW_WIDTH: float = 14.0
## Cuanto se prolonga la sombra mas alla del objeto que la proyecta.
const SHADOW_EXTEND: float = 12.0

## Color de la mancha (azul-negro). El ALPHA lo governing la fase.
const BLOB_TINT: Color = Color(0.05, 0.055, 0.08, 1.0)

## Opacidad de la mancha por fase del dia. De noche no hay sol: la mancha
## desaparece y solo queda el faro (con sus sombras reales).
const PHASE_ALPHA: Dictionary = {
	"day": 0.38,
	"dawn": 0.30,
	"dusk": 0.26,
	"night": 0.0,
}

var _phase: String = "day"
var _sun_angle: float = 0.0
var _refresh_t: float = 0.0
var _enabled: bool = true
var _texture: Texture2D = null
## instance_id del oclusor -> { "sprite": Sprite2D, "occ": WeakRef }
var _blobs: Dictionary = {}


func _ready() -> void:
	if ResourceLoader.exists(BLOB_TEXTURE):
		_texture = load(BLOB_TEXTURE) as Texture2D


func _process(delta: float) -> void:
	if not _enabled:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH_INTERVAL
		_refresh_occluders()
	_update_blobs()


## ---------------------------------------------------------------------------
## API publica (la usa SolarLighting y el arnés)
## ---------------------------------------------------------------------------

## La fase y el angulo del sol los manda `SolarLighting` (que ya conoce el
## ciclo dia/noche y el angulo solar). El controlador NO busca el director:
## una sola fuente de verdad para la fase.
func set_sun_state(phase: String, angle_rad: float) -> void:
	_phase = String(phase).to_lower()
	_sun_angle = angle_rad


## Interruptor: si se desactiva, las manchas desaparecen (y no se crean).
func set_bounded_shadows_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_clear_blobs()


func bounded_shadows_enabled() -> bool:
	return _enabled


## Opacidad de la mancha para la fase indicada (o la actual).
func phase_alpha(phase: String = "") -> float:
	var key: String = String(phase).to_lower()
	if key == "":
		key = _phase
	return float(PHASE_ALPHA.get(key, 0.0))


## Cota dura de la sombra (px). Es el contrato verificable.
func max_shadow_length() -> float:
	return MAX_SHADOW_LENGTH


## Direccion en la que se proyecta la sombra (opuesta a la luz).
func shadow_direction() -> Vector2:
	return Vector2.RIGHT.rotated(_sun_angle + PI)


## Numero de manchas vivas.
func blob_count() -> int:
	return _blobs.size()


## Longitud (px) del eje largo de cada mancha, en el mismo orden que
## `blob_count()`. Sirve para exigir la cota.
func blob_lengths() -> Array[float]:
	var out: Array[float] = []
	for key in _blobs.keys():
		var entry: Dictionary = _blobs[key]
		var sprite: Sprite2D = entry.get("sprite", null) as Sprite2D
		if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
			continue
		out.append(sprite.scale.y * float(sprite.texture.get_height()))
	return out


## Distancia (px) entre el centro del oclusor y el centro de su mancha.
func blob_offsets() -> Array[float]:
	var out: Array[float] = []
	for key in _blobs.keys():
		var entry: Dictionary = _blobs[key]
		var sprite: Sprite2D = entry.get("sprite", null) as Sprite2D
		var occ_ref: WeakRef = entry.get("occ", null) as WeakRef
		if sprite == null or not is_instance_valid(sprite) or occ_ref == null:
			continue
		var occ := occ_ref.get_ref() as LightOccluder2D
		if occ == null or not is_instance_valid(occ):
			continue
		out.append(sprite.global_position.distance_to(occ.global_position))
	return out


## Fuerza un rastreo inmediato de oclusores (lo usa el arnés).
func refresh_now() -> void:
	_refresh_occluders()
	_update_blobs()


## ---------------------------------------------------------------------------
## Interno
## ---------------------------------------------------------------------------

func _refresh_occluders() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Se busca desde la RAIZ del arbol, no desde `current_scene`: asi el
	# controlador funciona igual dentro del juego (Main) y dentro de un
	# arnés, donde la escena actual es el propio arnés y el mundo vive en un
	# sandbox aparte.
	var root: Node = tree.root
	if root == null or not is_instance_valid(root):
		return
	var found: Array = root.find_children("*", "LightOccluder2D", true, false)
	for node in found:
		var occ := node as LightOccluder2D
		if occ == null or not is_instance_valid(occ):
			continue
		var key: int = occ.get_instance_id()
		if not _blobs.has(key):
			_blobs[key] = _make_blob(occ)
	# Los oclusores que ya no existen se limpian (zombis muertos, bosque
	# descargado). La mancha es hija del controlador, asi que se libera con el.
	for key in _blobs.keys():
		var entry: Dictionary = _blobs[key]
		var occ_ref := entry.get("occ", null) as WeakRef
		if occ_ref != null and occ_ref.get_ref() != null:
			continue
		var sprite := entry.get("sprite", null) as Sprite2D
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
		_blobs.erase(key)


func _make_blob(occ: LightOccluder2D) -> Dictionary:
	var sprite := Sprite2D.new()
	sprite.name = "SunShadow"
	sprite.texture = _texture
	sprite.centered = true
	# La mancha NO recibe luz: es oscuridad pintada, no una superficie.
	sprite.light_mask = 0
	sprite.modulate = Color(BLOB_TINT.r, BLOB_TINT.g, BLOB_TINT.b, 0.0)
	add_child(sprite)
	return {"sprite": sprite, "occ": weakref(occ)}


func _clear_blobs() -> void:
	for key in _blobs.keys():
		var entry: Dictionary = _blobs[key]
		var sprite := entry.get("sprite", null) as Sprite2D
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
	_blobs.clear()


func _update_blobs() -> void:
	if _texture == null:
		return
	var alpha: float = phase_alpha()
	var shadow_dir: Vector2 = shadow_direction()
	var across_axis: Vector2 = Vector2(-shadow_dir.y, shadow_dir.x)
	var tex_size := Vector2(float(_texture.get_width()), float(_texture.get_height()))
	for key in _blobs.keys():
		var entry: Dictionary = _blobs[key]
		var sprite := entry.get("sprite", null) as Sprite2D
		var occ_ref := entry.get("occ", null) as WeakRef
		if sprite == null or not is_instance_valid(sprite) or occ_ref == null:
			continue
		var occ := occ_ref.get_ref() as LightOccluder2D
		if occ == null or not is_instance_valid(occ):
			continue
		var size: Vector2 = _occluder_size(occ)
		# Extension del objeto proyectada sobre el eje del sol y el
		# perpendicular.
		var along: float = absf(size.x * shadow_dir.x) + absf(size.y * shadow_dir.y)
		var across: float = absf(size.x * across_axis.x) + absf(size.y * across_axis.y)
		var length: float = clampf(along + SHADOW_EXTEND,
			MIN_SHADOW_LENGTH, MAX_SHADOW_LENGTH)
		var width: float = maxf(across, MIN_SHADOW_WIDTH)
		# Lo que sobresale del objeto es lo que se desplaza: el centro de la
		# mancha se separa la mitad de la prolongacion.
		var extra: float = maxf(length - along, 0.0)
		sprite.global_position = occ.global_position + shadow_dir * (extra * 0.5)
		sprite.global_rotation = shadow_dir.angle()
		sprite.scale = Vector2(width / tex_size.x, length / tex_size.y)
		sprite.modulate = Color(BLOB_TINT.r, BLOB_TINT.g, BLOB_TINT.b, alpha)


## Tamano (px) del rectangulo que envuelve al oclusor.
func _occluder_size(occ: LightOccluder2D) -> Vector2:
	var poly_node: OccluderPolygon2D = occ.occluder
	if poly_node == null:
		return Vector2(24.0, 24.0)
	var polygon: PackedVector2Array = poly_node.polygon
	if polygon.is_empty():
		return Vector2(24.0, 24.0)
	var rect := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		rect = rect.expand(point)
	var scale: Vector2 = occ.scale
	return Vector2(absf(rect.size.x * scale.x), absf(rect.size.y * scale.y))
