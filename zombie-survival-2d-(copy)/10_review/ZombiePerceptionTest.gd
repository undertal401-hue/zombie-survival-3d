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
##   6. El radio de contacto NO sustituye a la linea de vision: a 80 px, con
##      una pared entre ambos, el zombi no ve ni alerta (bug reportado: seguia
##      al jugador dentro de la casa).
##   7. El ataque normal, el slam del jefe y el dano de carga exigen linea de
##      vision: no se puede golpear a traves de una pared.
##   8. La audicion del `WeaponController` esta cableada: un disparo o un
##      melee alerta al zombi aunque no lo vea y fija el punto de ruido.
##
## Control negativo: con el rayo unico de antes, el punto 4 falla (el poste
## oculta al jugador). Con la propagacion desactivada, el punto 5 falla. Si se
## elimina el rayo del radio de contacto (version R3), el punto 6 falla; si se
## quita el guard de LOS en `_attack`, el punto 7 falla; si se desconectan las
## senales del arma, el punto 8 falla.
## ============================================================================

const ZOMBIE_SCENE: String = "res://03_zombies/Zombie.tscn"
## Distancia lateral de los puntos alternativos de vision. Debe coincidir con
## SIGHT_SHOULDER_OFFSET de Zombie.gd (el jugador mide 16x16).
const SHOULDER_OFFSET: float = 6.0

var _failures: Array[String] = []
var _instances: Array[Node] = []


## Espia de la cascada: cuenta cada llamada a `receive_group_alert`. Esta
## dentro del radio de propagacion, asi que la primera llamada la hace el
## emisor. Si el receptor repropagara, el contador subiria a dos.
class AlertSpy:
	extends Node2D

	var calls: int = 0

	func receive_group_alert(_world_position: Vector2, _radius: float,
			_source: Node = null) -> void:
		calls += 1


## Objetivo de dano controlado: tiene RID (el rayo de vision puede excluirlo)
## y cuenta los golpes. Evita depender de Player.tscn y de su HUD.
class DamageTarget:
	extends CharacterBody2D

	var hp: float = 100.0
	var hits: int = 0

	func receive_damage(amount: float, _source: Node = null) -> void:
		hp -= amount
		hits += 1


## Emisor minimo con las DOS senales que `_connect_hearing_sources()` exige.
## No es un arma real: la prueba aisla el cableado de audicion del zombi.
class NoiseEmitter:
	extends Node

	signal fire_requested(weapon, from, to)
	signal melee_attack(weapon, direction)


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame
	await _detection_matrix()
	await _close_range_occlusion()
	await _hearing_wiring()
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


func _make_damage_target(position: Vector2) -> DamageTarget:
	var target := DamageTarget.new()
	target.name = "DamageTarget"
	target.collision_layer = 1
	target.collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	target.add_child(shape)
	target.add_to_group("player")
	add_child(target)
	target.global_position = position
	_instances.append(target)
	return target


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


