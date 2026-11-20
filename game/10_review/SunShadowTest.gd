extends Node
## ============================================================================
## SUN SHADOW TEST (R3 / ADR-006) — sombras DIURNAS acotadas.
## ============================================================================
## El usuario complained de que las sombras de dia llegaban hasta el borde de
## pantalla. La causa raiz NO es un parametro mal puesto: en Godot 4 la
## sombra de una `DirectionalLight2D` NO TIENE LARGO.
##
## Hecho de motor (verificado con ClassDB en 4.7.2 y con el codigo fuente
## `renderer_canvas_render_rd.cpp: light_update_directional_shadow()`):
##   - `Light2D` NO tiene `shadow_max_distance` (nunca existio en Godot 4).
##   - `DirectionalLight2D.max_distance` NO acorta la sombra: solo amplia el
##     rectangulo de oclusores considerados y suma al `z_far`
##     (`2 * to_edge_distance + cull_distance`).
##   - La sombra direccional 2D se prolonga hasta el BORDE DE LA PANTALLA en
##     la direccion opuesta a la luz. Ningun parametro la acorta.
##
## Este arnes fija el contrato de la SOLUCION (manchas acotadas) y deja
## intacto el faro nocturno, que es lo que el usuario valora:
##
##   1. El sol NO proyecta sombra direccional (la ilimitada).
##   2. Ya no existe el "limite" ficticio `shadow_max_distance`.
##   3. Existe un controlador de sombras acotadas con una COTA DURA.
##   4. Cada oclusor vivo tiene una mancha y NUNCA supera la cota.
##   5. La mancha no recibe luz (`light_mask = 0` + material `UNSHADED`) y
##      esta por debajo de los personajes.
##   6. De noche la mancha es invisible y el sol no aporta energia.
##   7. El faro del jugador SIGUE con sombras reales (no se toca).
##
## Control negativo: si se vuelve a activar `shadow_enabled` en el
## DirectionalLight2D, el punto 1 falla. Si se sube la cota, el punto 4 falla.
## ============================================================================

const SOLAR_GD: String = "res://08_ui/SolarLighting.gd"
const SOLAR_SCENE: String = "res://08_ui/SolarLighting.tscn"
const SHADOWS_GD: String = "res://08_ui/SunShadowController.gd"
const SHADOW_TEXTURE: String = "res://assets/art/shadows/sun_shadow.png"
const PLAYER_SCENE: String = "res://02_player/Player.tscn"
const ZOMBIE_SCENE: String = "res://03_zombies/Zombie.tscn"

## Contrato DURO de ADR-006: 48 px exactos en ambos ejes. No se admite una
## puerta laxa como `<= 64`.
const EXPECTED_MAX_SHADOW_LENGTH_PX: float = 48.0
const EXPECTED_MAX_SHADOW_WIDTH_PX: float = 48.0
## Tolerancia maxima para comparaciones geometricas en pixeles.
const GEOMETRY_TOLERANCE_PX: float = 0.001

