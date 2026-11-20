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
##   5. La mancha no recibe luz (`light_mask = 0`) y esta por debajo de los
##      personajes.
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

	# Dos emisores de sombra: un zombi y un muro.
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
	poly.polygon = PackedVector2Array([
		Vector2(-32, -8), Vector2(32, -8), Vector2(32, 8), Vector2(-32, 8),
	])
	occluder.occluder = poly
	wall.add_child(occluder)
	sandbox.add_child(wall)
	wall.global_position = Vector2(400, 100)

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

	var max_length: float = float(controller.call("max_shadow_length"))
	_check(max_length > 0.0 and max_length <= 64.0,
		"runtime: la cota dura es razonable (%.0f px)" % max_length)
	_check(int(controller.call("blob_count")) >= 2,
		"runtime: hay una mancha por oclusor (%d)" % int(controller.call("blob_count")))

	var lengths: Array = controller.call("blob_lengths")
	var bounded: bool = lengths.size() >= 2
	for value in lengths:
		if float(value) > max_length + 0.5:
			bounded = false
	_check(bounded,
		"runtime: NINGUNA sombra supera la cota (%.0f px): %s" % [max_length, str(lengths)])

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

	# La mancha se desplaza en la direccion OPUESTA a la luz.
	controller.call("set_sun_state", "day", 0.0)
	controller.call("refresh_now")
	await get_tree().process_frame
	var dir: Vector2 = controller.call("shadow_direction")
	_check(dir.is_equal_approx(Vector2.LEFT),
		"runtime: con el sol al este la sombra cae al oeste (%s)" % str(dir))
	controller.call("set_sun_state", "day", PI)
	controller.call("refresh_now")
	await get_tree().process_frame
	dir = controller.call("shadow_direction")
	_check(dir.is_equal_approx(Vector2.RIGHT),
		"runtime: con el sol al oeste la sombra cae al este (%s)" % str(dir))

	# De noche: sin sol, sin manchas visibles, y el faro intacto.
	controller.call("set_sun_state", "night", 0.0)
	await get_tree().process_frame
	_check(is_equal_approx(float(controller.call("phase_alpha", "night")), 0.0),
		"runtime: de noche la mancha es INVISIBLE (alpha 0)")
	_check(float(controller.call("phase_alpha", "day")) > 0.0,
		"runtime: de dia la mancha se ve (alpha > 0)")

	var sun: DirectionalLight2D = solar.get_node_or_null("SunLight") as DirectionalLight2D
	_check(sun != null and not sun.shadow_enabled,
		"runtime: el sol no proyecta la sombra direccional ilimitada")

	var flashlight_src: String = _read(PLAYER_SCENE)
	_check(flashlight_src.contains("shadow_enabled = true"),
		"runtime: el faro nocturno conserva sus sombras reales")

	await _finish()


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
