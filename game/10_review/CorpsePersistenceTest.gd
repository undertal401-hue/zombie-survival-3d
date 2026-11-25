extends Node
## ============================================================================
## CORPSE PERSISTENCE TEST — cadáveres durante dos días de juego.
## ============================================================================
## El plazo es de DOS ciclos completos de WorldDirector. Con el valor
## production de 300 s, el cadáver debe permanecer 600 s de mundo activo.
## El menú principal forma parte de ese mundo activo; una pausa normal del
## árbol lo congela. El test usa el reloj absoluto de GameState para evitar
## esperas reales de diez minutos y conserva pruebas de integración reales
## para bosque, horda, colisión, IA, señal de muerte y propietario persistente.
## ============================================================================

const MAIN_SCENE: PackedScene = preload("res://07_house/Main.tscn")
const ZOMBIE_SCENE: PackedScene = preload("res://03_zombies/Zombie.tscn")

const CORPSE_LIFETIME_CYCLES: float = 2.0
const DEFAULT_CYCLE_SECONDS: float = 300.0
const CORPSE_ROOT_NAME: String = "Corpses"
const CORPSE_ROOT_GROUP: StringName = &"corpse_root"
const CORPSE_GROUP: StringName = &"corpses"

var _failures: Array[String] = []
var _checks: int = 0
var _main: Node = null
var _player: CharacterBody2D = null
var _death_event_count: int = 0


func _ready() -> void:
	# El reloj debe poder comprobarse también con el árbol pausado.
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await _load_main()
	await _test_world_clock_contract()
	await _test_standalone_corpse()
	await _test_pause_does_not_expire_corpse()
	await _test_configurable_cycle_duration()
	await _test_forest_corpse()
	await _test_horde_corpse()
	_finish()


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
	_player = _main.get_node_or_null("Player") as CharacterBody2D
	_check(_main != null, "Main crea el mundo real")
	_check(_player != null, "Main crea el jugador real")
	var corpse_root: Node = _main.get_node_or_null(CORPSE_ROOT_NAME)
	_check(corpse_root != null and corpse_root.is_in_group(CORPSE_ROOT_GROUP),
		"Main crea la raíz persistente de cadáveres")
	# Main no debe cambiar la fase de combate durante esta prueba. El reloj,
	# el director y los ciclos de vida que se verifican siguen siendo reales.
	_main.set_process(false)


## El menú principal no es una pausa: su tiempo resta de la vida del cadáver.
## Una pausa real del árbol, en cambio, congela el epoch absoluto y el ciclo.
func _test_world_clock_contract() -> void:
	var has_epoch: bool = GameState.has_method("world_epoch")
	var has_advance: bool = GameState.has_method("advance_world_epoch")
	var has_cycle: bool = GameState.has_method("world_cycle_seconds")
	var has_set_cycle: bool = GameState.has_method("set_world_cycle_seconds")
	_check(has_epoch, "GameState expone un epoch absoluto del mundo")
	_check(has_advance, "GameState permite avanzar el epoch absoluto de forma controlada")
	_check(has_cycle, "GameState expone la duración canónica del ciclo del mundo")
	_check(has_set_cycle, "GameState permite configurar la duración canónica del ciclo")
	if not has_epoch or not has_advance or not has_cycle or not has_set_cycle:
		return

	var director := _main.get_node_or_null("WaveManager")
	var director_cycle: float = DEFAULT_CYCLE_SECONDS
	if director != null and is_instance_valid(director):
		director_cycle = maxf(float(director.get("cycle_seconds")), 0.001)
	var configured_cycle: float = float(GameState.call("world_cycle_seconds"))
	_check(is_equal_approx(director_cycle, DEFAULT_CYCLE_SECONDS),
		"El ciclo de producción dura 300 segundos")
	_check(is_equal_approx(configured_cycle, director_cycle),
		"GameState y WorldDirector comparten la duración del ciclo")

	GameState.set_phase(GameState.PHASE_MENU)
	var menu_before: float = _world_epoch()
	var run_before: float = GameState.run_clock
	for _i in range(3):
		await get_tree().process_frame
	var menu_after: float = _world_epoch()
	_check(menu_after > menu_before,
		"El tiempo del menú principal cuenta para la vida del cadáver")
	_check(is_equal_approx(GameState.run_clock, run_before),
		"El menú no contamina el cronómetro de la partida")

	get_tree().paused = true
	var paused_before: float = _world_epoch()
	var cycle_before: float = _director_cycle_t()
	for _i in range(3):
		await get_tree().process_frame
	var paused_after: float = _world_epoch()
	_check(is_equal_approx(paused_before, paused_after),
		"La pausa normal del árbol congela el epoch del mundo")
	_check(is_equal_approx(cycle_before, _director_cycle_t()),
		"La pausa normal del árbol congela el ciclo de WorldDirector")
	GameState.call("advance_world_epoch", 10.0)
	_check(is_equal_approx(paused_before, _world_epoch()),
		"El seam de QA no puede saltar el epoch mientras el árbol está pausado")
	get_tree().paused = false
	await get_tree().process_frame
	_check(_world_epoch() > paused_after,
		"El epoch del mundo vuelve a avanzar al reanudar")
	GameState.set_phase(GameState.PHASE_EXPLORE)