var _failures: Array[String] = []
var _instances: Array[Node] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _read(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	return ""


func _ready() -> void:
	await get_tree().process_frame
	_static_checks()
	_scene_checks()
	await _runtime_checks()
	await _finish()


## ---------------------------------------------------------------------------
## 1. Introspeccion del contrato.
## ---------------------------------------------------------------------------
func _static_checks() -> void:
	var solar_src: String = _read(SOLAR_GD)
	_check(solar_src.contains("shadow_enabled = false"),
		"SolarLighting.gd desactiva la sombra direccional del sol")
	_check(not solar_src.contains("var shadow_max_distance"),
		"SolarLighting.gd ya no declara el limite ficticio shadow_max_distance")
	_check(not solar_src.contains("sun_light.max_distance"),
		"SolarLighting.gd ya no asigna max_distance al sol")

	var shadows_src: String = _read(SHADOWS_GD)
	_check(shadows_src.contains("MAX_SHADOW_LENGTH"),
		"SunShadowController declara una cota dura de longitud")
	_check(shadows_src.contains("light_mask = 0"),
		"SunShadowController pinta las manchas sin luz (light_mask = 0)")

	# La textura de la mancha la genera el pipeline determinista.
	_check(FileAccess.file_exists(SHADOW_TEXTURE),
		"existe la mascara de sombra %s" % SHADOW_TEXTURE)
	var tex: Texture2D = load(SHADOW_TEXTURE) as Texture2D
	_check(tex != null and tex.get_width() == 64 and tex.get_height() == 64,
		"la mascara de sombra es 64x64")


## ---------------------------------------------------------------------------
## 2. La escena: el sol sin sombra ilimitada y el faro INTACTO.
## ---------------------------------------------------------------------------
func _scene_checks() -> void:
	var solar_scene: String = _read(SOLAR_SCENE)
	_check(solar_scene.contains("[node name=\"SunLight\" type=\"DirectionalLight2D\""),
		"SolarLighting.tscn: existe la DirectionalLight2D")
	_check(solar_scene.contains("shadow_enabled = false"),
		"SolarLighting.tscn: el sol NO proyecta la sombra direccional ilimitada")
	_check(not solar_scene.contains("max_distance"),
		"SolarLighting.tscn: fuera el limite ficticio max_distance")
	_check(solar_scene.contains("[node name=\"SunShadows\" type=\"Node2D\""),
		"SolarLighting.tscn: monta el controlador de sombras acotadas")

	# El faro NOCTURNO es intocable: es la parte que el usuario valora.
	var player_scene: String = _read(PLAYER_SCENE)
	_check(player_scene.contains("[node name=\"Flashlight\" type=\"PointLight2D\""),
		"Player.tscn: el faro sigue siendo una PointLight2D")
	_check(player_scene.contains("shadow_enabled = true"),
		"Player.tscn: el faro CONSERVA sus sombras reales")


## ---------------------------------------------------------------------------
## 3. Runtime: una mancha por oclusor, acotada, sin luz y de noche invisible.
## ---------------------------------------------------------------------------
func _runtime_checks() -> void:
	var sandbox := Node.new()
	sandbox.name = "SunShadowSandbox"
	get_tree().root.add_child(sandbox)
	_instances.append(sandbox)

	# Emisores de sombra: un zombi, un muro y fixtures geometricos.
	var zombie: Node = load(ZOMBIE_SCENE).instantiate()
	zombie.set_physics_process(false)
	sandbox.add_child(zombie)
	zombie.global_position = Vector2(100, 100)

	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(64, 16)
	shape.shape = rect
	wall.add_child(shape)
	var occluder := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	# Caso real de House.gd: el nodo oclusor esta en el origen del cuerpo,
	# pero el poligono lleva las coordenadas del muro dentro de ese cuerpo.
	# Si la mancha se ancla a `occ.global_position`, aparece en el centro de la
	# casa en vez de sobre el muro.
	poly.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(64, 0), Vector2(64, 16), Vector2(0, 16),
	])
	occluder.occluder = poly
	wall.add_child(occluder)
	sandbox.add_child(wall)
	wall.global_position = Vector2(400, 100)

	# Fixture con el eje TRANSVERSAL mayor que el longitudinal. Con el sol al
	# este, la dimension transversal de este poste (64 px) supera a la
	# longitudinal (16 px). Sirve para detectar que `blob_lengths()` informe
	# solo del eje Y.
	var post := StaticBody2D.new()
	post.collision_layer = 1
	var post_shape := CollisionShape2D.new()
	var post_rect := RectangleShape2D.new()
	post_rect.size = Vector2(16, 64)
	post_shape.shape = post_rect
	post.add_child(post_shape)
	var post_occluder := LightOccluder2D.new()
	var post_poly := OccluderPolygon2D.new()
	post_poly.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(16, 0), Vector2(16, 64), Vector2(0, 64),
	])
	post_occluder.occluder = post_poly
	post.add_child(post_occluder)
	sandbox.add_child(post)
	post.global_position = Vector2(600, 100)

	# Edificio ancho: el eje transversal tambien debe quedar acotado. Una
	# mancha de 220x180 px seria el bug que allowia el eje sin cota.
	var building := StaticBody2D.new()
	building.collision_layer = 1
	var building_shape := CollisionShape2D.new()
	var building_rect := RectangleShape2D.new()
	building_rect.size = Vector2(220, 180)
	building_shape.shape = building_rect
	building.add_child(building_shape)
	var building_occluder := LightOccluder2D.new()
	var building_poly := OccluderPolygon2D.new()
	building_poly.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(220, 0), Vector2(220, 180), Vector2(0, 180),
	])
	building_occluder.occluder = building_poly
	building.add_child(building_occluder)
	sandbox.add_child(building)
	building.global_position = Vector2(800, 100)

	var solar: Node = load(SOLAR_SCENE).instantiate()
	sandbox.add_child(solar)
	for i in range(4):
		await get_tree().process_frame

	var controller: Node = solar.get_node_or_null("SunShadows")
	_check(controller != null, "runtime: SolarLighting.tscn monta SunShadows")
	if controller == null:
		await _finish()
		return

	# Fase de dia: el sol aporta energia y las manchas son visibles.
	controller.call("set_sun_state", "day", 0.0)
	controller.call("refresh_now")
	await get_tree().process_frame

	# La puerta exige los valores EXACTOS de ADR-006. `<= 64` permitia que una
	# cota futura mas grande siguiera dando verde.
	var shadow_script := controller.get_script() as GDScript
	var shadow_constants: Dictionary = shadow_script.get_script_constant_map()
	var declared_max_length := float(shadow_constants.get("MAX_SHADOW_LENGTH", -1.0))
	var declared_max_width := float(shadow_constants.get("MAX_SHADOW_WIDTH", -1.0))
	_check(declared_max_length == EXPECTED_MAX_SHADOW_LENGTH_PX,
		"runtime: MAX_SHADOW_LENGTH es exactamente 48 px")
	_check(declared_max_width == EXPECTED_MAX_SHADOW_WIDTH_PX,
		"runtime: MAX_SHADOW_WIDTH es exactamente 48 px")
	var max_length: float = float(controller.call("max_shadow_length"))
	_check(max_length == EXPECTED_MAX_SHADOW_LENGTH_PX,
		"runtime: max_shadow_length() expone exactamente 48 px")
	var has_width_accessor: bool = controller.has_method("max_shadow_width")
	_check(has_width_accessor,
		"runtime: el controlador expone max_shadow_width()")
	var max_width := -1.0
	if has_width_accessor:
		max_width = float(controller.call("max_shadow_width"))
	_check(max_width == EXPECTED_MAX_SHADOW_WIDTH_PX,
		"runtime: max_shadow_width() expone exactamente 48 px")
	var live_occluders: Array = get_tree().root.find_children(
		"*", "LightOccluder2D", true, false)
	var blob_count: int = int(controller.call("blob_count"))
	_check(blob_count == live_occluders.size(),
		"runtime: hay EXACTAMENTE una mancha por oclusor (%d manchas / %d oclusores)" % \
			[blob_count, live_occluders.size()])

	# La geometria real del sprite es el contrato: no basta con que la API
	# reporte una longitud acotada si el eje transversal o la orientacion
	# estan mal.
	var blobs: Dictionary = controller.get("_blobs") as Dictionary
	var lengths: Array = controller.call("blob_lengths")
	var shadow_direction := controller.call("shadow_direction") as Vector2
	var dimensions_ok := _blob_dimensions_within_contract(blobs)
	# Este helper NO presupone que el eje local Y es el largo: compara el eje
	# transformado REALMENTE mas largo. El fixture transversal 16x64 debe
	# detectarlo cuando el local X queda mas largo que el local Y.
	var orientation_ok := _blob_orientations_match(blobs, shadow_direction)
	var shadow_axis_dominance_ok := _blob_shadow_axes_are_dominant(
		blobs, shadow_direction)
	var anchoring_ok: bool = not blobs.is_empty()
	var unshaded_ok: bool = not blobs.is_empty()
	for key in blobs.keys():
		var entry: Dictionary = blobs[key]
		var sprite := entry.get("sprite", null) as Sprite2D
		var occ_ref := entry.get("occ", null) as WeakRef
		if sprite == null or not is_instance_valid(sprite) or occ_ref == null:
			anchoring_ok = false
			unshaded_ok = false
			continue
		# DirectionalLight2D ignora CanvasItem.light_mask en Godot 4.7: para
		# que la mancha de oscuridad no reciba el sol hace falta un material
		# CanvasItemMaterial explícitamente UNSHADED.
		var material := sprite.material as CanvasItemMaterial
		if material == null \
				or material.light_mode != CanvasItemMaterial.LIGHT_MODE_UNSHADED:
			unshaded_ok = false
		var occ := occ_ref.get_ref() as LightOccluder2D
		if occ == null or not is_instance_valid(occ):
			anchoring_ok = false
			continue
		var bounds := _occluder_global_bounds(occ)
		if sprite.global_position.distance_to(bounds.get_center()) \
				> GEOMETRY_TOLERANCE_PX:
			anchoring_ok = false
	_check(dimensions_ok,
		"runtime: ambas dimensiones visuales de cada mancha respetan 48 px")
	_check(_blob_lengths_match_effective(blobs, lengths),
		"runtime: blob_lengths() contrasta con la dimension mundial maxima real")
	_check(orientation_ok,
		"runtime: el eje largo real coincide dinamicamente con shadow_direction() (segun la dimension visual)")
	_check(shadow_axis_dominance_ok,
		"runtime: el eje local Y mapeado a shadow_direction() domina al transversal")

	# Diagnostico RED explicito del fixture que motivo el bloqueante: con el
	# sol al este, el poste 16x64 tiene 64 px transversales y 16 px a lo largo.
	# La salida muestra el eje visual real y si es perpendicular a la sombra.
	var post_blob := _blob_sprite_for_occluder(blobs, post_occluder)
	var post_long_axis := _longest_visual_axis(post_blob)
	var post_axis_matches := false
	var post_axis_perpendicular := false
	if post_long_axis.length() > 0.0:
		var normalized_post_axis := post_long_axis.normalized()
		post_axis_matches = normalized_post_axis.distance_to(
			shadow_direction) <= GEOMETRY_TOLERANCE_PX
		post_axis_perpendicular = absf(normalized_post_axis.dot(
			shadow_direction)) <= GEOMETRY_TOLERANCE_PX
	_check(post_axis_matches,
		"runtime: fixture transversal 16x64: el eje real mas largo coincide con shadow_direction() (eje=%s, sombra=%s, perpendicular=%s)" % \
			[str(post_long_axis), str(shadow_direction), str(post_axis_perpendicular)])
	_check(anchoring_ok,
		"runtime: cada mancha se ancla EXACTAMENTE al centro mundial de su poligono")
	_check(unshaded_ok,
		"runtime: las manchas son UNSHADED y no reciben la DirectionalLight2D")

	# La mancha esta debajo de los personajes y no recibe luz.
	var under: bool = int(controller.get("z_index")) < 0
	var unlit: bool = true
	for child in controller.get_children():
		var sprite := child as Sprite2D
		if sprite == null:
			continue
		if sprite.light_mask != 0:
			unlit = false
		if not sprite.z_as_relative:
			under = false
	_check(unlit, "runtime: las manchas no reciben luz (light_mask = 0)")
	_check(under,
		"runtime: las manchas se dibujan por debajo de los personajes (z_index %d)" % \
			int(controller.get("z_index")))

	# La mancha se orienta en la direccion OPUESTA a la luz REAL del nodo
	# DirectionalLight2D. En Godot 4 esa luz emite por el eje +Y de su base.
	var sun: DirectionalLight2D = solar.get_node_or_null("SunLight") as DirectionalLight2D
	_check(sun != null and not sun.shadow_enabled,
		"runtime: el sol no proyecta la sombra direccional ilimitada")
	solar.call("set_solar_angle", 0.0)
	await get_tree().process_frame
	var emitted: Vector2 = Vector2.DOWN.rotated(sun.global_rotation)
	var expected_emitted := Vector2.RIGHT
	_check(emitted.is_equal_approx(expected_emitted),
		"runtime: con el sol al este la DirectionalLight2D emite al este (%s)" % str(emitted))
	var dir: Vector2 = controller.call("shadow_direction")
	_check(dir.is_equal_approx(Vector2.LEFT),
		"runtime: con el sol al este la sombra cae al oeste (%s)" % str(dir))
	_check(dir.distance_to(-emitted) <= GEOMETRY_TOLERANCE_PX,
		"runtime: la direccion de la mancha es opuesta a la luz emitida")
	controller.call("set_sun_state", "day", PI)
	controller.call("refresh_now")
	await get_tree().process_frame
	dir = controller.call("shadow_direction")
	_check(dir.is_equal_approx(Vector2.RIGHT),
		"runtime: con el sol al oeste la sombra cae al este (%s)" % str(dir))
	solar.call("set_solar_angle", PI * 0.5)
	controller.call("set_sun_state", "day", PI * 0.5)
	controller.call("refresh_now")
	await get_tree().process_frame
	emitted = Vector2.DOWN.rotated(sun.global_rotation)
	dir = controller.call("shadow_direction")
	_check(emitted.is_equal_approx(Vector2.DOWN),
		"runtime: con el sol al sur la DirectionalLight2D emite al sur (%s)" % str(emitted))
	_check(dir.is_equal_approx(Vector2.UP),
		"runtime: con el sol al sur la sombra cae al norte (%s)" % str(dir))

	# La orientacion no se contrasta contra un cardinal fijo: se compara con
	# la direccion DINAMICA del controlador en un angulo oblicuo y con una
	# tolerancia geometrica estricta.
	var oblique_angle := 0.63
	solar.call("set_solar_angle", oblique_angle)
	controller.call("set_sun_state", "day", oblique_angle)
	controller.call("refresh_now")
	await get_tree().process_frame
	var oblique_direction := controller.call("shadow_direction") as Vector2
	_check(_blob_orientations_match(blobs, oblique_direction),
		"runtime: el eje largo coincide con shadow_direction() en un angulo oblicuo")

	# ADR-006 expresa las cotas en pixeles MUNDIALES. Si un ancestro futuro
	# escala SunShadows, el runtime debe normalizar su escala global a 1 y la
	# puerta debe exigir esa normalizacion de forma explicita.
	var solar_2d := solar as Node2D
	var controller_2d := controller as Node2D
	solar_2d.scale = Vector2(2.0, 2.0)
	controller.call("refresh_now")
	await get_tree().process_frame
	_check(controller_2d != null and controller_2d.global_scale == Vector2.ONE,
		"runtime: el runtime normaliza SunShadows a escala global (1, 1)")
	var ancestor_scaled_lengths: Array = controller.call("blob_lengths")
	_check(_blob_dimensions_within_contract(blobs),
		"runtime: un ancestro escalado x2 no supera las cotas mundiales")
	_check(_blob_lengths_match_effective(blobs, ancestor_scaled_lengths),
		"runtime: blob_lengths() sigue reflejando el tamano mundial efectivo")
	solar_2d.scale = Vector2.ONE
	controller.call("refresh_now")
	await get_tree().process_frame

	# De noche: sin sol, sin manchas visibles, y el faro intacto.
	controller.call("set_sun_state", "night", 0.0)
	await get_tree().process_frame
	_check(is_equal_approx(float(controller.call("phase_alpha", "night")), 0.0),
		"runtime: de noche la mancha es INVISIBLE (alpha 0)")
	_check(float(controller.call("phase_alpha", "day")) > 0.0,
		"runtime: de dia la mancha se ve (alpha > 0)")
	var night_alpha_ok: bool = not blobs.is_empty()
	for key in blobs.keys():
		var entry: Dictionary = blobs[key]
		var sprite := entry.get("sprite", null) as Sprite2D
		if sprite == null or not is_instance_valid(sprite) \
				or not is_zero_approx(sprite.modulate.a):
			night_alpha_ok = false
	_check(night_alpha_ok,
		"runtime: todas las manchas tienen alpha 0 de noche")

	# El faro se comprueba sobre el nodo EXACTO, no leyendo el texto de la
	# escena: asi ningun otro nodo puede mantener `shadow_enabled = true` por
	# accidente mientras el faro pierde la suya.
	var player: Node = load(PLAYER_SCENE).instantiate()
	_instances.append(player)
	get_tree().root.add_child(player)
	await get_tree().process_frame
	var flashlight := player.get_node_or_null("Flashlight") as PointLight2D
	_check(flashlight != null and flashlight.shadow_enabled,
		"runtime: el nodo Flashlight conserva shadow_enabled = true")
	_check(flashlight != null and flashlight.texture != null \
			and flashlight.texture.resource_path == \
			"res://assets/art/lights/light_cone.png",
		"runtime: el faro conserva la textura canonica del cono")
	_check(flashlight != null and flashlight.shadow_filter == 1 \
			and is_equal_approx(flashlight.shadow_filter_smooth, 2.0),
		"runtime: el faro conserva el filtro de sombra canonico")

	# Ciclo de vida: al liberar un oclusor, el siguiente refresco debe quitar
	# tanto su entrada de `_blobs` como la mancha hija. Es un control de baja
	# prioridad, pero evita que un oclusor muerto conserve una mancha huerfana.
	var released_occluder_key := post_occluder.get_instance_id()
	var released_sprite := _blob_sprite_for_occluder(blobs, post_occluder)
	_check(released_sprite != null and is_instance_valid(released_sprite),
		"runtime: el oclusor liberado tiene una mancha antes de liberarlo")
	post_occluder.queue_free()
	await get_tree().process_frame
	controller.call("refresh_now")
	await get_tree().process_frame
	var blobs_after_release: Dictionary = controller.get("_blobs") as Dictionary
	_check(not blobs_after_release.has(released_occluder_key),
		"runtime: liberar un LightOccluder2D elimina su entrada de _blobs")
	_check(released_sprite == null or not is_instance_valid(released_sprite),
		"runtime: liberar un LightOccluder2D elimina su mancha")

	await _finish()


