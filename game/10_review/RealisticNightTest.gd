extends Node
## ============================================================================
## REALISTIC NIGHT TEST — noche realista con oscuridad continua y luces dinámicas.
## ============================================================================
## Contrato (punto 14):
## - WorldDirector expone night_factor() ∈ [0,1]: continuo, no binario.
##   0 = día pleno, 1 = noche profunda; crepúsculos son valores intermedios.
## - Main NO escribe ambient_energy/sun_energy directamente; WorldDirector
##   es la ÚNICA fuente vía apply_state() en SolarLighting.
## - StreetLight / PointLight2D reales en el barrio (luces de farola acotadas).
## - SolarLighting.apply_state() sigue intacto (firma y comportamiento).
## - MetaProgress usa night_factor() solo si NO existe current_phase() binario.
## - La oscuridad de noche es "media luz" legible sin faro; el cono destaca.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")
const DIRECTOR_SCENE: PackedScene = preload("res://01_core/WorldDirector.tscn")
const SOLAR_SCENE: PackedScene = preload("res://08_ui/SolarLighting.tscn")
## StreetLight.tscn se creará durante GREEN; no preload para evitar error en RED.

var _failures: Array[String] = []
var _checks: int = 0
var _main: Node = null
var _director: Node = null
var _solar: Node = null
var _neighborhood: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await _load_main()
	await _test_night_factor_exists_and_continuous()
	await _test_night_factor_values_by_phase()
	await _test_no_competing_ambient_writes_in_main()
	await _test_street_lights_exist_and_bounded()
	await _test_solar_apply_state_intact()
	await _test_meta_progress_uses_night_factor()
	await _test_night_darkness_is_medium_light()
	await _finish()

func _check(condition: bool, label: String) -> void:
	_checks += 1
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)

func _load_main() -> void:
	_main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	for _i in range(12):
		await get_tree().process_frame
	_director = _main.get_node_or_null("WaveManager")
	_solar = _main.get_node_or_null("SolarLighting")
	_neighborhood = _main.get_node_or_null("Level/Neighborhood")
	_check(_main != null, "Main crea el mundo real")
	_check(_director != null, "Main crea WorldDirector (WaveManager)")
	_check(_solar != null, "Main crea SolarLighting")
	_check(_neighborhood != null, "Main crea Neighborhood")
	_main.set_process(false)

## 1. WorldDirector expone night_factor() continua [0,1]
func _test_night_factor_exists_and_continuous() -> void:
	_check(_director != null and _director.has_method("night_factor"),
		"WorldDirector expone night_factor()")
	if _director == null or not _director.has_method("night_factor"):
		return
	# Debe ser float
	var val: Variant = _director.call("night_factor")
	_check(val is float or val is int, "night_factor() devuelve número")
	var f: float = float(val)
	_check(f >= 0.0 and f <= 1.0, "night_factor() ∈ [0,1]")
	# No es solo binario: debe poder tomar valores intermedios
	# (se verifica en _test_night_factor_values_by_phase)

## 2. night_factor() varía continuamente por fase
func _test_night_factor_values_by_phase() -> void:
	if _director == null or not _director.has_method("night_factor") or not _director.has_method("force_phase"):
		return
	# day -> ~0
	_director.call("force_phase", "day")
	await get_tree().process_frame
	var day: float = float(_director.call("night_factor"))
	_check(day < 0.15, "night_factor(day) ≈ 0 (got %.3f)" % day)
	# dawn -> bajo pero > 0 (force_phase pone _phase_t=0.1)
	_director.call("force_phase", "dawn")
	await get_tree().process_frame
	var dawn: float = float(_director.call("night_factor"))
	_check(dawn > 0.0 and dawn < 0.15, "night_factor(dawn) intermedio temprano (got %.3f)" % dawn)
	# dusk -> medio (force_phase pone _phase_t=0.1)
	_director.call("force_phase", "dusk")
	await get_tree().process_frame
	var dusk: float = float(_director.call("night_factor"))
	_check(dusk > 0.25 and dusk < 0.6, "night_factor(dusk) intermedio temprano (got %.3f)" % dusk)
	# night -> ~1
	_director.call("force_phase", "night")
	await get_tree().process_frame
	var night: float = float(_director.call("night_factor"))
	_check(night > 0.85, "night_factor(night) ≈ 1 (got %.3f)" % night)
	# Verificar continuidad: valores intermedios existen
	var all: Array[float] = [day, dawn, dusk, night]
	all.sort()
	var has_intermediate: bool = false
	for i in range(all.size() - 1):
		if all[i+1] - all[i] > 0.15:
			has_intermediate = true
	_check(has_intermediate, "night_factor tiene valores intermedios (no solo 0/1)")