## Bug reportado: dentro de la casa el zombi seguia al jugador aunque hubiera
## una pared. `_can_detect()` devolvia true sin rayo dentro de
## `close_sense_radius` (120 px). Este bloque fija que el radio de contacto
## solo relaja el cono, NUNCA la geometria, y que el dano tampoco atraviesa.
func _close_range_occlusion() -> void:
	var target: DamageTarget = _make_damage_target(Vector2.ZERO)
	var wall: StaticBody2D = _make_wall(Vector2(0, 40), Vector2(240, 10))
	var zombie: CharacterBody2D = _make_zombie(Vector2(0, 80), false)
	if zombie == null:
		_check(false, "Zombie.tscn se puede instanciar (corta distancia)")
		await _free_instances()
		return
	zombie.set("_facing_angle", -PI * 0.5)
	for i in range(4):
		await get_tree().physics_frame

	var distance: float = zombie.global_position.distance_to(target.global_position)
	var close_radius: float = float(zombie.get("close_sense_radius"))
	_check(distance <= close_radius,
		"el caso de pared es de corta distancia (%.0f <= %.0f px)" % [distance, close_radius])
	_check(not _sees(zombie, target),
		"una pared bloquea la vision aunque el jugador este dentro del radio de contacto")
	_check(is_zero_approx(float(zombie.get("_alert_timer"))),
		"el zombi no queda alertado por ver a traves de la pared")

	# Control positivo: sin pared, la misma distancia SI se percibe.
	wall.queue_free()
	for i in range(4):
		await get_tree().physics_frame
	_check(_sees(zombie, target),
		"sin pared, el radio de contacto sigue detectando al jugador")

	# Ataque normal: la pared no deja pasar el golpe.
	var wall_attack: StaticBody2D = _make_wall(Vector2(0, 40), Vector2(240, 10))
	zombie.set("target", target)
	zombie.set("state", 3)  # State.ATTACK
	zombie.set("attack_cooldown", 0.0)
	for i in range(3):
		await get_tree().physics_frame
	zombie.call("_attack")
	await get_tree().physics_frame
	_check(target.hits == 0, "el zombi no hace dano a traves de la pared")
	_check(is_equal_approx(float(target.hp), 100.0),
		"la vida del jugador no cambia a traves de la pared (hp %.0f)" % target.hp)

	wall_attack.queue_free()
	for i in range(4):
		await get_tree().physics_frame
	zombie.set("attack_cooldown", 0.0)
	zombie.call("_attack")
	await get_tree().physics_frame
	_check(target.hits == 1, "sin pared, el ataque normal conecta una vez")
	_check(float(target.hp) < 100.0,
		"sin pared, la vida del jugador baja (hp %.0f)" % target.hp)

	# Jefe "Tanque Alfa": slam y dano de carga tambien exigen LOS.
	var wall_boss: StaticBody2D = _make_wall(Vector2(0, 40), Vector2(240, 10))
	zombie.set("kind", 1)  # Kind.BOSS
	zombie.set("_boss_slam_timer", 0.0)
	var hits_before: int = target.hits
	for i in range(3):
		await get_tree().physics_frame
	zombie.call("_boss_attack")
	zombie.call("_boss_impact_damage")
	await get_tree().physics_frame
	_check(target.hits == hits_before,
		"el jefe no hace dano (slam ni carga) a traves de la pared")

	wall_boss.queue_free()
	for i in range(4):
		await get_tree().physics_frame
	zombie.set("_boss_slam_timer", 0.0)
	zombie.call("_boss_attack")
	await get_tree().physics_frame
	_check(target.hits == hits_before + 1, "sin pared, el slam del jefe conecta")

	await _free_instances()


