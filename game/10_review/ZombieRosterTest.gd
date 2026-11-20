extends Node
## ============================================================================
## ZOMBIE ROSTER TEST (R3) — el juego tiene UN SOLO arquetipo de zombi.
## ============================================================================
## El usuario pidió eliminar todos los zombis menos el normal (WALKER, el que
## lleva la skin pixel-art) y spawnear más normales para compensar la
## descompensación que dejan los arquetipos eliminados.
##
## Contrato que este arnés fija:
##
##   1. `Zombie.Kind` y `ZombieVisual.ZombieType` solo tienen WALKER y BOSS.
##      "Tanque Alfa" NO es un arquetipo distinto: es un PERFIL del mismo
##      zombi (mismo arte, más grande, más vida, barra de jefe, carga+slam).
##      Así se conserva el encuentro con el jefe, el meta-árbol v2 y la
##      extracción de 12 s sin reintroducir una familia de zombis.
##   2. Todos los spawners producen WALKER: barrio, bosque y horda.
##   3. La cantidad de zombis sube para compensar (barrio >= 42, bosque >= 9,
##      horda base >= 4, horda maxima >= 14).
##   4. El WALKER conserva sus stats (68 HP, 80 px/s, deteccion 430->520).
##   5. El jefe conserva vida alta, barra visible y la MISMA skin.
##   6. La telegrafia sonora solo distingue walker y jefe.
##
## Control negativo: con el roster anterior (RUNNER/TANK/SPITTER/SCREAMER)
## este arnés falla en los puntos 1, 2, 3 y 6.
## ============================================================================

const ZOMBIE_SCRIPT: String = "res://03_zombies/Zombie.gd"
const ZOMBIE_VISUAL_SCRIPT: String = "res://03_zombies/ZombieVisual.gd"
const ZOMBIE_SCENE: String = "res://03_zombies/Zombie.tscn"
const MAIN_SCRIPT: String = "res://07_house/Main.gd"
const NEIGHBORHOOD_SCRIPT: String = "res://05_house/Neighborhood.gd"
const FOREST_ZOMBIES_SCRIPT: String = "res://11_forest/ForestZombies.gd"
const WORLD_DIRECTOR_SCRIPT: String = "res://01_core/WorldDirector.gd"
const AUDIO_SCRIPT: String = "res://13_audio/AudioDirector.gd"

## Nombres de arquetipo que NO deben volver a existir en el codigo.
const DEAD_ARCHETYPES: Array[String] = ["RUNNER", "SPITTER", "SCREAMER", "TANK"]

var _failures: Array[String] = []
var _instances: Array[Node] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## Quita los comentarios `#` del codigo fuente (respetando comillas) para que
## la documentacion pueda NOMBRAR los arquetipos eliminados (que es
## justamente lo que hay que hacer) sin que el arnes lo tome por codigo vivo.
func _strip_comments(src: String) -> String:
	var out: String = ""
	var in_string: bool = false
	var quote: String = ""
	var i: int = 0
	while i < src.length():
		var ch: String = src[i]
		if in_string:
			out += ch
			if ch == "\\" and i + 1 < src.length():
				out += src[i + 1]
				i += 2
				continue
			if ch == quote:
				in_string = false
			i += 1
			continue
		if ch == "\"" or ch == "'":
			in_string = true
			quote = ch
			out += ch
			i += 1
			continue
		if ch == "#":
			while i < src.length() and src[i] != "\n":
				i += 1
			continue
		out += ch
		i += 1
	return out


func _constants(path: String) -> Dictionary:
	var script: Script = load(path)
	if script == null:
		return {}
	return script.get_script_constant_map()


func _ready() -> void:
	await get_tree().process_frame
	_enum_checks()
	_spawner_checks()
	_amount_checks()
	# `await` IMPORTANTE: `_runtime_checks()`.awaita frames. Sin el, `_finish()`
	# liberaria el zombi mientras la corrutina esta suspendida y las llamadas
	# posteriores fallarian con "previously freed instance".
	await _runtime_checks()
	await _boss_spawn_checks()
	await _finish()