## Ejes visuales transformados en el mundo. Cada vector incluye la escala
## global y la dimension de la textura, de modo que su longitud es la longitud
## visual real de ese eje LOCAL, no solo una direccion sin escalar.
func _visual_axis_vectors(sprite: Sprite2D) -> Dictionary:
	if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
		return {"x": Vector2.ZERO, "y": Vector2.ZERO}
	var texture_width := float(sprite.texture.get_width())
	var texture_height := float(sprite.texture.get_height())
	var world_transform := sprite.global_transform
	return {
		"x": world_transform.basis_xform(Vector2.RIGHT * texture_width),
		"y": world_transform.basis_xform(Vector2.DOWN * texture_height),
	}


## Tamano visual efectivo en el mundo. Se transforman los ejes LOCALES de la
## textura con `global_transform`, de modo que se incluyen todos los ancestros
## (posicion, rotacion y escala), no solo `sprite.scale`.
func _effective_sprite_size(sprite: Sprite2D) -> Vector2:
	var axes := _visual_axis_vectors(sprite)
	var x_axis := axes.get("x", Vector2.ZERO) as Vector2
	var y_axis := axes.get("y", Vector2.ZERO) as Vector2
	return Vector2(x_axis.length(), y_axis.length())


## Eje visual REAL mas largo. En un empate se elige Y, que es el eje que el
## controlador mapea a `shadow_direction`; el contrato exige que Y nunca sea
## menor que X.
func _longest_visual_axis(sprite: Sprite2D) -> Vector2:
	var axes := _visual_axis_vectors(sprite)
	var x_axis := axes.get("x", Vector2.ZERO) as Vector2
	var y_axis := axes.get("y", Vector2.ZERO) as Vector2
	if x_axis.length() > y_axis.length():
		return x_axis
	return y_axis


