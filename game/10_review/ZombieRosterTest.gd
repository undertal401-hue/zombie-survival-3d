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
const COMBAT_FX_SCRIPT: String = "res://15_fx/CombatFX.gd"
const GEN_ART_SCRIPT: String = "res://tools/gen_art.py"

## Nombres de arquetipo que NO deben volver a existir en el codigo.
const DEAD_ARCHETYPES: Array[String] = ["RUNNER", "SPITTER", "SCREAMER", "TANK"]
## Marcadores de runtime/arte que tampoco deben sobrevivir. Se comparan en
## minusculas para detectar tanto `RUNNER` como `runner` y las metodos de los
## arquetipos retirados en CombatFX y en el generador canonico.
const DEAD_RUNTIME_TOKENS: Array[String] = [
	"runner", "spitter", "screamer", "tank", "acid spit", "scream wave",
]

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
		# GDScript admite cadenas con comillas simples y dobles. Un `#` dentro
		# de cualquiera de ellas no abre un comentario; un apostrofe dentro de
		# un comentario se ignora porque el bloque `#` se consume entero.
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
	_audio_checks()
	# `await` IMPORTANTE: `_runtime_checks()`.awaita frames. Sin el, `_finish()`
	# liberaria el zombi mientras la corrutina esta suspendida y las llamadas
	# posteriores fallarian con "previously freed instance".
	await _runtime_checks()
	await _boss_spawn_checks()
	await _finish()


func _enum_checks() -> void:
	# El analizador de comentarios debe respetar AMBAS formas de cadena de
	# GDScript. Godot acepta comillas simples y dobles; un `#` dentro de una
	# cadena simple no es el inicio de un comentario.
	var parser_probe: String = "var marker = 'runner#not-comment'\n# un apostrofo ' no abre cadena\nvar after = 1"
	var parsed_probe: String = _strip_comments(parser_probe)
	_check(parsed_probe.contains("'runner#not-comment'"),
		"el analizador de comentarios respeta cadenas con comillas simples")
	_check(parsed_probe.contains("var after = 1"),
		"un apostrofo dentro de un comentario no oculta el codigo posterior")

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
		+ _read(WORLD_DIRECTOR_SCRIPT) + _read(AUDIO_SCRIPT)
		+ _read(COMBAT_FX_SCRIPT) + _read(GEN_ART_SCRIPT)).to_lower()
	for dead in DEAD_RUNTIME_TOKENS:
		_check(not sources.contains(dead),
			"ningun fuente runtime/arte conserva el arquetipo eliminado %s" % dead)
	var gen_art_source: String = _read(GEN_ART_SCRIPT).to_lower()
	for dead_effect in ["acid spit", "scream wave"]:
		_check(not gen_art_source.contains(dead_effect),
			"gen_art.py no fabrica el efecto retirado %s" % dead_effect)


func _spawner_checks() -> void:
	var main_src: String = _read(MAIN_SCRIPT)
	_check(not main_src.contains("type_weights"),
		"Main._spawn_zombies() ya no reparte por pesos de arquetipo")
	_check(not main_src.contains("selected_type"),
		"Main._spawn_zombies() ya no selecciona tipo")
	_check(not main_src.contains("BOSS_KIND: int"),
		"Main no usa un indice de jefe magico: lo resuelve del enum del zombi")
	_check(not main_src.contains("kinds.get(\"BOSS\", 1)"),
		"Main._boss_kind() no cae al indice magico 1 si falta Kind.BOSS")
	_check(not main_src.contains("kinds.get(\"BOSS\", 0)"),
		"Main._boss_kind() no cae al indice magico 0 si falta Kind.BOSS")
	_check(main_src.contains("_boss_kind_from(kinds)"),
		"Main._boss_kind() usa el resolver _boss_kind_from(kinds)")
	_check(main_src.contains("push_error") and main_src.contains("return -1"),
		"Main._boss_kind() falla de forma abierta si no existe Kind.BOSS")
	_check(main_src.contains("kind < 0"),
		"Main.spawn_boss() rechaza un kind de jefe invalido")

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