func _enum_checks() -> void:
	var zombie_consts: Dictionary = _constants(ZOMBIE_SCRIPT)
	var kind: Dictionary = zombie_consts.get("Kind", {}) as Dictionary
	_check(kind.has("WALKER"), "Zombie.Kind declara WALKER")
	_check(kind.has("BOSS"), "Zombie.Kind declara BOSS (Tanque Alfa como perfil)")
	for dead in DEAD_ARCHETYPES:
		_check(not kind.has(dead), "Zombie.Kind ya no declara %s" % dead)
	_check(kind.size() == 2, "Zombie.Kind tiene exactamente 2 entradas (WALKER, BOSS)")

	var visual_consts: Dictionary = _constants(ZOMBIE_VISUAL_SCRIPT)
	var ztype: Dictionary = visual_consts.get("ZombieType", {}) as Dictionary
	_check(ztype.has("WALKER"), "ZombieVisual.ZombieType declara WALKER")
	_check(ztype.has("BOSS"), "ZombieVisual.ZombieType declara BOSS")
	for dead in DEAD_ARCHETYPES:
		_check(not ztype.has(dead), "ZombieVisual.ZombieType ya no declara %s" % dead)
	_check(ztype.size() == 2, "ZombieVisual.ZombieType tiene exactamente 2 entradas")

	# El codigo no debe conservar ni el nombre ni las ramas de los
	# arquetipos eliminados (ni siquiera como codigo muerto). Los COMENTARIOS
	# si pueden nombrarlos (documentan la decision), asi que se eliminan antes
	# de comprobar.
	var sources: String = _strip_comments(
		_read(ZOMBIE_SCRIPT) + _read(ZOMBIE_VISUAL_SCRIPT)
		+ _read(MAIN_SCRIPT) + _read(FOREST_ZOMBIES_SCRIPT)
		+ _read(WORLD_DIRECTOR_SCRIPT) + _read(AUDIO_SCRIPT))
	for dead in DEAD_ARCHETYPES:
		_check(not sources.contains(dead),
			"ningun fuente conserva el arquetipo eliminado %s" % dead)


func _spawner_checks() -> void:
	var main_src: String = _read(MAIN_SCRIPT)
	_check(not main_src.contains("type_weights"),
		"Main._spawn_zombies() ya no reparte por pesos de arquetipo")
	_check(not main_src.contains("selected_type"),
		"Main._spawn_zombies() ya no selecciona tipo")
	_check(not main_src.contains("BOSS_KIND: int"),
		"Main no usa un indice de jefe magico: lo resuelve del enum del zombi")

	var forest_src: String = _read(FOREST_ZOMBIES_SCRIPT)
	_check(not forest_src.contains("ZOMBIE_KINDS"),
		"ForestZombies ya no tiene una lista de arquetipos")
	_check(not forest_src.contains("set(\"kind\""),
		"ForestZombies no asigna kind: todos usan el WALKER por defecto")

	var director_src: String = _read(WORLD_DIRECTOR_SCRIPT)
	_check(not director_src.contains("HORDE_EARLY_KINDS"),
		"WorldDirector ya no tiene composicion de arquetipos para la horda")
	_check(not director_src.contains("_horde_kind_for"),
		"WorldDirector ya no elige arquetipo por oleada")


func _amount_checks() -> void:
	var neighborhood: Dictionary = _constants(NEIGHBORHOOD_SCRIPT)
	var village: int = int(neighborhood.get("ZOMBIE_SPAWN_COUNT", 0))
	_check(village >= 42, "el barrio spawnea al menos 42 zombis (actual %d)" % village)

	var forest: Dictionary = _constants(FOREST_ZOMBIES_SCRIPT)
	var forest_count: int = int(forest.get("MAX_ZOMBIES", 0))
	_check(forest_count >= 9, "el bosque spawnea al menos 9 zombis (actual %d)" % forest_count)

	var director_script: Script = load(WORLD_DIRECTOR_SCRIPT)
	if director_script != null:
		var director: Node = director_script.new()
		if director != null:
			_check(int(director.get("horde_base_count")) >= 4,
				"la horda base es de al menos 4 zombis")
			_check(int(director.get("horde_max_alive")) >= 14,
				"la horda admite al menos 14 vivos simultaneos")
			director.free()
		else:
			_check(false, "WorldDirector se puede instanciar para leer sus parametros")
	else:
		_check(false, "WorldDirector.gd se puede cargar")


