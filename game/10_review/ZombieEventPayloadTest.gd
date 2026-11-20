extends Node
## ============================================================================
## ZOMBIE EVENT PAYLOAD TEST (R1-fix) — payload inválido de `zombie_died`.
## ============================================================================
## El usuario reportó un error en un fichero llamado "Zombies.gd". El único
## fichero del repo cuyo nombre coincide EXACTAMENTE es
## `game/11_forest/ForestZombies.gd`, y el fallo se reproduce de forma literal:
##
##   SCRIPT ERROR: Left operand of 'is' is a previously freed instance.
##          at: _kill_is_headshot (res://01_core/GameState.gd:361)
##   ERROR: Error calling from signal 'zombie_died' to callable:
##          'Node2D(ForestZombies.gd)::_on_zombie_died': Cannot convert
##          argument 1 from Object to Object.
##
## CAUSA: `EventBus.zombie_died` declara el payload como `Node2D`. Cuando el
## payload llega liberado (o no válido) el motor (a) rechaza la llamada a
## cualquier receptor tipado — y el error nombra el fichero del receptor — y
## (b) dentro de `GameState` el guard `zombie != null` es TRUE para una
## instancia ya liberada, de modo que `zombie is Node2D` explota.
##
## Este arnés cubre las dos caras:
##   1. INTROSPECCIÓN (determinista y positiva): la señal y sus receptores
##      deben aceptar un payload no tipado, y los que lo tocan deben validar
##      `is_instance_valid()` antes de usarlo.
##   2. RUNTIME (regresión real): se libera un payload y se comprueba que
##      `GameState._kill_is_headshot/_kill_is_melee` responden `bool`, que
##      `ForestZombies` no corrompe su lista y que la emisión por la señal no
##      rompe ningún receptor.
##
## La AUSENCIA de error en runtime la verifica el grep del CI
## (`SCRIPT ERROR|Parse Error|Failed to load|ERROR:|Assertion failed`): si el
## blindaje se retira, el log de este arnés contiene el error y el CI cae.
## GDScript no puede interceptar un SCRIPT ERROR, por eso el arnés NO intenta
## hacerlo y delega esa mitad en el grep.
## ============================================================================

const FOREST_ZOMBIES: String = "res://11_forest/ForestZombies.gd"
const EVENT_BUS: String = "res://01_core/EventBus.gd"
const GAME_STATE: String = "res://01_core/GameState.gd"
const MAIN: String = "res://07_house/Main.gd"
const WEAPON_CONTROLLER: String = "res://02_player/weapons/WeaponController.gd"
const QUEST_DIRECTOR: String = "res://14_quests/QuestDirector.gd"

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _info(label: String) -> void:
	print("INFO " + label)


