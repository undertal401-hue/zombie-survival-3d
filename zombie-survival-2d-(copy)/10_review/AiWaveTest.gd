extends Node
## ============================================================================
## AI WAVE TEST (Fase 3 + R3 / ADR-006) — dificultad, PERFILES, botín y hordas.
## ============================================================================
## R3 (ADR-006) deja UN SOLO arquetipo de zombi (el caminante) mas el perfil
## de jefe "Tanque Alfa". Este arnés deja de exigir perfiles por arquetipo y
## pasa a exigir el contrato nuevo:
##
##   1. La dificultad unificada sigue igual (horda x1.0..x1.8, daño x1.0..x1.45).
##   2. El caminante conserva su perfil táctico (flanqueo 0.18, separación 1.0).
##   3. El perfil de jefe tiene el suyo (sin flanqueo, separación 2.2, 800 HP).
##   4. El botín se reparte por RIESGO: el jefe asegura 5-8 de chatarra y el
##      caminante normal suelta como mucho 1 pieza.
##   5. La horda es HOMOGENEA: todos sus miembros son caminantes (Kind 0).
## ============================================================================

const ZOMBIE_SCRIPT: String = "res://03_zombies/Zombie.gd"
const WORLD_DIRECTOR_SCRIPT: String = "res://01_core/WorldDirector.gd"

var _failures: Array[String] = []
var _main: Node


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_main = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	for i in range(10):
		await get_tree().process_frame

	await _difficulty_checks()
	await _profile_checks()
	await _loot_checks()
	await _horde_checks()
	await _finish()


# --- 1. Unificación de dificultad --------------------------------------------
func _difficulty_checks() -> void:
	var previous: float = GameState.difficulty()
	GameState.set_difficulty(0.0)
	_check(is_equal_approx(GameState.multiplier(&"horde"), 1.0), "horda x1.0 al inicio")
	_check(is_equal_approx(GameState.multiplier(&"zombie", &"damage"), 1.0),
		"daño zombi x1.0 al inicio")
	GameState.set_difficulty(1.0)
	_check(is_equal_approx(GameState.multiplier(&"horde"), 1.8), "horda x1.8 al máximo")
	_check(is_equal_approx(GameState.multiplier(&"zombie", &"damage"), 1.45),
		"daño zombi x1.45 al máximo")
	GameState.set_difficulty(previous)


# --- 2. Perfiles tácticos: caminante y jefe ----------------------------------
func _profile_checks() -> void:
	var scene: PackedScene = load("res://03_zombies/Zombie.tscn") as PackedScene
	var kinds: Dictionary = _kind_map()
	var walker: int = int(kinds.get("WALKER", 0))
	var boss: int = int(kinds.get("BOSS", 1))

	var walker_z: Node2D = scene.instantiate() as Node2D
	get_tree().root.add_child(walker_z)
	walker_z.set("kind", walker)
	walker_z.call("_apply_kind")
	_check(is_equal_approx(float(walker_z.get("flank_strength")), 0.18),
		"el caminante conserva su flanqueo (0.18)")
	_check(is_equal_approx(float(walker_z.get("separation_scale")), 1.0),
		"el caminante conserva su empuje de separación (1.0)")
	_check(is_equal_approx(float(walker_z.get("preferred_range")), 0.0),
		"el caminante va a por el cuerpo a cuerpo")
	walker_z.queue_free()

	var boss_z: Node2D = scene.instantiate() as Node2D
	get_tree().root.add_child(boss_z)
	boss_z.set("kind", boss)
	boss_z.call("_apply_kind")
	_check(is_equal_approx(float(boss_z.get("flank_strength")), 0.0),
		"el jefe no flanquea (va de frente)")
	_check(float(boss_z.get("separation_scale")) > 1.5,
		"el jefe empuja mas en la separación (%.2f)" % float(boss_z.get("separation_scale")))
	_check(float(boss_z.get("max_hp")) >= 500.0,
		"el jefe conserva vida alta (%.0f)" % float(boss_z.get("max_hp")))
	boss_z.queue_free()


# --- 3. Botín por riesgo ------------------------------------------------------
func _loot_checks() -> void:
	var scene: PackedScene = load("res://03_zombies/Zombie.tscn") as PackedScene
	var kinds: Dictionary = _kind_map()
	var boss: int = int(kinds.get("BOSS", 1))
	var walker: int = int(kinds.get("WALKER", 0))

	var boss_z: Node2D = scene.instantiate() as Node2D
	get_tree().root.add_child(boss_z)
	boss_z.set("kind", boss)
	boss_z.call("_apply_kind")
	var scrap_before: int = Inventory.count("scrap")
	boss_z.call("_drop_loot")
	var scrap_after: int = Inventory.count("scrap")
	_check(scrap_after >= scrap_before + 5,
		"el jefe suelta 5-8 de chatarra (%d)" % (scrap_after - scrap_before))
	boss_z.queue_free()

	var walker_z: Node2D = scene.instantiate() as Node2D
	get_tree().root.add_child(walker_z)
	walker_z.set("kind", walker)
	walker_z.call("_apply_kind")
	var scrap_walker_before: int = Inventory.count("scrap")
	var cloth_walker_before: int = Inventory.count("cloth")
	walker_z.call("_drop_loot")
	_check(Inventory.count("scrap") - scrap_walker_before <= 1
			and Inventory.count("cloth") - cloth_walker_before <= 1,
		"el caminante suelta como mucho 1 pieza")
	walker_z.queue_free()


# --- 4. Hordas homogéneas -----------------------------------------------------
func _horde_checks() -> void:
	var director: Node = _main.get_node_or_null("WaveManager")
	_check(director != null, "WaveManager presente")
	var constants: Dictionary = _constants(WORLD_DIRECTOR_SCRIPT)
	var horde_kind: int = int(constants.get("HORDE_KIND", -1))
	_check(horde_kind == 0,
		"la horda es de caminantes (HORDE_KIND = %d)" % horde_kind)
	_check(not constants.has("HORDE_EARLY_KINDS"),
		"la horda ya no se compone por arquetipo")
	_check(director != null and int(director.get("horde_base_count")) >= 4,
		"la horda base es de al menos 4 zombis")
	_check(director != null and int(director.get("horde_max_alive")) >= 14,
		"la horda admite al menos 14 vivos simultaneos")


# --- Utilidades ---------------------------------------------------------------
func _constants(path: String) -> Dictionary:
	var script: Script = load(path)
	if script == null:
		return {}
	return script.get_script_constant_map()


func _kind_map() -> Dictionary:
	return _constants(ZOMBIE_SCRIPT).get("Kind", {}) as Dictionary


func _finish() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
		_main = null
	# Dar tiempo al árbol a liberar el mundo instanciado antes de salir,
	# evitando "ObjectDB instances were leaked at exit" en headless.
	for i in range(3):
		await get_tree().process_frame
	print("AI_WAVE_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# La salida se programa ANTES de los assert: si uno falla en debug el
	# proceso ya tiene su codigo y el CI no puede dar verde aunque el arnes
	# se detenga. En release los asserts se compilan fuera y los _failures
	# de arriba siguen gobernando la salida.
	get_tree().quit(1 if not _failures.is_empty() else 0)
	for f in _failures:
		assert(false, "AI_WAVE_TEST: " + f)