## Sprite asociado a un oclusor concreto. Permite aislar un fixture sin
## depender del orden de iteracion del diccionario.
func _blob_sprite_for_occluder(blobs: Dictionary, occ: LightOccluder2D) -> Sprite2D:
	if occ == null or not is_instance_valid(occ):
		return null
	var wanted_id := occ.get_instance_id()
	for key in blobs.keys():
		var entry: Dictionary = blobs[key]
		var occ_ref := entry.get("occ", null) as WeakRef
		if occ_ref == null:
			continue
		var candidate := occ_ref.get_ref() as LightOccluder2D
		if candidate != null and candidate.get_instance_id() == wanted_id:
			return entry.get("sprite", null) as Sprite2D
	return null


func _blob_dimensions_within_contract(blobs: Dictionary) -> bool:
	if blobs.is_empty():
		return false
	for key in blobs.keys():
		var entry: Dictionary = blobs[key]
		var sprite := entry.get("sprite", null) as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			return false
		var visual_size := _effective_sprite_size(sprite)
		if visual_size.x > EXPECTED_MAX_SHADOW_WIDTH_PX + GEOMETRY_TOLERANCE_PX:
			return false
		if visual_size.y > EXPECTED_MAX_SHADOW_LENGTH_PX + GEOMETRY_TOLERANCE_PX:
			return false
	return true


