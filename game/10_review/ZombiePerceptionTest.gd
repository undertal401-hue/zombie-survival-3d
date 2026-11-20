extends Node
## ============================================================================
## ZOMBIE PERCEPTION TEST (R3) — deteccion robusta del jugador.
## ============================================================================
## El usuario noto que los zombis detectan mal al jugador. Este arnes fija el
## contrato de la percepcion (no la mera presencia de metodos):
##
##   1. Dentro del cono y del radio, el zombi VE al jugador.
##   2. Fuera del cono (detras) NO lo ve.
##   3. Fuera del radio efectivo NO lo ve (el radio se escala por dificultad,
##      asi que el arnes lo lee del propio zombi y no fija un literal).
##   4. La linea de vision usa TRES rayos (centro + dos "hombros"): un poste
##      estrecho que solo tapa el centro del jugador NO lo oculta, pero una
##      pared que lo tapa entero SI.
##   5. VER al jugador propaga la alerta al grupo: un zombi que lo ve alerta a
##      los zombis cercanos aunque no lo vean todavia (horda convergente).
##
## Control negativo: con el rayo unico de antes, el punto 4 falla (el poste
## oculta al jugador). Con la propagacion desactivada, el punto 5 falla.
## ============================================================================

const ZOMBIE_SCENE: String = "res://03_zombies/Zombie.tscn"
## Distancia lateral de los puntos alternativos de vision. Debe coincidir con
## SIGHT_SHOULDER_OFFSET de Zombie.gd (el jugador mide 16x16).
const SHOULDER_OFFSET: float = 6.0

var _failures: Array[String] = []
var _instances: Array[Node] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame
	await _detection_matrix()
	await _alert_propagation()
	await _finish()


func _make_player(position: Vector2) -> CharacterBody2D:
	var player := CharacterBody2D.new()
	player.name = "TestPlayer"
	player.collision_layer = 1
	player.collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	player.add_child(shape)
	player.add_to_group("player")
	add_child(player)
	player.global_position = position
	_instances.append(player)
	return player


func _make_zombie(position: Vector2, physics_enabled: bool) -> CharacterBody2D:
	var zombie := load(ZOMBIE_SCENE).instantiate() as CharacterBody2D
	if zombie == null:
		return null
	zombie.set_physics_process(physics_enabled)
	add_child(zombie)
	zombie.global_position = position
	_instances.append(zombie)
	return zombie


func _make_wall(center: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.name = "TestWall"
	wall.collision_layer = 1
	wall.collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = center
	_instances.append(wall)
	return wall


func _sees(zombie: Node, player: Node2D) -> bool:
	return bool(zombie.call("_can_detect", player))


func _effective_radius(zombie: Node) -> float:
	var difficulty: Dictionary = zombie.get("_difficulty") as Dictionary
	return float(zombie.get("detect_radius")) * float(difficulty.get("perception", 1.0))


func _detection_matrix() -> void:
	var player: CharacterBody2D = _make_player(Vector2(300, 0))
	var zombie: CharacterBody2D = _make_zombie(Vector2.ZERO, false)
	if zombie == null:
		_check(false, "Zombie.tscn se puede instanciar")
		return
	for i in range(4):
		await get_tree().physics_frame

	_check(_sees(zombie, player),
		"el zombi ve al jugador delante dentro del cono")

	# Detras: fuera del cono de +/-100 grados.
	var behind: CharacterBody2D = _make_player(Vector2(-300, 0))
	for i in range(2):
		await get_tree().physics_frame
	_check(not _sees(zombie, behind),
		"el zombi NO ve al jugador detras (fuera del cono)")
	behind.queue_free()

	# Distancia: dentro y fuera del radio efectivo real.
	var radius: float = _effective_radius(zombie)
	var far: CharacterBody2D = _make_player(Vector2(radius * 1.15, 0))
	for i in range(2):
		await get_tree().physics_frame
	_check(not _sees(zombie, far),
		"el zombi NO ve al jugador mas alla del radio efectivo (%.0f px)" % radius)
	far.queue_free()

	# Poste estrecho: tapa el centro pero no los hombros.
	var pole: StaticBody2D = _make_wall(Vector2(150, 0), Vector2(12, 2))
	for i in range(3):
		await get_tree().physics_frame
	_check(_sees(zombie, player),
		"un poste que solo tapa el centro NO oculta al jugador (rayos de hombros)")

	# Muro ancho: tapa los tres rayos.
	pole.queue_free()
	var wall: StaticBody2D = _make_wall(Vector2(150, 0), Vector2(12, 120))
	for i in range(3):
		await get_tree().physics_frame
	_check(not _sees(zombie, player),
		"una pared que tapa el cuerpo entero SI oculta al jugador")

	# Se libera TODO lo creado en esta seccion: un jugador anterior en el
	# grupo "player" se interponia en el rayo y hacia fallar la seccion de
	# alerta (el zombi apunta al jugador viejo, no al nuevo).
	await _free_instances()


## Libera los nodos creados y espera a que SALGAN del arbol (y del grupo).
func _free_instances() -> void:
	for node in _instances:
		if is_instance_valid(node):
			node.queue_free()
	_instances.clear()
	for i in range(4):
		await get_tree().physics_frame
		await get_tree().process_frame


func _alert_propagation() -> void:
	var player: CharacterBody2D = _make_player(Vector2(400, 0))
	var spotter: CharacterBody2D = _make_zombie(Vector2.ZERO, true)
	var neighbour: CharacterBody2D = _make_zombie(Vector2(400, 300), false)
	if spotter == null or neighbour == null:
		_check(false, "se pueden instanciar los dos zombis de la prueba de alerta")
		return
	# Muro entre el vecino y el jugador: el vecino NO lo ve, pero esta lo
	# bastante cerca como para recibir la alerta del que si lo ve.
	_make_wall(Vector2(400, 150), Vector2(240, 24))
	for i in range(4):
		await get_tree().physics_frame

	_check(_sees(spotter, player), "el zombi que mira al jugador lo ve")
	_check(not _sees(neighbour, player),
		"el vecino tapado por el muro no ve al jugador")

	for i in range(8):
		await get_tree().physics_frame

	var spotter_alert: float = float(spotter.get("_alert_timer"))
	var neighbour_alert: float = float(neighbour.get("_alert_timer"))
	_check(spotter_alert > 0.0, "el que ve al jugador queda alertado")
	_check(neighbour_alert > 0.0,
		"VER al jugador propaga la alerta a los zombis cercanos (alerta %.1f s)" % neighbour_alert)
	var neighbour_state: int = int(neighbour.get("state"))
	_check(neighbour_state != 0,
		"el vecino alertado deja el estado PATROL (estado %d)" % neighbour_state)

	await _free_instances()


func _finish() -> void:
	for node in _instances:
		if is_instance_valid(node):
			node.queue_free()
	_instances.clear()
	for i in range(4):
		await get_tree().process_frame
	print("ZOMBIE_PERCEPTION_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
	for f in _failures:
		assert(false, "ZOMBIE_PERCEPTION_TEST: " + f)