func _audio_checks() -> void:
	var audio_script: Script = load(AUDIO_SCRIPT)
	if audio_script == null:
		_check(false, "AudioDirector.gd se puede cargar")
		return
	var audio: Node = audio_script.new()
	if audio == null:
		_check(false, "AudioDirector.gd se puede instanciar")
		return

	# Un payload de una instancia liberada no puede tocarse con `is` antes de
	# comprobar su vigencia. Estos casos cubren Node2D, Node y Object, que son
	# los tres tipos que el bus puede haber dejado en una referencia antigua.
	var freed_node2d: Node2D = Node2D.new()
	var freed_node2d_value: Variant = freed_node2d
	freed_node2d.free()
	var freed_node: Node = Node.new()
	var freed_node_value: Variant = freed_node
	freed_node.free()
	var freed_object: Object = Object.new()
	var freed_object_value: Variant = freed_object
	freed_object.free()

	_check(audio.call("_as_position", freed_node2d_value) == null,
		"AudioDirector ignora una posicion Node2D liberada")
	_check(audio.call("_as_position", freed_node_value) == null,
		"AudioDirector ignora una posicion Node liberada")
	_check(audio.call("_as_position", freed_object_value) == null,
		"AudioDirector ignora una posicion Object liberada")
	_check(audio.call("_weapon_sfx_id", freed_node_value) == "pistol",
		"AudioDirector ignora un weapon liberado")
	audio.call("_on_bus_vehicle_state_changed", freed_node2d_value, 10.0, 10.0)

	# La comprobacion estatica fija el orden seguro que Godot exige: la
	# vigencia se consulta ANTES de clasificar una variante como Node/Node2D.
	# Si alguien invierte esas llamadas, el suite vuelve a fallar aunque el
	# caso de Node2D concreto no se haya ejecutado en este proceso.
	var audio_src: String = _read(AUDIO_SCRIPT)
	for unsafe_pattern in [
			"found is Node2D", "vehicle is Node2D", "candidate is Node2D",
			"node is Node2D", "weapon is Object",
	]:
		_check(not audio_src.contains(unsafe_pattern),
			"AudioDirector no clasifica una instancia liberada antes de validarla: %s"
				% unsafe_pattern)
	var live_helper_at: int = audio_src.find("func _is_live_node2d")
	var live_check_at: int = audio_src.find("_is_live_object(value)", live_helper_at)
	var type_check_at: int = audio_src.find("value is Node2D", live_helper_at)
	_check(live_helper_at >= 0 and live_check_at >= live_helper_at
			and type_check_at > live_check_at,
		"AudioDirector valida un Node2D antes de usar is sobre el")
	var engine_poll_at: int = audio_src.find("func _update_engine_poll")
	var engine_candidate_at: int = audio_src.find("_is_live_node2d(node)", engine_poll_at)
	_check(engine_poll_at >= 0 and engine_candidate_at > engine_poll_at,
		"AudioDirector valida los candidatos del grupo antes de clasificarlos")

	var kind_map: Dictionary = (_constants(ZOMBIE_SCRIPT).get("Kind", {}) as Dictionary)
	var walker_kind: int = int(kind_map.get("WALKER", 0))
	var boss_kind: int = int(kind_map.get("BOSS", 1))
	var audio_consts: Dictionary = _constants(AUDIO_SCRIPT)
	var telegraph: Dictionary = audio_consts.get("TELEGRAPH_SFX", {}) as Dictionary
	_check(telegraph.has(&"walker") and telegraph.has(&"boss"),
		"la telegrafia se identifica semanticamente como walker/boss")
	_check(not telegraph.has(walker_kind) and not telegraph.has(boss_kind),
		"la telegrafia no usa los ordinales del enum como claves")
	_check(audio.has_method("_telegraph_preset"),
		"AudioDirector resuelve la telegrafia mediante una tabla semantica")
	if audio.has_method("_telegraph_preset"):
		var walker_preset: Dictionary = audio.call("_telegraph_preset", &"walker") as Dictionary
		var boss_preset: Dictionary = audio.call("_telegraph_preset", &"boss") as Dictionary
		var boss_from_enum: Dictionary = audio.call("_telegraph_preset", boss_kind) as Dictionary
		var walker_from_enum: Dictionary = audio.call("_telegraph_preset", walker_kind) as Dictionary
		_check(String(walker_preset.get("id", "")) == "footstep",
			"la API semantica reproduce el efecto de walker")
		_check(String(boss_preset.get("id", "")) == "horde_alert",
			"la API semantica reproduce el efecto de boss")
		_check(String(boss_from_enum.get("id", "")) == "horde_alert",
			"la compatibilidad int resuelve boss desde Zombie.Kind")
		_check(String(walker_from_enum.get("id", "")) == "footstep",
			"la compatibilidad int resuelve walker desde Zombie.Kind")
	audio.free()


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

	# El roster tambien se aplica a la capa de efectos: el indice real de
	# Kind.BOSS debe clasificarse como `boss`, nunca como un arquetipo retirado.
	var combat_script: Script = load(COMBAT_FX_SCRIPT)
	if combat_script != null:
		var combat: Node = combat_script.new()
		if combat != null:
			add_child(combat)
			_instances.append(combat)
			_check(combat.call("_normalize_zombie_kind", boss_kind) == &"boss",
				"CombatFX clasifica Kind.BOSS como boss")
			_check(combat.call("_normalize_zombie_kind", walker_kind) == &"walker",
				"CombatFX clasifica Kind.WALKER como walker")

			# Un objeto liberado puede llegar desde una referencia antigua. El
			# guard debe comprobar `is_instance_valid` ANTES de usar `is Node`;
			# al revés, Godot aborta la funcion con "previously freed instance".
			var freed_node: Node = Node.new()
			var freed_value: Variant = freed_node
			freed_node.free()
			_check(combat.call("_normalize_surface", freed_value) == &"concrete",
				"CombatFX tolera una superficie de instancia liberada")
			_check(combat.call("_normalize_zombie_kind", freed_value) == &"walker",
				"CombatFX tolera un perfil de zombi de instancia liberada")

			# El color no se deduce solo de la clasificacion: se comprueba la
			# particula realmente emitida para cada perfil del enum.
			var fx_consts: Dictionary = combat_script.get_script_constant_map()
			var amber_type: int = int(fx_consts.get("PART_BLOOD_AMBER", -1))
			var green_type: int = int(fx_consts.get("PART_BLOOD_GREEN", -1))
			combat.call("spawn_blood", Vector2.ZERO, boss_kind)
			var amber_seen: bool = false
			var amber_color_ok: bool = false
			var particles: Array = combat.get("_particles") as Array
			for data in particles:
				var particle: Dictionary = data as Dictionary
				if not bool(particle.get("active", false)) \
						or int(particle.get("type", -1)) != amber_type:
					continue
				amber_seen = true
				var amber: Color = particle.get("color", Color.TRANSPARENT) as Color
				amber_color_ok = is_equal_approx(amber.r, 0.96) \
						and is_equal_approx(amber.g, 0.56) \
						and is_equal_approx(amber.b, 0.12)
			_check(amber_seen and amber_color_ok,
				"CombatFX emite sangre AMBAR para el perfil Kind.BOSS")

			combat.call("spawn_blood", Vector2.ZERO, walker_kind)
			var green_seen: bool = false
			var green_color_ok: bool = false
			particles = combat.get("_particles") as Array
			for data in particles:
				var particle: Dictionary = data as Dictionary
				if not bool(particle.get("active", false)) \
						or int(particle.get("type", -1)) != green_type:
					continue
				green_seen = true
				var green: Color = particle.get("color", Color.TRANSPARENT) as Color
				green_color_ok = is_equal_approx(green.r, 0.24) \
						and is_equal_approx(green.g, 0.74) \
						and is_equal_approx(green.b, 0.20)
			_check(green_seen and green_color_ok,
				"CombatFX emite sangre VERDE para el perfil Kind.WALKER")
		else:
			_check(false, "CombatFX.gd se puede instanciar")
	else:
		_check(false, "CombatFX.gd se puede cargar")

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

	# La telegrafia sonora solo distingue walker y jefe mediante nombres
	# semanticos; sus ordinales se resuelven desde Zombie.Kind al vuelo.
	var audio_consts: Dictionary = _constants(AUDIO_SCRIPT)
	var telegraph: Dictionary = audio_consts.get("TELEGRAPH_SFX", {}) as Dictionary
	_check(telegraph.size() == 2, "la tabla de telegrafia tiene 2 entradas (walker, jefe)")
	_check(telegraph.has(&"walker") and telegraph.has(&"boss"),
		"la tabla de telegrafia cubre semanticamente walker y jefe")


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

	# Se prueba la RUTA REAL con un mapa SIN Kind.BOSS. `report_error=false`
	# evita deliberar `push_error` en CI, pero no cambia como se resuelve el
	# enum: el fallo abierto debe seguir siendo -1.
	var invalid_boss_kind: int = -1
	var invalid_route_called: bool = false
	var boss_kind_accepts_test_args: bool = false
	for method_info in main.get_method_list():
		if String(method_info.get("name", "")) == "_boss_kind":
			boss_kind_accepts_test_args = (method_info.get("args", []) as Array).size() >= 2
			break
	_check(boss_kind_accepts_test_args,
		"Main._boss_kind() admite override y control de error")
	if boss_kind_accepts_test_args:
		invalid_route_called = true
		invalid_boss_kind = int(main.call("_boss_kind", {}, false))
	_check(invalid_route_called and invalid_boss_kind == -1,
		"Main._boss_kind({}, false) se ejecuta y falla abierto si falta BOSS")

	# Un indice resuelto invalido no debe crear un jefe ni consumir la oleada.
	# `spawn_boss()` resuelve el enum y delega aqui, asi que esta es la misma
	# ruta de creacion que usa la API publica.
	var invalid_boss: Node = null
	if main.has_method("_spawn_boss_with_kind"):
		invalid_boss = main.call("_spawn_boss_with_kind", Vector2(600.0, 600.0), invalid_boss_kind)
	_check(invalid_boss == null,
		"Main aborta el spawn cuando Kind.BOSS no se puede resolver")
	_check(int(main.get("_boss_spawned_wave")) == -1,
		"el jefe invalido no consume la oleada de aparicion")

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