func _blob_lengths_match_effective(blobs: Dictionary, lengths: Array) -> bool:
	if blobs.is_empty() or lengths.size() != blobs.size():
		return false
	var keys: Array = blobs.keys()
	for index in range(keys.size()):
		var entry: Dictionary = blobs[keys[index]]
		var sprite := entry.get("sprite", null) as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			return false
		var visual_size := _effective_sprite_size(sprite)
		var expected_length := maxf(visual_size.x, visual_size.y)
		if absf(float(lengths[index]) - expected_length) > GEOMETRY_TOLERANCE_PX:
			return false
	return true


func _blob_orientations_match(blobs: Dictionary, expected_direction: Vector2) -> bool:
	if blobs.is_empty():
		return false
	for key in blobs.keys():
		var entry: Dictionary = blobs[key]
		var sprite := entry.get("sprite", null) as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			return false
		# Selecciona el eje transformado REALMENTE mas largo. No presupone
		# que el eje local Y es el largo: si X es mayor, X debe coincidir con
		# `expected_direction` para que la puerta siga siendo verde.
		var long_axis := _longest_visual_axis(sprite)
		if long_axis.length() <= 0.0:
			return false
		if long_axis.normalized().distance_to(expected_direction) \
				> GEOMETRY_TOLERANCE_PX:
			return false
	return true