## Un zombi muerto conserva el nodo original, deja de ser un actor vivo y
## permanece hasta exactamente death_epoch + 2 * cycle_seconds.
func _test_standalone_corpse() -> void:
	if _main == null or _player == null:
		return
	_death_event_count = 0
	EventBus.zombie_died.connect(_on_death_event)

	var corpse: CharacterBody2D = _make_walker("StandaloneCorpse")
	_main.add_child(corpse)
	corpse.global_position = _player.global_position + Vector2(48.0, 0.0)
	await get_tree().process_frame
	await get_tree().physics_frame

	var death_epoch: float = _world_epoch()
	corpse.take_damage(10000.0, _player)
	# La propia ruta de muerte debe ser idempotente, no solo la protección de
	# take_damage(). Una llamada directa repetida no puede duplicar el evento.
	corpse.call("_die")
	_check(_death_event_count == 1,
		"La muerte real emite zombie_died exactamente una vez")
	_check(corpse.has_method("is_alive") and not _bool_call(corpse, "is_alive"),
		"El zombi muerto deja de estar vivo")
	_check(corpse.has_method("is_corpse") and _bool_call(corpse, "is_corpse"),
		"El zombi muerto se identifica como cadáver")
	_check(not corpse.is_in_group("zombies"),
		"El cadáver abandona el grupo de zombis vivos")
	_check(corpse.is_in_group(CORPSE_GROUP),
		"El cadáver pertenece al grupo de cadáveres")
	_check(not corpse.is_physics_processing(),
		"El cadáver desactiva la física y la IA")
	_check(corpse.velocity == Vector2.ZERO,
		"El cadáver no conserva velocidad")
	_check(corpse.collision_layer == 0 and corpse.collision_mask == 0,
		"El cadáver desactiva todas sus capas de colisión")
	var collision := corpse.get_node_or_null("Collision") as CollisionShape2D
	_check(collision != null and collision.disabled,
		"El cadáver desactiva explícitamente su CollisionShape2D")
	var separation := corpse.get_node_or_null("SeparationArea") as Area2D
	_check(separation != null and not separation.monitoring,
		"El cadáver deja de monitorizar vecinos para separación")

	# La animación de muerte antigua terminaba en 0,86 s y liberaba el nodo.
	# Dos segundos reales en headless deben dejar un cadáver persistente.
	for _i in range(120):
		await get_tree().physics_frame
	_check(is_instance_valid(corpse),
		"El cadáver permanece después de terminar su animación de muerte")
	if not is_instance_valid(corpse):
		EventBus.zombie_died.disconnect(_on_death_event)
		return

	_check(corpse.modulate.a > 0.99,
		"El cadáver conserva el frame final en vez de desvanecerse")
	_check(corpse.visible,
		"El cadáver permanece visible cuando el jugador está cerca")
	var blood := corpse.get_node_or_null("CorpseBlood") as Sprite2D
	_check(blood != null and blood.texture != null and blood.visible,
		"El cadáver conserva el pixel art de sangre que lo ensangienta")
	_check(_is_under_corpse_root(corpse),
		"El cadáver pertenece a la raíz persistente de cadáveres")

	var cycle_seconds: float = float(GameState.call("world_cycle_seconds"))
	var recorded_death: float = _zombie_float(corpse, "death_epoch")
	var recorded_expiry: float = _zombie_float(corpse, "expiry_epoch")
	_check(not is_nan(recorded_death)
			and absf(recorded_death - death_epoch) < 0.25,
		"El epoch de muerte se captura en el instante real de la baja")
	_check(not is_nan(recorded_expiry)
			and absf(recorded_expiry
				- (recorded_death + CORPSE_LIFETIME_CYCLES * cycle_seconds)) < 0.001,
		"El expiry equivale a death_epoch + 2 * cycle_seconds")
	_check(not is_nan(recorded_expiry)
			and is_equal_approx(recorded_expiry - recorded_death, 600.0),
		"Con el ciclo de 300 s el cadáver dura exactamente 600 s")

	# El culling del corpse es reversible y no reactiva su simulación.
	var player_position: Vector2 = _player.global_position
	_player.global_position = corpse.global_position + Vector2(2000.0, 0.0)
	for _i in range(3):
		await get_tree().process_frame
	_check(not corpse.visible,
		"El cadáver lejano se oculta sin dejar de existir")
	_player.global_position = corpse.global_position + Vector2(50.0, 0.0)
	for _i in range(3):
		await get_tree().process_frame
	_check(corpse.visible,
		"El cadáver reaparece al acercarse el jugador")
	_check(not corpse.is_physics_processing()
			and corpse.collision_layer == 0
			and corpse.collision_mask == 0,
		"Reaparecer un cadáver no reactiva IA ni colisión")
	_player.global_position = player_position

	# El límite se cruza durante el menú: su tiempo activo consume la vida.
	GameState.set_phase(GameState.PHASE_MENU)
	var remaining: float = recorded_expiry - _world_epoch()
	if remaining > 0.5:
		GameState.call("advance_world_epoch", remaining - 0.25)
		await get_tree().process_frame
		_check(is_instance_valid(corpse),
			"El cadáver sigue vivo justo antes de completar dos ciclos")
		_check(GameState.phase() == GameState.PHASE_MENU,
			"La expiración ocurre todavía en el menú principal")
		GameState.call("advance_world_epoch", 0.5)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(not is_instance_valid(corpse),
			"El cadáver se elimina al completar dos ciclos de mundo")
		_check(GameState.phase() == GameState.PHASE_MENU,
			"El tiempo del menú consumió el plazo completo del cadáver")
	GameState.set_phase(GameState.PHASE_EXPLORE)
	EventBus.zombie_died.disconnect(_on_death_event)
	if is_instance_valid(corpse):
		corpse.queue_free()


