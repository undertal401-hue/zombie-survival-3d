extends Node
## Regresión R11/R12: faros de vehículo y resplandor solar.
## R11 cerró #14: DriveableVehicle._night_factor() resuelve el director real
## `/root/Main/WaveManager` (NO `/root/WorldDirector`) y usa current_phase().
## R12 cerró el residual `/root/Main/SolarLighting` y cableó `viewport_aspect`
## desde SolarLighting.gd hasta SolarGlare.gdshader.
## No existía ningún arnés que leyera estas dos superficies: este sí lo hace.

const SHADER_PATH: String = "res://08_ui/SolarGlare.gdshader"
const MATERIAL_PATH: String = "res://08_ui/SolarGlareMaterial.tres"
const DIRECTOR_SCENE: String = "res://01_core/WorldDirector.tscn"
const SOLAR_SCENE: String = "res://08_ui/SolarLighting.tscn"
const VEHICLE_SCENE: String = "res://12_vehicles/DriveableVehicle.tscn"

var _failures: Array[String] = []
var _sandbox: Node
var _decoy: Node
var _wm: Node
var _solar: Node
var _vehicle: Node

func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)

func _ready() -> void:
	await get_tree().process_frame
	_shader_checks()
	_build_sandbox()
	_solar_checks()
	_vehicle_checks()
	await _finish()

# --- Shader / material -----------------------------------------------------

func _shader_checks() -> void:
	var shader: Shader = load(SHADER_PATH) as Shader
	var mat: ShaderMaterial = load(MATERIAL_PATH) as ShaderMaterial
	_check(mat != null and shader != null and mat.shader == shader
		and mat.resource_path == MATERIAL_PATH,
		"SolarGlareMaterial.tres apunta a SolarGlare.gdshader")

	# Declaración directa del uniform en la fuente. Un ShaderMaterial recién
	# creado devuelve null en get_shader_parameter() para uniforms con valor
	# por defecto (Godot 4.7), así que la fuente es la prueba fiable aquí;
	# el valor en marcha se comprueba abajo sobre el material de SolarLighting.
	var source: String = FileAccess.get_file_as_string(SHADER_PATH)
	var declared: bool = source.contains("uniform float viewport_aspect = 1.0")
	_check(shader != null and declared,
		"SolarGlare.gdshader expone viewport_aspect (default 1.0)")

func _solar_checks() -> void:
	var glare: ColorRect = _solar.get_node_or_null("GlareLayer/GlareRect") as ColorRect
	var gm: ShaderMaterial = null
	if glare != null:
		gm = glare.material as ShaderMaterial
	var glare_shader: Shader = load(SHADER_PATH) as Shader
	_check(glare != null and gm != null and gm.shader == glare_shader,
		"SolarLighting.tscn GlareRect usa ShaderMaterial del glare")

	if gm == null:
		return
	var value: Variant = gm.get_shader_parameter("viewport_aspect")
	var size: Vector2 = get_viewport().get_visible_rect().size
	var expected: float = size.x / maxf(size.y, 1.0)
	_check(value is float and is_equal_approx(float(value), expected),
		"SolarLighting.gd actualiza viewport_aspect desde el tamaño del viewport")

# --- Árbol sintético -------------------------------------------------------

func _build_sandbox() -> void:
	# `/root/Main` sin instanciar el Main completo: suficiente para las rutas
	# absolutas que consulta _night_factor().
	_sandbox = Node.new()
	_sandbox.name = "Main"
	get_tree().root.add_child(_sandbox)

	# Decoy R11: `/root/WorldDirector` existe y está en fase night. Si el
	# vehículo lo leyera, los checks day/dawn darían 1.0 en vez de 0.0.
	_decoy = load(DIRECTOR_SCENE).instantiate()
	_decoy.name = "WorldDirector"
	get_tree().root.add_child(_decoy)
	_decoy.call("force_phase", "night")

	_wm = load(DIRECTOR_SCENE).instantiate()
	_wm.name = "WaveManager"
	_sandbox.add_child(_wm)

	_solar = load(SOLAR_SCENE).instantiate()
	_solar.name = "SolarLighting"
	_sandbox.add_child(_solar)

	_vehicle = load(VEHICLE_SCENE).instantiate()
	_sandbox.add_child(_vehicle)

# --- DriveableVehicle._night_factor() -------------------------------------

func _night() -> float:
	return float(_vehicle.call("_night_factor"))

func _vehicle_checks() -> void:
	var decoy_ok: bool = get_node_or_null("/root/WorldDirector") == _decoy
	_wm.call("force_phase", "day")
	var day: float = _night()
	_wm.call("force_phase", "dawn")
	var dawn: float = _night()
	_check(decoy_ok and is_equal_approx(day, 0.0) and is_equal_approx(dawn, 0.0),
		"resuelve /root/Main/WaveManager (no /root/WorldDirector): day/dawn -> 0.0")

	_wm.call("force_phase", "dusk")
	var dusk: float = _night()
	_wm.call("force_phase", "night")
	var night: float = _night()
	_check(is_equal_approx(dusk, 1.0) and is_equal_approx(night, 1.0),
		"fase dusk/night del director -> 1.0 (faros encendidos)")

	# R12: sin WaveManager cae al SolarLighting hijo de Main.
	# 1.0 - 0.2125 / 0.85 == 0.75 exacto.
	_sandbox.remove_child(_wm)
	_wm.free()
	_solar.set("ambient_energy", 0.2125)
	_check(is_equal_approx(_night(), 0.75),
		"fallback /root/Main/SolarLighting: ambient 0.2125 -> 0.75")

	# Sin director ni solar: crepúsculo neutro.
	_sandbox.remove_child(_solar)
	_solar.free()
	_check(is_equal_approx(_night(), 0.35),
		"sin director ni SolarLighting -> 0.35 (neutro)")

# --- Cierre ----------------------------------------------------------------

func _finish() -> void:
	if is_instance_valid(_vehicle):
		_vehicle.queue_free()
	if is_instance_valid(_decoy):
		_decoy.queue_free()
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	# Dar tiempo al árbol a liberar los nodos antes de salir, evitando
	# "ObjectDB instances were leaked at exit" en headless.
	for i in range(6):
		await get_tree().process_frame
	print("NIGHT_GLARE_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# La salida se programa ANTES de los assert: si uno falla en debug el
	# proceso ya tiene su código y el CI no puede dar verde aunque el arnés
	# se detenga. En release los asserts se compilan fuera y los _failures
	# de arriba siguen gobernando la salida.
	get_tree().quit(1 if not _failures.is_empty() else 0)
	for f in _failures:
		assert(false, "NIGHT_GLARE_TEST: " + f)