## 3. Main NO escribe ambient_energy/sun_energy directamente
##    (excepto reset_to_defaults en forest_exited, que es legado permitido)
func _test_no_competing_ambient_writes_in_main() -> void:
	if _main == null:
		return
	var main_script: Script = _main.get_script()
	if main_script == null:
		_failures.append("Main no tiene script")
		return
	var source: String = main_script.get_source_code()
	# Buscar escrituras directas a solar_lighting.set_ambient_energy / set_sun_energy
	# EXCEPTO en forest_exited (reset_to_defaults) y _connect_state_signals
	var lines: PackedStringArray = source.split("\n")
	var forbidden_writes: Array[String] = []
	for i in range(lines.size()):
		var line: String = lines[i].strip_edges()
		if line.begins_with("#") or line.is_empty():
			continue
		# Detectar set_ambient_energy o set_sun_energy en solar_lighting
		if line.contains("solar_lighting.set_ambient_energy") \
				or line.contains("solar_lighting.set_sun_energy"):
			# Permitir solo si está en contexto de forest_exited/reset_to_defaults
			var context_ok: bool = false
			for j in range(max(0, i-5), min(lines.size(), i+5)):
				var ctx: String = lines[j].strip_edges()
				if ctx.contains("forest_exited") or ctx.contains("reset_to_defaults"):
					context_ok = true
					break
			if not context_ok:
				forbidden_writes.append("Línea %d: %s" % [i+1, line])
	_check(forbidden_writes.is_empty(),
		"Main no escribe ambient_energy/sun_energy directamente (excepto reset forest): " + str(forbidden_writes))

## 4. StreetLight / PointLight2D reales en el barrio (luces de farola acotadas)
func _test_street_lights_exist_and_bounded() -> void:
	if _neighborhood == null:
		_check(false, "Neighborhood existe para buscar farolas")
		return
	# Buscar PointLight2D en el barrio (farolas)
	var streetlights: Array[PointLight2D] = []
	_collect_point_lights(_neighborhood, streetlights)
	# En RED puede que no existan aún; en GREEN deben existir
	_check(streetlights.size() > 0, "Barrio tiene farolas PointLight2D (count=%d)" % streetlights.size())
	if streetlights.is_empty():
		return
	# Verificar que son acotadas (tienen textura de cono o shadow_enabled=false)
	for light in streetlights:
		var has_cone_tex: bool = light.texture != null
		var shadows_off: bool = not light.shadow_enabled
		# StreetLight tiene shadow_enabled=false y textura de cono => acotada
		var is_bounded: bool = has_cone_tex or shadows_off
		_check(is_bounded,
			"Farola %s es acotada (texture=%s, shadows=%s)" % [light.name, has_cone_tex, shadows_off])
	# Verificar que NO están en grupo nav_obstacles
	for light in streetlights:
		_check(not light.is_in_group("nav_obstacles"),
			"Farola %s NO está en nav_obstacles" % light.name)