## Una pausa real congela la vida del cadáver, no solo el cronómetro del HUD.
func _test_pause_does_not_expire_corpse() -> void:
	if _main == null or _player == null:
		return
	if not GameState.has_method("set_world_cycle_seconds") \
			or not GameState.has_method("world_cycle_seconds"):
		return
	var previous_cycle: float = float(GameState.call("world_cycle_seconds"))
	GameState.call("set_world_cycle_seconds", 1.0)
	var corpse: CharacterBody2D = _make_walker("PausedCorpse")
	_main.add_child(corpse)
	corpse.global_position = _player.global_position + Vector2(72.0, 0.0)
	await get_tree().process_frame
	corpse.take_damage(10000.0, _player)
	var expiry_epoch: float = _zombie_float(corpse, "expiry_epoch")

	get_tree().paused = true
	var paused_epoch: float = _world_epoch()
	for _i in range(4):
		await get_tree().process_frame
	_check(is_equal_approx(paused_epoch, _world_epoch()),
		"La pausa no consume el epoch del cadáver")
	GameState.call("advance_world_epoch", 10.0)
	_check(is_equal_approx(paused_epoch, _world_epoch()),
		"La pausa impide que QA consuma el plazo del cadáver")
	_check(is_instance_valid(corpse),
		"El cadáver no expira mientras el árbol está pausado")
	get_tree().paused = false
	await get_tree().process_frame

	if not is_nan(expiry_epoch):
		var remaining: float = expiry_epoch - _world_epoch()
		if remaining > 0.0:
			GameState.call("advance_world_epoch", remaining + 0.1)
			await get_tree().process_frame
			await get_tree().process_frame
		_check(not is_instance_valid(corpse),
			"El cadáver expira al reanudar si ya se alcanzó su epoch absoluto")
	GameState.call("set_world_cycle_seconds", previous_cycle)
	if is_instance_valid(corpse):
		corpse.queue_free()
		await get_tree().process_frame


