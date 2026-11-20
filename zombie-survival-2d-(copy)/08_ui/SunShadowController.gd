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
##   2. La mancha mide como maximo `MAX_SHADOW_LENGTH` px en su eje largo y
##      `MAX_SHADOW_WIDTH` px en el transversal: nunca llega al borde de la
##      pantalla (1280x720) ni se convierte en una elipse gigante.
##   3. La mancha NO recibe luz: usa `light_mask = 0` y un
##      `CanvasItemMaterial` en modo `UNSHADED`. La primera guarda no basta
##      con una `DirectionalLight2D` en Godot 4.7.
##   4. De noche la mancha es INVISIBLE (alpha 0) y el sol no aporta energia.
##   5. La mancha se ORIENTA y se alarga en la direccion opuesta a la luz,
##      sin desplazar su ancla desde el centro del poligono.
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
const MAX_SHADOW_WIDTH: float = 48.0
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
	_normalize_global_scale()
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


## Cota dura del eje transversal (px). Es parte del mismo contrato que la
## longitud y ambos valores son exactamente 48 en ADR-006.
func max_shadow_width() -> float:
	return MAX_SHADOW_WIDTH


## Direccion en la que se proyecta la sombra (opuesta a la luz).
func shadow_direction() -> Vector2:
	return Vector2.RIGHT.rotated(_sun_angle + PI)


## Numero de manchas vivas.
func blob_count() -> int:
	return _blobs.size()


## Dimension MAYOR (px) de cada mancha, en el mismo orden que `blob_count()`.
## Es la magnitud que debe respetar la cota dura, tanto si el eje elongado
## es el X local como si la geometria del emisor invierte los ejes.
func blob_lengths() -> Array[float]:
	var out: Array[float] = []
	for key in _blobs.keys():
		var entry: Dictionary = _blobs[key]
		var sprite: Sprite2D = entry.get("sprite", null) as Sprite2D
		if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
			continue
		var world_size := _sprite_world_size(sprite)
		out.append(maxf(world_size.x, world_size.y))
	return out


## Dimension visual efectiva de un sprite en el mundo. Se transforman sus ejes
## locales con `global_transform`: asi se incluyen TODOS los ancestros y no
## solo la escala local del sprite.
func _sprite_world_size(sprite: Sprite2D) -> Vector2:
	if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
		return Vector2.ZERO
	var texture_width := float(sprite.texture.get_width())
	var texture_height := float(sprite.texture.get_height())
	var world_transform := sprite.global_transform
	return Vector2(
		world_transform.basis_xform(Vector2.RIGHT * texture_width).length(),
		world_transform.basis_xform(Vector2.DOWN * texture_height).length())


## Distancia (px) entre el centro geometrical del poligono del oclusor y el
## centro de su mancha. No usa `occ.global_position`: en House.gd el nodo esta
## en el origen de la casa y el poligono lleva las coordenadas del muro.
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
		out.append(sprite.global_position.distance_to(
			_occluder_bounds(occ).get_center()))
	return out


## Fuerza un rastreo inmediato de oclusores (lo usa el arnés).
func refresh_now() -> void:
	_refresh_occluders()
	_update_blobs()


## ---------------------------------------------------------------------------
## Interno
## ---------------------------------------------------------------------------

## Garantiza que el controlador y sus manchas usen una escala global de 1.
## Se revalida en cada actualizacion porque un ancestro puede cambiar de
## escala despues de `_ready()`.
func _normalize_global_scale() -> void:
	if not is_inside_tree():
		return
	global_scale = Vector2.ONE


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
	# `light_mask = 0` no basta con una DirectionalLight2D (Godot 4.7 la ignora
	# para CanvasItems); UNSHADED es el contrato que impide que el sol la
	# aclare.
	sprite.light_mask = 0
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	sprite.material = material
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
	# Las cotas de ADR-006 estan expresadas en pixeles MUNDIALES. El
	# controlador neutraliza cualquier escala propia o heredada para que un
	# ancestro futuro no convierta 48 px en 96 px.
	_normalize_global_scale()
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
		var bounds: Rect2 = _occluder_bounds(occ)
		var size: Vector2 = bounds.size
		# Extension del objeto proyectada sobre el eje del sol y el
		# perpendicular.
		var along: float = absf(size.x * shadow_dir.x) + absf(size.y * shadow_dir.y)
		var across: float = absf(size.x * across_axis.x) + absf(size.y * across_axis.y)
		var length: float = clampf(along + SHADOW_EXTEND,
			MIN_SHADOW_LENGTH, MAX_SHADOW_LENGTH)
		var width: float = clampf(across, MIN_SHADOW_WIDTH, MAX_SHADOW_WIDTH)
		# El eje local Y se orienta hacia `shadow_direction`; debe ser el eje
		# visual REAL mas largo. Sin esta garantia, un oclusor mas ancho que
		# largo deja el eje X (perpendicular) como mayor y la sombra se
		# alarga en la direccion equivocada.
		length = maxf(length, width)
		# Ancla EXACTA: el centro de la mancha coincide con el centro mundial
		# del poligono real. La elongacion se obtiene orientando la mascara;
		# desplazar el sprite moveria su ancla y romperia el contrato.
		sprite.global_position = bounds.get_center()
		# La textura se elonga por su eje local Y. Para que ese eje sea la
		# direccion de la sombra, el sprite debe girar 90 grados menos que la
		# direccion proyectada.
		sprite.global_rotation = shadow_dir.angle() - PI * 0.5
		# La escala es mundial: el accessor y la prueba pueden contrastarla
		# con `global_transform` sin depender de la escala local.
		sprite.global_scale = Vector2(width / tex_size.x, length / tex_size.y)
		sprite.modulate = Color(BLOB_TINT.r, BLOB_TINT.g, BLOB_TINT.b, alpha)
		sprite.visible = alpha > 0.0


## Caja MUNDIAL (px) que envuelve el poligono real del oclusor. Se transforman
## todos los puntos: asi se respeta la posicion, escala y rotacion del nodo y
## se distinguen los muros de House.gd, cuyo poligono no esta centrado en el
## origen del oclusor.
func _occluder_bounds(occ: LightOccluder2D) -> Rect2:
	var poly_node: OccluderPolygon2D = occ.occluder
	if poly_node == null or poly_node.polygon.is_empty():
		return Rect2(occ.global_position - Vector2(12, 12), Vector2(24, 24))
	var first := occ.to_global(poly_node.polygon[0])
	var bounds := Rect2(first, Vector2.ZERO)
	for point in poly_node.polygon:
		bounds = bounds.expand(occ.to_global(point))
	return bounds