## La audicion se cablea desde las senales del `WeaponController` hijo del
## jugador. El bug reportado decia "no escuchan"; este bloque fija el contrato
## con un emisor minimo para no depender de municion, aguante ni HUD.
func _hearing_wiring() -> void:
	var target: DamageTarget = _make_damage_target(Vector2.ZERO)
	var emitter := NoiseEmitter.new()
	emitter.name = "HearingStub"
	target.add_child(emitter)
	var zombie: CharacterBody2D = _make_zombie(Vector2(400, 0), false)
	if zombie == null:
		_check(false, "Zombie.tscn se puede instanciar (audicion)")
		await _free_instances()
		return
	zombie.set("_facing_angle", 0.0)  # De espaldas al jugador (a su izquierda).
	for i in range(4):
		await get_tree().physics_frame

	_check(not _sees(zombie, target),
		"PRE audicion: el zombi no ve al jugador que tiene detras")
	_check(is_zero_approx(float(zombie.get("_alert_timer"))),
		"PRE audicion: el zombi arranca sin alerta")

	emitter.emit_signal("fire_requested", null, Vector2(18, 0), Vector2(120, 0))
	await get_tree().process_frame
	var alert_shot: float = float(zombie.get("_alert_timer"))
	_check(alert_shot > 0.0,
		"el zombi OYE el disparo aunque no vea al jugador (alerta %.1f s)" % alert_shot)
	var last_shot: Vector2 = zombie.get("_last_known")
	_check(last_shot.distance_to(Vector2(18, 0)) <= 1.0,
		"el disparo deja su origen como ultimo punto conocido (%s)" % str(last_shot))
	_check(zombie.get("target") == target,
		"el ruido del jugador fija al jugador como objetivo")

	# Segunda senal del contrato: melee. Su radio es 250 px (menor que el del
	# disparo), asi que el zombi se acerca para quedar dentro del alcance.
	zombie.global_position = Vector2(200, 0)
	for i in range(2):
		await get_tree().physics_frame
	_check(not _sees(zombie, target),
		"PRE melee: el zombi sigue sin ver al jugador (de espaldas)")
	zombie.set("_alert_timer", 0.0)
	zombie.set("_noise_cooldown", 0.0)
	zombie.set("target", null)
	emitter.emit_signal("melee_attack", null, Vector2.UP)
	await get_tree().process_frame
	_check(float(zombie.get("_alert_timer")) > 0.0,
		"el zombi OYE el melee aunque no vea al jugador")
	var last_melee: Vector2 = zombie.get("_last_known")
	_check(last_melee.distance_to(Vector2(0, -18)) <= 1.0,
		"el melee usa el origen del jugador + direccion (%s)" % str(last_melee))

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
	var neighbour: CharacterBody2D = _make_zombie(Vector2(400, 420), false)
	# Tercer zombi: queda fuera del radio de propagacion de 420 px, asi que
	# no debe recibir ni el primer salto ni uno encadenado por el receptor.
	var third: CharacterBody2D = _make_zombie(Vector2(400, 540), false)
	# Espia dentro del radio: recibe el primer salto. Un segundo salto desde
	# el receptor lo detectaria como una segunda llamada, aunque la geometria
	# del tercer zombi no pueda alcanzarlo.
	var spy: AlertSpy = AlertSpy.new()
	spy.global_position = Vector2(400, 100)
	spy.add_to_group("zombies")
	add_child(spy)
	_instances.append(spy)
	if spotter == null or neighbour == null or third == null or spy == null:
		_check(false, "se pueden instanciar los tres zombis de la prueba de alerta")
		return
	# Muro entre el vecino y el jugador: el vecino NO lo ve, pero esta lo
	# bastante cerca como para recibir la alerta del que si lo ve.
	_make_wall(Vector2(400, 210), Vector2(240, 24))
	for i in range(4):
		await get_tree().physics_frame

	_check(_sees(spotter, player), "el zombi que mira al jugador lo ve")
	_check(not _sees(neighbour, player),
		"el vecino tapado por el muro no ve al jugador")
	var propagation_radius: float = float(spotter.get("alert_propagation_radius"))
	_check(third.global_position.distance_to(player.global_position) > propagation_radius,
		"el tercer zombi esta fuera del radio de propagacion del primer salto")
	_check(third.global_position.distance_to(spotter.global_position) > 520.0,
		"el tercer zombi esta fuera del radio de deteccion del emisor")
	_check(spy.global_position.distance_to(player.global_position) <= propagation_radius,
		"el espia esta dentro del radio de propagacion")

	for i in range(8):
		await get_tree().physics_frame

	var spotter_alert: float = float(spotter.get("_alert_timer"))
	var neighbour_alert: float = float(neighbour.get("_alert_timer"))
	var third_alert: float = float(third.get("_alert_timer"))
	_check(spotter_alert > 0.0, "el que ve al jugador queda alertado")
	_check(neighbour_alert > 0.0,
		"VER al jugador propaga la alerta a los zombis cercanos (alerta %.1f s)" % neighbour_alert)
	var neighbour_state: int = int(neighbour.get("state"))
	_check(neighbour_state != 0,
		"el vecino alertado deja el estado PATROL (estado %d)" % neighbour_state)
	_check(is_zero_approx(third_alert),
		"el receptor NO repropaga la alerta a un tercer zombi")
	_check(is_zero_approx(float(neighbour.get("_propagate_cooldown"))),
		"el receptor que recibe la alerta no inicia un segundo salto")
	_check(spy.calls == 1,
		"el grupo recibe exactamente una llamada de alerta (sin cascada): %d" % spy.calls)


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