## La duración no puede estar codificada a 600 s: debe derivar de la
## configuración canónica del ciclo vigente en el momento de la muerte.
func _test_configurable_cycle_duration() -> void:
	if _main == null or _player == null:
		return
	if not GameState.has_method("set_world_cycle_seconds") \
			or not GameState.has_method("world_cycle_seconds"):
		return
	var previous_cycle: float = float(GameState.call("world_cycle_seconds"))
	GameState.call("set_world_cycle_seconds", 12.5)
	var corpse: CharacterBody2D = _make_walker("ConfigurableCycleCorpse")
	_main.add_child(corpse)
	corpse.global_position = _player.global_position + Vector2(64.0, 0.0)
	await get_tree().process_frame
	corpse.take_damage(10000.0, _player)
	var death_epoch: float = _zombie_float(corpse, "death_epoch")
	var expiry_epoch: float = _zombie_float(corpse, "expiry_epoch")
	_check(not is_nan(death_epoch) and not is_nan(expiry_epoch)
			and absf(expiry_epoch - (death_epoch + 25.0)) < 0.001,
		"La duración configurable usa dos ciclos, no un literal de 600 s")
	GameState.call("set_world_cycle_seconds", previous_cycle)
	if is_instance_valid(corpse):
		corpse.queue_free()
	await get_tree().process_frame


## El zombi del bosque debe salir de la colección live-only antes de que la
## salida del bosque limpie sus compañeros. Su cadáver sigue en el mundo.
func _test_forest_corpse() -> void:
	if _main == null or _player == null:
		return
	var forest := _main.get_node_or_null("ForestZombies") as Node2D
	_check(forest != null, "Main crea el gestor real del bosque")
	if forest == null:
		return

	EventBus.forest_entered.emit()
	await get_tree().process_frame
	await get_tree().physics_frame
	var actors: Array[CharacterBody2D] = _actors_with_meta(forest, "forest_zombie")
	_check(not actors.is_empty(), "La entrada real al bosque crea zombis")
	if actors.is_empty():
		return
	var corpse: CharacterBody2D = actors[0]
	var survivors: Array[CharacterBody2D] = []
	for actor in actors:
		if actor != corpse:
			survivors.append(actor)
	_check(not survivors.is_empty(),
		"La limpieza del bosque tiene zombis vivos que liberar")

	corpse.take_damage(10000.0, _player)
	await get_tree().process_frame
	var live_owned: Array = forest.get("_spawned") as Array
	_check(not live_owned.has(corpse),
		"La colección del bosque relinquish el cadáver antes de limpiar")
	_check(live_owned.size() == survivors.size(),
		"La colección del bosque conserva solo zombis vivos")
	EventBus.forest_exited.emit()
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(_all_invalid(survivors),
		"La salida del bosque libera a los zombis vivos")
	_check(is_instance_valid(corpse),
		"El cadáver del bosque sobrevive a la salida del bosque")
	if is_instance_valid(corpse):
		_check(_is_under_corpse_root(corpse),
			"El cadáver del bosque pertenece a la raíz persistente")
		corpse.queue_free()