func _runtime_checks() -> void:
	var zombie: Node = load(ZOMBIE_SCENE).instantiate()
	if zombie == null:
		_check(false, "Zombie.tscn se puede instanciar")
		return
	_instances.append(zombie)
	add_child(zombie)
	await get_tree().process_frame
	await get_tree().physics_frame

	var kind_map: Dictionary = (_constants(ZOMBIE_SCRIPT).get("Kind", {}) as Dictionary)
	var walker_kind: int = int(kind_map.get("WALKER", 0))
	var boss_kind: int = int(kind_map.get("BOSS", 1))

	_check(int(zombie.get("kind")) == walker_kind,
		"el zombi por defecto es WALKER")
	_check(not bool(zombie.get("is_boss")), "el zombi por defecto no es jefe")
	_check(is_equal_approx(float(zombie.get("max_hp")), 68.0),
		"el WALKER conserva 68 de vida")
	_check(is_equal_approx(float(zombie.get("speed")), 80.0),
		"el WALKER conserva 80 px/s")
	_check(float(zombie.get("detect_radius")) >= 520.0,
		"el WALKER amplia su radio de deteccion (>= 520)")

	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	_check(visual != null and bool(visual.call("uses_skin")),
		"el WALKER muestra la skin pixel-art")

	# El jefe es el MISMO zombi con otro perfil: mismo arte, mas vida.
	zombie.set("kind", boss_kind)
	zombie.call("_apply_kind")
	await get_tree().process_frame
	_check(bool(zombie.get("is_boss")), "kind=BOSS activa el perfil de jefe")
	_check(float(zombie.get("max_hp")) >= 500.0,
		"el jefe conserva vida alta (>= 500)")
	_check(visual != null and bool(visual.call("uses_skin")),
		"el jefe usa la MISMA skin que el normal (no hay otro arquetipo)")
	var boss_bar: Node = visual.get_node_or_null("boss_bar") if visual != null else null
	_check(boss_bar != null and bool(boss_bar.get("visible")),
		"el jefe muestra su barra de vida")
	# Las habilidades de arquetipo desaparecen del CONTRATO del zombi: las
	# propiedades/exportadas se eliminan (no se dejan a 0 como codigo muerto).
	var props: Array[String] = []
	for info in zombie.get_property_list():
		props.append(String(info.get("name", "")))
	_check(not props.has("spit_range") and not props.has("scream_radius"),
		"no quedan propiedades de escupitajo ni de grito")
	_check(not props.has("spit_damage") and not props.has("scream_cooldown"),
		"no quedan propiedades de dano de escupitajo ni de cooldown de grito")

	# La telegrafia sonora solo distingue walker y jefe.
	var audio_consts: Dictionary = _constants(AUDIO_SCRIPT)
	var telegraph: Dictionary = audio_consts.get("TELEGRAPH_SFX", {}) as Dictionary
	_check(telegraph.size() == 2, "la tabla de telegrafia tiene 2 entradas (walker, jefe)")
	_check(telegraph.has(walker_kind) and telegraph.has(boss_kind),
		"la tabla de telegrafia cubre walker y jefe")


## ---------------------------------------------------------------------------
## El spawn real del jefe: el indice de `Zombie.Kind.BOSS` NO puede ser un
## numero magico. En R3 el enum paso de 6 entradas (WALKER=0, RUNNER=1,
## TANK=2, SPITTER=3, SCREAMER=4, BOSS=5) a 2 (WALKER=0, BOSS=1) y el
## `BOSS_KIND = 5` de Main.gd dejo de ser valido: el Tanque Alfa spawneaba
## como un zombi SIN perfil (sin vida de jefe, sin barra, sin carga ni slam),
## y el fallo era INVISIBLE porque ningun arnes miraba el indice.
## ---------------------------------------------------------------------------
func _boss_spawn_checks() -> void:
	var main: Node = load("res://07_house/Main.tscn").instantiate()
	if main == null:
		_check(false, "Main.tscn se puede instanciar para el spawn del jefe")
		return
	_instances.append(main)
	get_tree().root.add_child(main)
	for i in range(6):
		await get_tree().process_frame

	var boss: Node = null
	if main.has_method("spawn_boss"):
		boss = main.call("spawn_boss", Vector2(600.0, 600.0))
	_check(boss != null, "Main.spawn_boss() devuelve un zombi")
	if boss == null:
		return
	_check(bool(boss.get("is_boss")),
		"el jefe spawneado activa el PERFIL de jefe (kind = Kind.BOSS real)")
	_check(float(boss.get("max_hp")) >= 500.0,
		"el jefe spawneado conserva la vida alta (%.0f)" % float(boss.get("max_hp")))
	var visual: Node = boss.get_node_or_null("ZombieVisual")
	var bar: Node = visual.get_node_or_null("boss_bar") if visual != null else null
	_check(bar != null and bool(bar.get("visible")),
		"el jefe spawneado muestra su barra de vida")
	_check(visual != null and bool(visual.call("uses_skin")),
		"el jefe spawneado usa la MISMA skin que el caminante")


func _finish() -> void:
	for node in _instances:
		if is_instance_valid(node):
			node.queue_free()
	_instances.clear()
	for i in range(4):
		await get_tree().process_frame
	print("ZOMBIE_ROSTER_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
	for f in _failures:
		assert(false, "ZOMBIE_ROSTER_TEST: " + f)