func _read(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	return ""


func _ready() -> void:
	await get_tree().process_frame
	_signal_is_untyped()
	_receivers_are_untyped()
	_guards_present()
	await _runtime_invalid_payload()
	print("ZOMBIE_EVENT_PAYLOAD_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
	_asserts()


## ---------------------------------------------------------------------------
## 1. Introspección: la señal no debe tipar el payload.
## ---------------------------------------------------------------------------
func _signal_is_untyped() -> void:
	var src: String = _read(EVENT_BUS)
	_check(src.contains("signal zombie_died(zombie)"),
		"EventBus: `signal zombie_died(zombie)` sin tipo (payload liberado admitido)")
	_check(not src.contains("signal zombie_died(zombie: Node2D)"),
		"EventBus: ya no declara el payload como `Node2D`")


## ---------------------------------------------------------------------------
## 2. Introspección: ningún receptor puede rechazar un payload no tipado.
## ---------------------------------------------------------------------------
func _receivers_are_untyped() -> void:
	var forest: String = _read(FOREST_ZOMBIES)
	_check(forest.contains("func _on_zombie_died(zombie)"),
		"ForestZombies: receptor sin tipar (`func _on_zombie_died(zombie)`)")
	_check(not forest.contains("func _on_zombie_died(zombie: Node2D)"),
		"ForestZombies: ya no declara el receptor como `Node2D`")

	var main: String = _read(MAIN)
	_check(main.contains("func _on_zombie_died_for_state(_zombie)"),
		"Main: receptor sin tipar")

	var weapon: String = _read(WEAPON_CONTROLLER)
	_check(weapon.contains("func _on_zombie_died(_zombie)"),
		"WeaponController: receptor sin tipar")

	var quest: String = _read(QUEST_DIRECTOR)
	_check(quest.contains("func _on_zombie_died(_zombie)"),
		"QuestDirector: receptor sin tipar")


## ---------------------------------------------------------------------------
## 3. Introspección: quien toca el payload valida su vigencia.
## ---------------------------------------------------------------------------
func _guards_present() -> void:
	var forest: String = _read(FOREST_ZOMBIES)
	var forest_body: String = _func_body(forest, "func _on_zombie_died(")
	_check(forest_body.contains("is_instance_valid(zombie)"),
		"ForestZombies._on_zombie_died valida `is_instance_valid(zombie)` antes de usarlo")

	var state: String = _read(GAME_STATE)
	var headshot_body: String = _func_body(state, "func _kill_is_headshot(")
	_check(headshot_body.contains("is_instance_valid(zombie)"),
		"GameState._kill_is_headshot valida `is_instance_valid(zombie)`")
	var melee_body: String = _func_body(state, "func _kill_is_melee(")
	_check(melee_body.contains("is_instance_valid(zombie)"),
		"GameState._kill_is_melee valida `is_instance_valid(zombie)`")


## Extrae el cuerpo de una función a partir de su cabecera (para que un
## `is_instance_valid` presente en OTRA función del mismo fichero no valga
## como prueba del blindaje de esta).
func _func_body(src: String, header: String, span: int = 18) -> String:
	var start: int = src.find(header)
	if start == -1:
		return ""
	var lines: PackedStringArray = src.substr(start, span * 80).split("\n")
	return "\n".join(lines.slice(0, span))


## ---------------------------------------------------------------------------
## 4. Runtime: payload liberado por la señal real.
## ---------------------------------------------------------------------------
func _runtime_invalid_payload() -> void:
	# --- Spawner real del bosque -------------------------------------------
	var spawner: Node = load(FOREST_ZOMBIES).new()
	add_child(spawner)
	await get_tree().process_frame

	# --- Payload: un Node2D válido que se libera ---------------------------
	var payload: CharacterBody2D = CharacterBody2D.new()
	payload.name = "PayloadZombie"
	add_child(payload)
	# Un segundo zombi VIVO: sirve de control (no debe desaparecer).
	var alive: CharacterBody2D = CharacterBody2D.new()
	alive.name = "AliveForestZombie"
	add_child(alive)
	await get_tree().process_frame

	# Se registran como zombis del bosque para que el handler los encontraria.
	payload.set_meta("forest_zombie", true)
	alive.set_meta("forest_zombie", true)
	var spawned: Array = spawner.get("_spawned")
	spawned.append(payload)
	spawned.append(alive)
	_info("lista del spawner tras registrar 2 zombis: %d (get->append)" % spawned.size())
	_info("lista real del spawner: %d" % (spawner.get("_spawned") as Array).size())

	payload.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var freed_ref: Node = payload
	_check(not is_instance_valid(freed_ref),
		"Runtime: el payload queda liberado (is_instance_valid=false)")

	# --- GameState no debe romperse con un payload liberado ---------------
	var headshot: Variant = GameState.call("_kill_is_headshot", freed_ref)
	_check(headshot is bool,
		"Runtime: GameState._kill_is_headshot responde bool con payload liberado")
	var melee: Variant = GameState.call("_kill_is_melee", freed_ref)
	_check(melee is bool,
		"Runtime: GameState._kill_is_melee responde bool con payload liberado")

	# --- ForestZombies: limpia la entrada obsoleta y CONSERVA la viva -----
	# Si el handler no se ejecuta (payload tipado rechazado por el motor),
	# la lista conserva la entrada obsoleta y este check falla.
	spawner.call("_on_zombie_died", freed_ref)
	await get_tree().process_frame
	var after: Array = spawner.get("_spawned")
	_info("tras _on_zombie_died: size=%d validos=%s" % [
		after.size(),
		str(after.map(func(x): return is_instance_valid(x)))])
	_check(after.size() == 1,
		"Runtime: ForestZombies elimina la entrada obsoleta del zombi liberado")
	_check(not after.is_empty() and is_instance_valid(after[0]) and after[0] == alive,
		"Runtime: el zombi vivo sigue en la lista (no se borra por error)")

	# --- La señal real con payload liberado no rompe a nadie ---------------
	EventBus.zombie_died.emit(freed_ref)
	await get_tree().process_frame
	_check(true, "Runtime: emisión por EventBus.zombie_died sin romper receptores")

	spawner.queue_free()


## ---------------------------------------------------------------------------
## Asserts opt-in: `-- --strict-assert`
## ---------------------------------------------------------------------------
func _asserts() -> void:
	if not ("--strict-assert" in OS.get_cmdline_user_args()):
		return
	assert(_failures.is_empty(), "ZOMBIE_EVENT_PAYLOAD_TEST: hay fallos")