## La horda tiene el mismo contrato: la colección queda live-only y el
## cadáver se desprende antes de la dispersión que libera a los vivos.
func _test_horde_corpse() -> void:
	if _main == null or _player == null:
		return
	var director := _main.get_node_or_null("WaveManager")
	_check(director != null, "Main crea el WorldDirector real")
	if director == null:
		return

	EventBus.forest_entered.emit()
	director.call("force_phase", "night")
	director.call("trigger_horde")
	await get_tree().process_frame
	await get_tree().physics_frame
	var actors: Array[CharacterBody2D] = _actors_with_meta(director, "horde_zombie")
	_check(not actors.is_empty(), "La horda real crea zombis")
	if actors.is_empty():
		EventBus.forest_exited.emit()
		return
	var corpse: CharacterBody2D = actors[0]
	var survivors: Array[CharacterBody2D] = []
	for actor in actors:
		if actor != corpse:
			survivors.append(actor)
	_check(not survivors.is_empty(),
		"La dispersión de la horda tiene zombis vivos que liberar")

	corpse.take_damage(10000.0, _player)
	await get_tree().process_frame
	var live_owned: Array = director.get("_horde_zombies") as Array
	_check(not live_owned.has(corpse),
		"La colección de la horda relinquish el cadáver antes de limpiar")
	_check(live_owned.size() == survivors.size()
			and int(director.call("horde_size")) == survivors.size(),
		"La horda conserva y cuenta solo zombis vivos")
	director.call("force_phase", "day")
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_check(_all_invalid(survivors),
		"La dispersión real de horda libera sus zombis vivos")
	_check(is_instance_valid(corpse),
		"El cadáver de la horda sobrevive a la dispersión")
	if is_instance_valid(corpse):
		_check(_is_under_corpse_root(corpse),
			"El cadáver de la horda pertenece a la raíz persistente")
		corpse.queue_free()
	EventBus.forest_exited.emit()
	await get_tree().process_frame


func _make_walker(node_name: String) -> CharacterBody2D:
	var zombie: CharacterBody2D = ZOMBIE_SCENE.instantiate() as CharacterBody2D
	zombie.name = node_name
	zombie.set("kind", 0)
	zombie.set("speed", 0.0)
	zombie.set("detect_radius", 0.0)
	zombie.set("close_sense_radius", 0.0)
	zombie.set("lose_radius", 0.0)
	return zombie


func _actors_with_meta(parent: Node, meta_name: String) -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	for child in parent.get_children():
		if child is CharacterBody2D and bool(child.get_meta(meta_name, false)):
			result.append(child as CharacterBody2D)
	return result


func _all_invalid(nodes: Array[CharacterBody2D]) -> bool:
	if nodes.is_empty():
		return false
	for node in nodes:
		if is_instance_valid(node):
			return false
	return true


func _is_under_corpse_root(corpse: Node) -> bool:
	if corpse == null or not is_instance_valid(corpse):
		return false
	var ancestor: Node = corpse.get_parent()
	while ancestor != null:
		if ancestor.name == CORPSE_ROOT_NAME \
				and ancestor.is_in_group(CORPSE_ROOT_GROUP):
			return true
		ancestor = ancestor.get_parent()
	return false


func _world_epoch() -> float:
	if not GameState.has_method("world_epoch"):
		return NAN
	var value: Variant = GameState.call("world_epoch")
	if value is float or value is int:
		return float(value)
	return NAN


func _director_cycle_t() -> float:
	if _main == null:
		return NAN
	var director := _main.get_node_or_null("WaveManager")
	if director == null or not is_instance_valid(director):
		return NAN
	return float(director.get("_cycle_t"))


func _zombie_float(zombie: Node, method_name: String) -> float:
	if zombie == null or not is_instance_valid(zombie) \
			or not zombie.has_method(method_name):
		return NAN
	var value: Variant = zombie.call(method_name)
	if value is float or value is int:
		return float(value)
	return NAN


func _bool_call(target: Node, method_name: String) -> bool:
	if target == null or not is_instance_valid(target) \
			or not target.has_method(method_name):
		return false
	return bool(target.call(method_name))


func _on_death_event(_zombie = null) -> void:
	_death_event_count += 1


func _finish() -> void:
	get_tree().paused = false
	if _checks == 0:
		_failures.append("La puerta debe ejecutar al menos una comprobación")
	print("CORPSE_PERSISTENCE_TEST failures=%d" % _failures.size())
	print("CORPSE_PERSISTENCE_CHECKS checks=%d" % _checks)
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)