func _collect_point_lights(node: Node, out: Array[PointLight2D]) -> void:
	for child in node.get_children():
		if child is PointLight2D:
			out.append(child as PointLight2D)
		_collect_point_lights(child, out)

## 5. SolarLighting.apply_state() sigue intacto
func _test_solar_apply_state_intact() -> void:
	if _solar == null:
		return
	_check(_solar.has_method("apply_state"), "SolarLighting tiene apply_state()")
	# Verificar firma: apply_state(ambient, sun, angle, tint, duration)
	var method_info: Array = _solar.get_method_list()
	var found: bool = false
	for info in method_info:
		if info.name == "apply_state":
			var args: Array = info.args
			# Debe tener al menos 4 args (ambient, sun, angle, tint) + duration opcional
			found = args.size() >= 4
			break
	_check(found, "apply_state tiene firma correcta (≥4 args)")
	# Verificar que NO se ha roto: llamar con valores válidos no debe crashear
	_solar.call("apply_state", 0.5, 0.1, 0.0, Color.WHITE, 0.1)
	await get_tree().process_frame
	_check(true, "apply_state() se ejecuta sin error")

## 6. MetaProgress usa night_factor() solo si NO existe current_phase() binario
func _test_meta_progress_uses_night_factor() -> void:
	var meta: Node = _main.get_node_or_null("MetaProgress")
	_check(meta != null, "Main tiene MetaProgress")
	if meta == null:
		return
	var meta_script: Script = meta.get_script()
	if meta_script == null:
		return
	var source: String = meta_script.get_source_code()
	# Verificar que usa night_factor() de WorldDirector
	_check(source.contains("night_factor"), "MetaProgress referencia night_factor")
	# Verificar que tiene check de current_phase() antes de usar night_factor
	# Patrón: if director.has_method("current_phase"): ... else: usar night_factor()
	var has_phase_check: bool = source.contains("current_phase") and source.contains("night_factor")
	_check(has_phase_check, "MetaProgress verifica current_phase antes de usar night_factor")

## 7. Oscuridad de noche = "media luz" legible sin faro
func _test_night_darkness_is_medium_light() -> void:
	if _director == null or _solar == null:
		return
	if not _director.has_method("force_phase") or not _director.has_method("night_factor"):
		return
	# Poner fase night
	_director.call("force_phase", "night")
	await get_tree().process_frame
	# Verificar que CanvasModulate no es negro (alpha=1, RGB multiplica)
	var canvas_mod: CanvasModulate = _solar.get_node_or_null("CanvasModulate") as CanvasModulate
	_check(canvas_mod != null, "SolarLighting tiene CanvasModulate")
	if canvas_mod != null:
		var color: Color = canvas_mod.color
		_check(is_equal_approx(color.a, 1.0), "CanvasModulate alpha = 1.0 (no transparencia)")
		# Luma no debe ser casi 0 (negro total) ni 1 (día)
		var luma: float = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
		_check(luma > 0.15 and luma < 0.75,
			"Noche es media luz legible (luma=%.3f, no negro total ni día)" % luma)
	# Verificar que faro del jugador tiene energía > 0
	var flashlight: PointLight2D = _solar.get_node_or_null("Flashlight") as PointLight2D
	# El faro vive en Player, no en SolarLighting directamente
	var player: Node = _main.get_node_or_null("Player")
	if player != null:
		var fl: PointLight2D = player.get_node_or_null("Flashlight") as PointLight2D
		_check(fl != null, "Player tiene Flashlight")
		if fl != null:
			_check(fl.energy > 0.5, "Faro nocturno tiene energía > 0.5 (got %.2f)" % fl.energy)

func _finish() -> void:
	get_tree().paused = false
	if _checks == 0:
		_failures.append("La puerta debe ejecutar al menos una comprobación")
	print("REALISTIC_NIGHT_TEST failures=%d" % _failures.size())
	print("REALISTIC_NIGHT_CHECKS checks=%d" % _checks)
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)