## Contrato adicional, explicito: el eje local Y es el que el controlador
## rota hacia `shadow_direction`, por lo que su longitud visual debe ser mayor
## o igual que la del eje transversal local X.
func _blob_shadow_axes_are_dominant(
		blobs: Dictionary, expected_direction: Vector2) -> bool:
	if blobs.is_empty():
		return false
	for key in blobs.keys():
		var entry: Dictionary = blobs[key]
		var sprite := entry.get("sprite", null) as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			return false
		var axes := _visual_axis_vectors(sprite)
		var x_axis := axes.get("x", Vector2.ZERO) as Vector2
		var y_axis := axes.get("y", Vector2.ZERO) as Vector2
		if y_axis.length() + GEOMETRY_TOLERANCE_PX < x_axis.length():
			return false
		if y_axis.length() <= 0.0:
			return false
		if y_axis.normalized().distance_to(expected_direction) \
				> GEOMETRY_TOLERANCE_PX:
			return false
	return true


## Caja mundial del poligono real del oclusor. Se usa el mismo criterio que
## el runtime: NO el origen del nodo, que en House.gd no coincide con el muro.
func _occluder_global_bounds(occ: LightOccluder2D) -> Rect2:
	var poly_node: OccluderPolygon2D = occ.occluder
	if poly_node == null or poly_node.polygon.is_empty():
		return Rect2(occ.global_position - Vector2(12, 12), Vector2(24, 24))
	var first := occ.to_global(poly_node.polygon[0])
	var bounds := Rect2(first, Vector2.ZERO)
	for point in poly_node.polygon:
		bounds = bounds.expand(occ.to_global(point))
	return bounds


func _finish() -> void:
	for node in _instances:
		if is_instance_valid(node):
			node.queue_free()
	_instances.clear()
	for i in range(4):
		await get_tree().process_frame
	print("SUN_SHADOW_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
	for f in _failures:
		assert(false, "SUN_SHADOW_TEST: " + f)
