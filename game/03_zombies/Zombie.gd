extends CharacterBody2D

enum Kind { WALKER, RUNNER, TANK, SPITTER, SCREAMER, BOSS }
enum State { PATROL, INVESTIGATE, CHASE, ATTACK, STUNNED, DEAD }

const HIT_TORSO: int = 0
const HIT_HEAD: int = 1
const HIT_LEG: int = 2

## CAPA 2 / ÍTEM 12 — "Tanque Alfa". Dos fases: la 1 carga telegrafiada y la
## 2 (enraged, al 50 % de vida) añade un golpe de area y acorta los cooldowns.
const BOSS_PHASE_2_HP: float = 0.5
const BOSS_CHARGE_RANGE: float = 260.0
const BOSS_SLAM_RANGE: float = 130.0
const BOSS_SLAM_COOLDOWN: float = 3.2

const ATTACK_RANGE := 34.0
const SEPARATION_RADIUS := 26.0
const SEPARATION_FORCE := 55.0
const ALERT_TIME := 5.0

## La alerta se propaga por EventBus.zombie_alerted y, localmente, con el
## bucle de grupo de _propagate_alert() -> receive_group_alert(). Antes había
## aquí una señal local zombie_alerted que nadie conectaba (deuda #17).

@export var kind: Kind = Kind.WALKER
@export var speed: float = 80.0
@export var max_hp: float = 68.0
@export var attack_damage: float = 10.0
@export var attack_cooldown_time: float = 1.0
@export var detect_radius: float = 430.0
@export var lose_radius: float = 700.0

## Nuevas propiedades para tipos especiales
@export var spit_range: float = 300.0
@export var spit_damage: float = 15.0
@export var spit_cooldown: float = 3.0
@export var scream_radius: float = 500.0
@export var scream_cooldown: float = 8.0
@export var charge_speed: float = 250.0
@export var charge_cooldown: float = 5.0

## Jefe (kind == Kind.BOSS). `phase`/`enraged` son el estado de las dos fases;
## `is_boss` permite a otros sistemas preguntar sin depender del enum.
@export var is_boss: bool = false
@export var phase: int = 1
@export var enraged: bool = false
@export var boss_slam_cooldown: float = BOSS_SLAM_COOLDOWN

## Percepcion / IA
@export var vision_half_angle_degrees: float = 100.0
@export var close_sense_radius: float = 105.0
@export var hearing_shot_radius: float = 950.0
@export var hearing_impact_radius: float = 540.0
@export var hearing_melee_radius: float = 250.0
@export var alert_propagation_radius: float = 420.0

## Perfil táctico por arquetipo (lo fija _apply_kind).
## flank_strength: desvío lateral al perseguir para no llegar en línea recta.
## preferred_range: distancia que intenta mantener; 0 = cuerpo a cuerpo.
## separation_scale: cuánto empuje ejerce en la separación vecinal.
@export var flank_strength: float = 0.0
@export var preferred_range: float = 0.0
@export var separation_scale: float = 1.0
var _flank_side: float = 1.0

var _spit_timer: float = 0.0
var _scream_timer: float = 0.0
var _charge_timer: float = 0.0
var _charge_duration: float = 0.0
var _is_charging: bool = false
var _charge_direction: Vector2 = Vector2.ZERO
var _boss_slam_timer: float = 0.0
var _boss_charge_hit: bool = false

@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var separation_area: Area2D = $SeparationArea
@onready var body_visual: Polygon2D = $Body
@onready var nose: Polygon2D = $Nose
@onready var alert_label: Label = $Alert
@onready var zombie_visual: ZombieVisual = $ZombieVisual

var target: Node2D
var hp: float = 68.0
var attack_cooldown: float = 0.0

var state: State = State.PATROL
var _state_after_stun: State = State.CHASE
var _stun_timer: float = 0.0
var _spawn_position: Vector2
var _last_known: Vector2
var _wander_target: Vector2
var _wander_timer: float = 0.0
var _alert_timer: float = 0.0
var _investigate_wait: float = 0.0
var _flash_timer: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _dead: bool = false
var _repath_timer: float = 0.0
var _last_destination: Vector2 = Vector2.INF
## Vecinos cercanos detectados por el Area2D local (solo zombis en radio SEPARATION_RADIUS).
## Sustituye al antiguo _separation_cache que contenía TODOS los zombis del grupo.
var _separation_neighbors: Array[Node2D] = []
var _facing_angle: float = 0.0

# Oido / alerta en grupo
var _noise_cooldown: float = 0.0
var _propagate_cooldown: float = 0.0
var _receive_cooldown: float = 0.0
var _hearing_source: Node = null
var _connected_weapons: Array = []
var _hearing_refresh: float = 0.0

# Dano por extremidad y dificultad
var _leg_wounds: int = 0
var _is_crawling: bool = false
var _difficulty: Dictionary = {
	"speed": 1.0, "perception": 1.0, "damage": 1.0, "health": 1.0
}
var _base_max_hp: float = 0.0
var _difficulty_refresh: float = 0.0


func _ready() -> void:
	add_to_group("zombies")
	# Separación local: el Area2D solo detecta cuerpos en la capa 2 (zombis).
	# Filtramos por grupo en el callback para ignorar sondas de test en esa capa.
	if separation_area != null:
		separation_area.body_entered.connect(_on_separation_body_entered)
		separation_area.body_exited.connect(_on_separation_body_exited)
	_spawn_position = global_position
	_last_known = _spawn_position
	# Lado de flanqueo estable por individuo y determinista por partida.
	_flank_side = 1.0 if GameState.rng(&"ai").randf() > 0.5 else -1.0
	_facing_angle = body_visual.rotation
	_refresh_difficulty()
	_apply_kind()
	hp = max_hp * float(_difficulty.get("health", 1.0))
	target = _player_node()
	alert_label.visible = false
	_pick_wander_target()
	_connect_hearing_sources()
	_connect_bus_alert_if_available()


## Única puerta de acceso al jugador dentro del zombi.
## `get_first_node_in_group` puede devolver un objeto ya liberado (la escena
## se recarga al morir o al reintentar) y castearlo a Node2D lanza
## "Trying to cast a freed object". Aquí se valida ANTES de convertir.
func _player_node() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var found: Node = tree.get_first_node_in_group("player")
	if found == null or not is_instance_valid(found):
		return null
	return found as Node2D


func _physics_process(delta: float) -> void:
	if _dead:
		return

	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	_repath_timer = maxf(_repath_timer - delta, 0.0)
	_noise_cooldown = maxf(_noise_cooldown - delta, 0.0)
	_propagate_cooldown = maxf(_propagate_cooldown - delta, 0.0)
	_receive_cooldown = maxf(_receive_cooldown - delta, 0.0)
	_difficulty_refresh -= delta
	_hearing_refresh -= delta
	if _difficulty_refresh <= 0.0:
		_refresh_difficulty()
	if _hearing_refresh <= 0.0:
		_connect_hearing_sources()
		_hearing_refresh = 2.0
	_update_flash(delta)

	# Timers para habilidades especiales
	_spit_timer = maxf(_spit_timer - delta, 0.0)
	_scream_timer = maxf(_scream_timer - delta, 0.0)
	_charge_timer = maxf(_charge_timer - delta, 0.0)
	_boss_slam_timer = maxf(_boss_slam_timer - delta, 0.0)

	if _is_charging:
		# La duración es independiente del cooldown: si se reutilizara
		# _charge_timer, la carga se acortaría a la mitad y el cooldown quedaría
		# en 0, encadenando cargas cada ~0.75s en vez de cada 5s.
		_charge_duration = maxf(_charge_duration - delta, 0.0)
		if _charge_duration <= 0.0:
			_is_charging = false

	_refresh_target()
	_update_perception(delta)
	_run_state(delta)

	_apply_separation()
	if not _is_charging:
		velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, 220.0 * delta)

	if velocity.length() > 8.0:
		_facing_angle = lerp_angle(_facing_angle, velocity.angle(), minf(delta * 8.0, 1.0))
		body_visual.rotation = _facing_angle
		nose.rotation = _facing_angle

	move_and_slide()

	# El jefe impacta una sola vez por carga telegrafiada (boss_attack).
	if is_boss and _is_charging and not _boss_charge_hit and _target_valid():
		if global_position.distance_to(target.global_position) <= ATTACK_RANGE * 1.25:
			_boss_charge_hit = true
			_boss_impact_damage()

	# Actualizar visual
	if zombie_visual != null and not _dead:
		var target_dir: Vector2 = Vector2.ZERO
		if target != null and is_instance_valid(target):
			target_dir = (target.global_position - global_position).normalized()
		zombie_visual.update_state(velocity, _alert_timer > 0.0, target_dir, _is_crawling)
		if is_boss:
			zombie_visual.update_boss_health(
				clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0), phase == 2)

	alert_label.visible = _alert_timer > 0.0 and not _dead


# ---------------------------------------------------------------------------
# Maquina de estados
# ---------------------------------------------------------------------------

func _refresh_target() -> void:
	if target == null or not is_instance_valid(target) or not target.is_in_group("player"):
		target = _player_node()


func _target_valid() -> bool:
	return target != null and is_instance_valid(target) and target.is_in_group("player")


func _update_perception(delta: float) -> void:
	var sees_player: bool = false
	var distance: float = INF
	if target != null and is_instance_valid(target):
		distance = global_position.distance_to(target.global_position)
		sees_player = _can_detect(target)
		if sees_player:
			_become_alerted(target.global_position, target, false)
		elif distance > lose_radius and _alert_timer <= 0.0:
			_last_known = _spawn_position

	if _alert_timer > 0.0:
		_alert_timer = maxf(_alert_timer - delta, 0.0)
		if _alert_timer <= 0.0:
			_investigate_wait = 0.6
			if state == State.CHASE or state == State.ATTACK:
				state = State.INVESTIGATE
			if _hearing_source != null and is_instance_valid(_hearing_source):
				_hearing_source = null


func _run_state(delta: float) -> void:
	match state:
		State.STUNNED:
			_stun_timer -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 420.0 * delta)
			if _stun_timer <= 0.0:
				state = _state_after_stun
		State.PATROL:
			_wander(delta)
		State.INVESTIGATE, State.CHASE, State.ATTACK:
			_pursue(delta)
		State.DEAD:
			velocity = Vector2.ZERO


func _pursue(delta: float) -> void:
	if not _target_valid():
		state = State.INVESTIGATE
		_navigate_to(_last_known, speed * _speed_multiplier() * 0.8)
		if _reached(_last_known):
			_settle_investigation(delta)
		return

	if _is_charging:
		velocity = _charge_direction * charge_speed
		return

	var distance: float = global_position.distance_to(target.global_position)
	var sees: bool = _can_detect(target)
	var move_speed: float = speed * _speed_multiplier()

	# Habilidades especiales por tipo (mantienen el comportamiento original).
	if kind == Kind.SPITTER and spit_range > 0.0:
		if distance <= spit_range and distance > ATTACK_RANGE and _spit_timer <= 0.0 and sees:
			state = State.CHASE
			_spit_attack()
			velocity = Vector2.ZERO
			return
	elif kind == Kind.SCREAMER and scream_radius > 0.0:
		if _scream_timer <= 0.0 and distance <= scream_radius:
			_scream_attack()
	elif kind == Kind.BOSS:
		# Fase 1: carga telegrafiada. Fase 2: además un slam de área más cercano.
		if phase == 2 and distance <= BOSS_SLAM_RANGE and _boss_slam_timer <= 0.0 and sees:
			state = State.CHASE
			_boss_attack()
			velocity = Vector2.ZERO
			return
		if distance <= BOSS_CHARGE_RANGE and distance > ATTACK_RANGE and _charge_timer <= 0.0 and sees:
			state = State.CHASE
			_start_boss_charge(target.global_position)
			velocity = _charge_direction * charge_speed
			return
	elif kind == Kind.TANK and charge_speed > 0.0:
		if distance <= 200.0 and distance > ATTACK_RANGE and _charge_timer <= 0.0 and sees:
			state = State.CHASE
			_start_charge(target.global_position)
			velocity = _charge_direction * charge_speed
			return

	if distance <= ATTACK_RANGE:
		state = State.ATTACK
		velocity = Vector2.ZERO
		_attack()
		return

	state = State.CHASE if sees else State.INVESTIGATE
	var destination: Vector2 = target.global_position if sees else _last_known
	if sees and distance > ATTACK_RANGE * 1.5:
		# Flanqueo: acercarse por un lado en vez de empujar en línea recta.
		if flank_strength > 0.0:
			var to_player: Vector2 = (target.global_position - global_position).normalized()
			var side: Vector2 = Vector2(-to_player.y, to_player.x) * _flank_side
			destination += side * (70.0 * flank_strength)
		# Kiting del escupidor / grito: si está demasiado cerca se retira.
		if preferred_range > 0.0 and distance < preferred_range * 0.7:
			var away: Vector2 = (global_position - target.global_position).normalized()
			destination = global_position + away * 120.0
	_navigate_to(destination, move_speed)
	if not sees and _reached(_last_known):
		_settle_investigation(delta)


func _settle_investigation(delta: float) -> void:
	_investigate_wait -= delta
	velocity = Vector2.ZERO
	if _investigate_wait <= 0.0:
		_alert_timer = 0.0
		state = State.PATROL
		_pick_wander_target()


func _reached(point: Vector2) -> bool:
	return global_position.distance_to(point) < 28.0


# ---------------------------------------------------------------------------
# Percepcion: cono + linea de vision + oido
# ---------------------------------------------------------------------------

func _can_detect(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var to_target: Vector2 = node.global_position - global_position
	var distance: float = to_target.length()
	var sight_radius: float = detect_radius * float(_difficulty.get("perception", 1.0))
	if distance > sight_radius:
		return false
	if distance > close_sense_radius and distance > 0.001:
		var cone: float = deg_to_rad(vision_half_angle_degrees)
		if absf(angle_difference(_facing_angle, to_target.angle())) > cone:
			return false
		return _has_line_of_sight_to(node)
	# A muy corta distancia el zombie tambien percibe por contacto/olido, aunque
	# un marco de puerta rompa la linea de vision exacta centro a centro.
	return true


func _has_line_of_sight_to(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, node.global_position)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	if node is CollisionObject2D:
		query.exclude.append(node.get_rid())
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _connect_hearing_sources() -> void:
	# Deuda #18: purgar referencias liberadas. Un WeaponController se libera al
	# recargar la escena; sin esto el array solo crece. El motor ya retira las
	# conexiones a objetos liberados; aquí solo limpiamos nuestra copia.
	if not _connected_weapons.is_empty():
		_connected_weapons = _connected_weapons.filter(func(w): return is_instance_valid(w))
	var player: Node2D = _player_node()
	if player == null:
		return
	# Senales locales del WeaponController: disparos, impactos y melee.
	for child in player.get_children():
		if child == null or not is_instance_valid(child) or _connected_weapons.has(child):
			continue
		if not child.has_signal("fire_requested") or not child.has_signal("melee_attack"):
			continue
		child.connect("fire_requested", Callable(self, "_on_gun_noise"))
		child.connect("melee_attack", Callable(self, "_on_melee_noise"))
		_connected_weapons.append(child)


func _connect_bus_alert_if_available() -> void:
	if not EventBus.has_signal("zombie_alerted"):
		return
	# La señal del EventBus puede tener 1, 2 o 3 argumentos segun el nucleo;
	# elegimos el adaptador con el mismo numero para evitar errores de Callable.
	var arg_count: int = 0
	for info in EventBus.get_signal_list():
		if String(info.get("name", "")) == "zombie_alerted":
			arg_count = (info.get("args", []) as Array).size()
			break
	match arg_count:
		1:
			EventBus.connect("zombie_alerted", Callable(self, "_on_bus_alert_1"))
		2:
			EventBus.connect("zombie_alerted", Callable(self, "_on_bus_alert_2"))
		3:
			EventBus.connect("zombie_alerted", Callable(self, "_on_bus_alert_3"))


func _on_gun_noise(_weapon: Variant, from: Vector2, to: Vector2) -> void:
	# Ruido en la boca y en el punto de impacto (el raycast del jugador puede
	# terminar en una pared, que también debe atraer a los zombies).
	_hear_noise(from, hearing_shot_radius, _player_node(), true)
	_hear_noise(to, hearing_impact_radius, null, true)


func _on_melee_noise(_weapon: Variant, direction: Vector2) -> void:
	var origin: Vector2 = global_position
	var player: Node2D = _player_node()
	if player != null:
		origin = player.global_position
	_hear_noise(origin + direction.normalized() * 18.0, hearing_melee_radius, player, true)


## ¿Es este valor ESTE zombi?
##
## El bus `zombie_alerted` admite DOS convenciones: `(zombie, source)` con
## nodos (la que declara `EventBus`) y `(posicion, radio)` desde el vehículo
## (`DriveableVehicle._emit_alert()` inspecciona la firma y emite lo que
## encaja). Comparar un Vector2 con un Object en GDScript 4 es un ERROR en
## tiempo de ejecución ("Invalid operands 'Vector2' and 'Object' in operator
## '=='"), NO un false: aborta el handler y el zombi nunca oye el ruido.
##
## Por eso el guard tiene que comprobar el TIPO antes de comparar, y validar
## que la instancia siga viva antes de tocarla (mismo patrón que R1-fix).
## ¿Es este valor un objeto VIVO de tipo Node?
##
## Orden de guards (el mismo que fija ADR-004 §9 para el payload de
## `zombie_died`): `typeof` -> `is_instance_valid` -> `is`.
##
## Medido en Godot 4.7.2:
##   - `instancia_liberada is Node` LANZA "Left operand of 'is' is a previously
##     freed instance": aborta la funcion y deja un SCRIPT ERROR por frame.
##   - `is_instance_valid(instancia_liberada)` responde false SIN lanzar.
##   - `typeof()` distingue un Vector2 de un objeto sin tocar la instancia.
##   - `instancia_liberada is float` NO lanza (los tipos basicos no necesitan
##     mirar la instancia), pero `is Node`/`is Node2D` si.
func _is_live_node(value: Variant) -> bool:
	if typeof(value) != TYPE_OBJECT:
		return false
	if not is_instance_valid(value):
		return false
	return value is Node


## ¿Es este valor ESTE zombi?
##
## El bus `zombie_alerted` admite DOS convenciones: `(zombie, source)` con
## nodos (la que declara `EventBus`) y `(posicion, radio)` desde el vehículo
## (`DriveableVehicle._emit_alert()` inspecciona la firma y emite lo que
## encaja). Comparar un Vector2 con un Object en GDScript 4 es un ERROR en
## tiempo de ejecución ("Invalid operands 'Vector2' and 'Object' in operator
## '=='"), NO un false: aborta el handler y el zombi nunca oye el ruido.
func _is_self(value: Variant) -> bool:
	if not _is_live_node(value):
		return false
	return (value as Node) == self


func _on_bus_alert_1(a: Variant) -> void:
	if _is_self(a):
		return
	_hear_noise(_alert_point(a), _alert_radius(null), _alert_source(a, null), true)


func _on_bus_alert_2(a: Variant, b: Variant) -> void:
	if _is_self(a) or _is_self(b):
		return
	_hear_noise(_alert_point(a), _alert_radius(b), _alert_source(a, b), true)


func _on_bus_alert_3(a: Variant, b: Variant, c: Variant) -> void:
	if _is_self(a) or _is_self(c):
		return
	_hear_noise(_alert_point(a), _alert_radius(b), _alert_source(a, c), true)


func _alert_source(a: Variant, b: Variant) -> Node:
	# Orden de guards: `typeof` -> `is_instance_valid` -> `is`. Con un `is`
	# directo sobre una instancia liberada, GDScript lanza y aborta la funcion.
	if _is_live_node(b):
		var source_b: Node = b as Node
		if source_b.is_in_group("player"):
			return source_b
	if _is_live_node(a):
		var source_a: Node = a as Node
		if source_a.is_in_group("player"):
			return source_a
	return null


func _alert_point(value: Variant) -> Vector2:
	# `typeof` primero: un payload liberado es TYPE_OBJECT y no se puede
	# leer su posicion, asi que el punto es desconocido (INF) y el ruido se
	# ignora. Antes el `is` sobre una instancia liberada abortaba la funcion
	# y devolvia (0,0): el zombi perseguia un punto inventado.
	var value_type: int = typeof(value)
	if value_type == TYPE_VECTOR2:
		return value
	if value_type == TYPE_VECTOR2I:
		return Vector2(value)
	if _is_live_node(value) and value is Node2D:
		return (value as Node2D).global_position
	return Vector2.INF


func _alert_radius(value: Variant) -> float:
	var value_type: int = typeof(value)
	if value_type == TYPE_FLOAT or value_type == TYPE_INT:
		return maxf(float(value), 0.0)
	if value_type == TYPE_STRING:
		var text: String = value
		if text.is_valid_float():
			return clampf(float(text), 0.0, 2000.0)
	return alert_propagation_radius


func _hear_noise(world_position: Vector2, radius: float, source: Node, propagate: bool = false) -> void:
	if _dead or _noise_cooldown > 0.0 or world_position == Vector2.INF:
		return
	if global_position.distance_to(world_position) > radius:
		return
	_noise_cooldown = 0.3
	_become_alerted(world_position, source, propagate)


func _become_alerted(world_position: Vector2, source: Node, propagate: bool = true) -> void:
	if _dead:
		return
	var was_calm: bool = _alert_timer <= 0.0 or state == State.PATROL or state == State.INVESTIGATE
	if source != null and is_instance_valid(source) and source is Node2D:
		var source_2d: Node2D = source as Node2D
		if source_2d.is_in_group("player"):
			target = source_2d
			_hearing_source = source_2d
	if target == null:
		target = _player_node()
	_last_known = world_position
	_alert_timer = ALERT_TIME
	_investigate_wait = 0.6
	if state != State.STUNNED:
		state = State.CHASE
	_state_after_stun = State.CHASE
	if was_calm and propagate:
		_propagate_alert(world_position, alert_propagation_radius, source)


## Un zombie alertado comparte el último punto conocido con el grupo cercano.
func _propagate_alert(world_position: Vector2, radius: float, source: Node) -> void:
	if _propagate_cooldown > 0.0 or world_position == Vector2.INF:
		return
	_propagate_cooldown = 1.2
	for other in get_tree().get_nodes_in_group("zombies"):
		if other == self or not is_instance_valid(other):
			continue
		if not other.has_method("receive_group_alert"):
			continue
		var other_2d: Node2D = other as Node2D
		if other_2d == null or other_2d.global_position.distance_to(world_position) > radius:
			continue
		other.call("receive_group_alert", world_position, radius, self)


func receive_group_alert(world_position: Vector2, radius: float, _source: Node = null) -> void:
	if _dead or _receive_cooldown > 0.0 or world_position == Vector2.INF:
		return
	if global_position.distance_to(world_position) > radius:
		return
	_receive_cooldown = 0.55 + randf() * 0.25
	_hear_noise(world_position, radius, null, false)


# ---------------------------------------------------------------------------
# Dano, extremidades, aturdimiento y muerte
# ---------------------------------------------------------------------------

func take_damage(amount: float, from: Node2D = null, hit_zone: int = HIT_TORSO) -> void:
	if _dead:
		return
	hp -= amount
	_flash_timer = 0.12
	modulate = Color(1.5, 0.65, 0.65, 1.0)

	if zombie_visual != null:
		zombie_visual.play_hit()

	if ParticleManager.instance != null:
		var direction: Vector2 = Vector2.ZERO
		if from != null:
			direction = (global_position - from.global_position).normalized()
		ParticleManager.instance.spawn_blood(global_position, direction, 25)

	if from != null:
		var was_calm: bool = _alert_timer <= 0.0 or state == State.PATROL or state == State.INVESTIGATE
		_alert_timer = ALERT_TIME + 2.0
		_last_known = from.global_position
		if from.is_in_group("player"):
			target = from
		var push: Vector2 = global_position - from.global_position
		if push.length() > 0.001:
			_knockback = push.normalized() * 120.0
		_state_after_stun = State.CHASE
		state = State.STUNNED
		_stun_timer = 0.55 if hit_zone == HIT_HEAD else 0.16
		if was_calm:
			_propagate_alert(_last_known, alert_propagation_radius, from)

	if hit_zone == HIT_LEG:
		_apply_leg_wound()

	if hp <= 0.0:
		_die()
		return
	# Cruce del 50 % de vida: el jefe entra en fase 2 y cambia de patrón.
	if is_boss and phase == 1 and hp <= max_hp * BOSS_PHASE_2_HP:
		_enter_phase_2()


## Variante con punto de impacto: los sistemas de combate pueden pasar la
## posicion exacta del disparo para clasificar cabeza / torso / pierna.
func take_damage_at(amount: float, from: Node2D, hit_position: Vector2) -> void:
	var zone: int = HIT_TORSO
	if hit_position.y < global_position.y - 4.0:
		zone = HIT_HEAD
	elif hit_position.y > global_position.y + 4.0:
		zone = HIT_LEG
	take_damage(amount, from, zone)


func _apply_leg_wound() -> void:
	_leg_wounds += 1
	var slow: float = maxf(1.0 - 0.32 * float(_leg_wounds), 0.25)
	if not _is_crawling and (_leg_wounds >= 2 or hp < max_hp * 0.35):
		_is_crawling = true
	if _is_crawling:
		slow = minf(slow, 0.28)
		if zombie_visual != null:
			zombie_visual.play_crawl()
	# La velocidad base se conserva: el multiplicador se aplica al moverse.
	set_meta("leg_wounds", _leg_wounds)
	set_meta("crawling", _is_crawling)
	set_meta("speed_factor", slow)


func _speed_multiplier() -> float:
	var wound_slow: float = float(get_meta("speed_factor", 1.0))
	return clampf(wound_slow * float(_difficulty.get("speed", 1.0)), 0.1, 2.5)


## Aviso visual + sonoro justo antes de una acción ofensiva. El kind coincide
## con ZombieVisual.ZombieType; AudioDirector elige un SFX distinto por tipo.
func _telegraph(kind_to_announce: int) -> void:
	if zombie_visual != null:
		zombie_visual.telegraph(kind_to_announce)
	var audio: Node = get_tree().get_first_node_in_group("audio_director")
	if audio != null and audio.has_method("play_telegraph"):
		audio.call("play_telegraph", kind_to_announce, global_position)


func _attack() -> void:
	if attack_cooldown > 0.0 or target == null or state == State.STUNNED:
		return
	attack_cooldown = attack_cooldown_time

	_telegraph(kind)
	if zombie_visual != null:
		zombie_visual.play_attack()

	if target.has_method("receive_damage"):
		target.call("receive_damage", attack_damage * float(_difficulty.get("damage", 1.0)))


## Ataque escupitajo (Spitter)
func _spit_attack() -> void:
	if _spit_timer > 0.0 or target == null:
		return
	_spit_timer = spit_cooldown

	_telegraph(kind)
	if zombie_visual != null:
		zombie_visual.play_attack()

	var spit_scene: PackedScene = preload("res://03_zombies/projectiles/AcidSpit.tscn")
	var spit: Node2D = spit_scene.instantiate()
	# Parentear a la escena, no a root: un escupitajo en vuelo podría sobrevivir
	# a reload_current_scene() y dañar al jugador de la partida nueva.
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(spit)

	var direction: Vector2 = (target.global_position - global_position).normalized()
	spit.global_position = global_position + direction * 20.0
	spit.rotation = direction.angle()
	spit.call("launch", direction, spit_damage * float(_difficulty.get("damage", 1.0)), spit_range)


## Grito de alerta (Screamer)
func _scream_attack() -> void:
	if _scream_timer > 0.0:
		return
	_scream_timer = scream_cooldown

	_telegraph(kind)
	if zombie_visual != null:
		zombie_visual.play_attack()

	if ParticleManager.instance != null:
		ParticleManager.instance.spawn_impact_flesh(global_position, Vector2.ZERO)

	_propagate_alert(global_position, scream_radius, self)

	if target != null and global_position.distance_to(target.global_position) <= 80.0:
		if target.has_method("receive_damage"):
			target.call("receive_damage", attack_damage * 0.5 * float(_difficulty.get("damage", 1.0)))


## Carga (Tank)
func _start_charge(target_pos: Vector2) -> void:
	if _charge_timer > 0.0:
		return
	_charge_timer = charge_cooldown
	_charge_duration = 1.5  # Duración de la carga
	_is_charging = true

	var direction: Vector2 = (target_pos - global_position).normalized()
	_charge_direction = direction

	_telegraph(kind)
	if zombie_visual != null:
		zombie_visual.play_attack()

	if ParticleManager.instance != null:
		ParticleManager.instance.spawn_impact_concrete(global_position, _charge_direction)


# --- Jefe "Tanque Alfa" (CAPA 2 / ÍTEM 12) ---------------------------------

## Fase 2: al caer por debajo del 50 % de vida el patrón se acelera y se añade
## un ataque de área. No reasigna `kind`, así que el arte y la barra se mantienen.
func _enter_phase_2() -> void:
	if not is_boss or phase == 2:
		return
	phase = 2
	enraged = true
	speed *= 1.28
	attack_damage *= 1.30
	attack_cooldown_time = maxf(attack_cooldown_time * 0.75, 0.4)
	charge_speed *= 1.20
	charge_cooldown = maxf(charge_cooldown * 0.65, 1.0)
	boss_slam_cooldown = maxf(boss_slam_cooldown * 0.75, 1.2)
	detect_radius *= 1.15
	_boss_slam_timer = 0.0
	_charge_timer = minf(_charge_timer, 0.4)
	alert_label.text = "!!!"
	_telegraph(Kind.BOSS)
	if ParticleManager.instance != null:
		ParticleManager.instance.spawn_impact_flesh(global_position, Vector2.ZERO)


## Carga telegrafiada del jefe (boss_attack, fase 1 y 2). Reutiliza el mismo
## aviso visual/sonoro de Capa 1 (`_telegraph`) con el kind del boss.
func _start_boss_charge(target_pos: Vector2) -> void:
	if _charge_timer > 0.0:
		return
	_charge_timer = charge_cooldown * (0.7 if phase == 2 else 1.0)
	_charge_duration = 1.2 if phase == 2 else 1.0
	_is_charging = true
	_boss_charge_hit = false
	_charge_direction = (target_pos - global_position).normalized()
	_telegraph(Kind.BOSS)
	if zombie_visual != null:
		zombie_visual.play_attack()
	if ParticleManager.instance != null:
		ParticleManager.instance.spawn_impact_concrete(global_position, _charge_direction)


## Ataque adicional exclusivo de la fase 2: golpe de área telegrafiado.
func _boss_attack() -> void:
	if _boss_slam_timer > 0.0 or not _target_valid():
		return
	_boss_slam_timer = boss_slam_cooldown
	_telegraph(Kind.BOSS)
	if zombie_visual != null:
		zombie_visual.play_attack()
	if ParticleManager.instance != null:
		ParticleManager.instance.spawn_impact_flesh(global_position, Vector2.ZERO)
	if global_position.distance_to(target.global_position) > BOSS_SLAM_RANGE:
		return
	if target.has_method("receive_damage"):
		var damage: float = attack_damage * 0.65 * float(_difficulty.get("damage", 1.0))
		target.call("receive_damage", damage)


## Daño único al conectar la carga; la fase 2 pega más fuerte.
func _boss_impact_damage() -> void:
	if not _target_valid():
		return
	if target.has_method("receive_damage"):
		var damage: float = attack_damage * (1.15 if phase == 2 else 0.9)
		damage *= float(_difficulty.get("damage", 1.0))
		target.call("receive_damage", damage)
	if ParticleManager.instance != null:
		ParticleManager.instance.spawn_impact_flesh(global_position, _charge_direction)


# ---------------------------------------------------------------------------
# Navegacion y movement
# ---------------------------------------------------------------------------

func _navigate_to(destination: Vector2, move_speed: float) -> void:
	if not is_instance_valid(agent):
		return
	if _repath_timer <= 0.0 or _last_destination == Vector2.INF or destination.distance_squared_to(_last_destination) > 784.0:
		agent.target_position = destination
		_last_destination = destination
		_repath_timer = 0.25
	var next_point: Vector2 = agent.get_next_path_position()
	var direction: Vector2 = next_point - global_position
	if direction.length() > 0.001:
		velocity = direction.normalized() * move_speed
	else:
		velocity = Vector2.ZERO


func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 20.0:
		_pick_wander_target()
	_navigate_to(_wander_target, speed * _speed_multiplier() * 0.35)


func _pick_wander_target() -> void:
	var angle: float = randf() * TAU
	var radius: float = randf_range(30.0, 100.0)
	_wander_target = _spawn_position + Vector2(cos(angle), sin(angle)) * radius
	_wander_timer = randf_range(2.5, 5.0)


## Callbacks del Area2D: mantienen un conjunto local de vecinos, sin escanear
## el grupo "zombies" completo. El Area2D usa la capa 2, así que el filtro por
## grupo evita contar sondas de test u otros cuerpos que compartan la capa.
func _on_separation_body_entered(body: Node2D) -> void:
	if body == null or body == self or not body.is_in_group("zombies"):
		return
	if not _separation_neighbors.has(body):
		_separation_neighbors.append(body)


func _on_separation_body_exited(body: Node2D) -> void:
	_separation_neighbors.erase(body)


func _apply_separation() -> void:
	if _separation_neighbors.is_empty():
		return
	# Misma fórmula que antes; solo cambia la fuente de vecinos (locales, no globales).
	var separation: Vector2 = Vector2.ZERO
	var my_position: Vector2 = global_position
	for other in _separation_neighbors:
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector2 = my_position - other.global_position
		var gap_sq: float = away.length_squared()
		if gap_sq > 0.0001 and gap_sq < SEPARATION_RADIUS * SEPARATION_RADIUS:
			var gap: float = sqrt(gap_sq)
			separation += (away / gap) * (1.0 - gap / SEPARATION_RADIUS)
	velocity += separation * SEPARATION_FORCE * separation_scale


func _update_flash(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		modulate = Color.WHITE


# ---------------------------------------------------------------------------
# Tipos y dificultad
# ---------------------------------------------------------------------------

## Fija la escala del cubo por arquetipo en UNA operación atómica.
## `ZombieVisual.set_cube_base_scales()` aplica la escala Y actualiza la base
## que los FX restauran: así no depende del orden "asignar escala → set_type()"
## y un cambio de escala posterior nunca es pisado por un FX.
func _apply_cube_scale(scale_value: Vector2) -> void:
	if zombie_visual != null:
		zombie_visual.set_cube_base_scales(scale_value, scale_value)
		return
	body_visual.scale = scale_value
	nose.scale = scale_value


func _apply_kind() -> void:
	# Sincronizado aquí (no solo en _ready) porque las pruebas y el spawner
	# pueden asignar `kind` antes o después de la instanciación.
	is_boss = (kind == Kind.BOSS)
	if not is_boss:
		phase = 1
		enraged = false
	match kind:
		Kind.WALKER:
			speed = 80.0
			max_hp = 68.0
			attack_damage = 10.0
			attack_cooldown_time = 1.0
			detect_radius = 430.0
			lose_radius = 700.0
			body_visual.color = Color(0.62, 0.22, 0.18)
			nose.color = Color(0.8, 0.5, 0.45)
			_apply_cube_scale(Vector2(1.0, 1.0))
			spit_range = 0.0
			spit_damage = 0.0
			spit_cooldown = 0.0
			scream_radius = 0.0
			scream_cooldown = 0.0
			charge_speed = 0.0
			charge_cooldown = 0.0
			if zombie_visual != null:
				zombie_visual.set_type(ZombieVisual.ZombieType.WALKER)
			alert_label.text = "?"

		Kind.RUNNER:
			speed = 150.0
			max_hp = 30.0
			attack_damage = 7.0
			attack_cooldown_time = 0.8
			detect_radius = 560.0
			lose_radius = 800.0
			body_visual.color = Color(0.82, 0.58, 0.2)
			nose.color = Color(0.95, 0.8, 0.5)
			_apply_cube_scale(Vector2(0.82, 0.82))
			spit_range = 0.0
			spit_damage = 0.0
			spit_cooldown = 0.0
			scream_radius = 0.0
			scream_cooldown = 0.0
			charge_speed = 0.0
			charge_cooldown = 0.0
			if zombie_visual != null:
				zombie_visual.set_type(ZombieVisual.ZombieType.RUNNER)
			alert_label.text = "!"

		Kind.TANK:
			speed = 45.0
			max_hp = 250.0
			attack_damage = 25.0
			attack_cooldown_time = 1.5
			detect_radius = 350.0
			lose_radius = 600.0
			body_visual.color = Color(0.4, 0.4, 0.5)
			nose.color = Color(0.6, 0.6, 0.7)
			_apply_cube_scale(Vector2(1.5, 1.5))
			spit_range = 0.0
			spit_damage = 0.0
			spit_cooldown = 0.0
			scream_radius = 0.0
			scream_cooldown = 0.0
			charge_speed = 250.0
			charge_cooldown = 5.0
			if zombie_visual != null:
				zombie_visual.set_type(ZombieVisual.ZombieType.TANK)
			alert_label.text = "!!"

		Kind.SPITTER:
			speed = 70.0
			max_hp = 50.0
			attack_damage = 8.0
			attack_cooldown_time = 1.2
			detect_radius = 500.0
			lose_radius = 700.0
			body_visual.color = Color(0.4, 0.7, 0.4)
			nose.color = Color(0.6, 0.9, 0.6)
			_apply_cube_scale(Vector2(0.9, 0.9))
			spit_range = 300.0
			spit_damage = 15.0
			spit_cooldown = 3.0
			scream_radius = 0.0
			scream_cooldown = 0.0
			charge_speed = 0.0
			charge_cooldown = 0.0
			if zombie_visual != null:
				zombie_visual.set_type(ZombieVisual.ZombieType.SPITTER)
			alert_label.text = "~"

		Kind.SCREAMER:
			speed = 100.0
			max_hp = 40.0
			attack_damage = 12.0
			attack_cooldown_time = 1.0
			detect_radius = 400.0
			lose_radius = 650.0
			body_visual.color = Color(0.8, 0.3, 0.8)
			nose.color = Color(1.0, 0.5, 1.0)
			_apply_cube_scale(Vector2(0.85, 0.85))
			spit_range = 0.0
			spit_damage = 0.0
			spit_cooldown = 0.0
			scream_radius = 500.0
			scream_cooldown = 8.0
			charge_speed = 0.0
			charge_cooldown = 0.0
			if zombie_visual != null:
				zombie_visual.set_type(ZombieVisual.ZombieType.SCREAMER)
			alert_label.text = "~~"

		Kind.BOSS:
			# "Tanque Alfa": vida alta, velocidad media, daño alto y detección
			# amplia. Parte en fase 1; el 50 % de vida dispara la fase 2.
			speed = 110.0
			max_hp = 800.0
			attack_damage = 32.0
			attack_cooldown_time = 1.1
			detect_radius = 700.0
			lose_radius = 1000.0
			body_visual.color = Color(0.431, 0.09, 0.071)   # BLOOD_DARK
			nose.color = Color(0.604, 0.671, 0.714)          # STEEL_LIGHT
			_apply_cube_scale(Vector2(1.9, 1.9))
			spit_range = 0.0
			spit_damage = 0.0
			spit_cooldown = 0.0
			scream_radius = 0.0
			scream_cooldown = 0.0
			charge_speed = 330.0
			charge_cooldown = 4.5
			boss_slam_cooldown = BOSS_SLAM_COOLDOWN
			phase = 1
			enraged = false
			_boss_slam_timer = 0.0
			_boss_charge_hit = false
			if zombie_visual != null:
				zombie_visual.set_type(ZombieVisual.ZombieType.BOSS)
			alert_label.text = "!!"

	# Perfil táctico por arquetipo (independiente del aspecto visual).
	match kind:
		Kind.WALKER:
			flank_strength = 0.18
			preferred_range = 0.0
			separation_scale = 1.0
		Kind.RUNNER:
			flank_strength = 0.42
			preferred_range = 0.0
			separation_scale = 0.9
		Kind.TANK:
			flank_strength = 0.0
			preferred_range = 0.0
			separation_scale = 1.7
		Kind.SPITTER:
			flank_strength = 0.55
			preferred_range = 210.0
			separation_scale = 1.2
		Kind.SCREAMER:
			flank_strength = 0.30
			preferred_range = 0.0
			separation_scale = 1.1
		Kind.BOSS:
			flank_strength = 0.0
			preferred_range = 0.0
			separation_scale = 2.2

	_base_max_hp = max_hp
	hp = max_hp


## Recompensa por riesgo: tanques sueltan chatarra, escupidores tela y el
## resto tiene una probabilidad pequeña. Usa el flujo 'loot' para que el botín
## siga siendo determinista dentro de la misma partida.
func _drop_loot() -> void:
	if not is_instance_valid(Inventory):
		return
	var rng: RandomNumberGenerator = GameState.rng(&"loot")
	var item_id: String = ""
	var amount: int = 1
	match kind:
		Kind.TANK:
			item_id = "scrap"
			amount = rng.randi_range(2, 3)
		Kind.BOSS:
			# El jefe asegura una recompensa proporcional a su riesgo.
			item_id = "scrap"
			amount = rng.randi_range(5, 8)
		Kind.SPITTER:
			item_id = "cloth"
			amount = rng.randi_range(1, 2)
		_:
			if rng.randf() < 0.18:
				item_id = "scrap" if rng.randf() < 0.6 else "cloth"
	if item_id == "":
		return
	var added: int = Inventory.add_item(item_id, amount, true)
	if added > 0:
		EventBus.notification.emit("Botín: %s +%d" % [Inventory.display_name(item_id), added])


## Consume GameState.difficulty() de forma defensiva. Acepta numero, texto o
## diccionario; si no existe el autoload, todos los multiplicadores son 1.0.
func _refresh_difficulty() -> void:
	_difficulty_refresh = 4.0
	var old_health: float = float(_difficulty.get("health", 1.0))
	var profile: Dictionary = {
		"speed": 1.0, "perception": 1.0, "damage": 1.0, "health": 1.0
	}
	var provider: Object = null
	var tree: SceneTree = get_tree()
	if tree != null and tree.root != null:
		provider = tree.root.get_node_or_null("GameState")
	if provider == null and Engine.has_singleton("GameState"):
		provider = Engine.get_singleton("GameState")
	if provider == null or not provider.has_method("difficulty"):
		_difficulty = profile
		return

	# Fuente canónica: GameState.multiplier sustituye a los tres mapeadores
	# incompatibles. El bloque defensivo de abajo queda solo como fallback.
	if provider.has_method("multiplier"):
		profile["speed"] = provider.call("multiplier", &"zombie", &"speed")
		profile["perception"] = provider.call("multiplier", &"zombie", &"perception")
		profile["damage"] = provider.call("multiplier", &"zombie", &"damage")
		profile["health"] = provider.call("multiplier", &"zombie", &"health")
		var canonical_health: float = float(profile["health"])
		_difficulty = profile
		if _base_max_hp > 0.0 and not is_equal_approx(old_health, canonical_health) and hp > 0.0:
			var ratio: float = canonical_health / maxf(old_health, 0.001)
			max_hp = _base_max_hp * canonical_health
			hp = clampf(hp * ratio, 1.0, max_hp)
		return

	var raw: Variant = provider.call("difficulty")
	if raw is Dictionary:
		var data: Dictionary = raw
		profile["speed"] = _diff_factor(data, ["zombie_speed", "speed", "speed_multiplier"], 1.0)
		profile["perception"] = _diff_factor(data, ["zombie_perception", "perception", "detection", "detect"], 1.0)
		profile["damage"] = _diff_factor(data, ["zombie_damage", "damage", "damage_multiplier"], 1.0)
		profile["health"] = _diff_factor(data, ["zombie_health", "health", "hp"], 1.0)
	elif raw is float or raw is int:
		# GameState.difficulty() esta normalizado [0,1] (0 facil, 1 maximo).
		# Valores >1 se tratan como multiplicador directo, como en WorldDirector.
		var level: float = clampf(float(raw), 0.0, 3.0)
		var t: float
		if level <= 1.0:
			t = level
		else:
			t = clampf((level - 1.0) / 0.8, 0.0, 2.0)
		profile["speed"] = clampf(1.0 + t * 0.22, 0.85, 1.5)
		profile["perception"] = clampf(1.0 + t * 0.28, 0.85, 1.6)
		profile["damage"] = clampf(1.0 + t * 0.45, 0.8, 2.0)
		profile["health"] = clampf(1.0 + t * 0.40, 0.85, 1.9)
	elif raw is String:
		match String(raw).to_lower():
			"easy", "facil", "fácil", "novice":
				profile = {"speed": 0.9, "perception": 0.85, "damage": 0.75, "health": 0.85}
			"hard", "dificil", "difícil", "veteran":
				profile = {"speed": 1.15, "perception": 1.2, "damage": 1.35, "health": 1.3}
			"nightmare", "pesadilla", "extreme":
				profile = {"speed": 1.35, "perception": 1.4, "damage": 1.7, "health": 1.6}
	var new_health: float = float(profile.get("health", 1.0))
	_difficulty = profile
	# Si la dificultad cambia a mitad de partida, reescalamos vida sin revivir
	# zombies muertos ni alterar el tipo base.
	if _base_max_hp > 0.0 and not is_equal_approx(old_health, new_health) and hp > 0.0:
		var ratio: float = new_health / maxf(old_health, 0.001)
		max_hp = _base_max_hp * new_health
		hp = clampf(hp * ratio, 1.0, max_hp)


func _diff_factor(data: Dictionary, keys: Array, fallback: float) -> float:
	for key in keys:
		if not data.has(key):
			continue
		var value: Variant = data[key]
		if value is float or value is int:
			return clampf(float(value), 0.5, 2.5)
	return fallback


func _die() -> void:
	_dead = true
	state = State.DEAD
	remove_from_group("zombies")
	# Al quitar la capa 2, los Area2D ajenos reciben body_exited y nos descartan.
	# Aquí además dejamos de monitorizar y liberamos nuestras propias referencias.
	_separation_neighbors.clear()
	if separation_area != null:
		separation_area.monitoring = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	alert_label.visible = false
	EventBus.zombie_died.emit(self)
	_drop_loot()

	if zombie_visual != null:
		zombie_visual.play_death()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_property(self, "scale", Vector2(0.6, 0.6), 0.3)
	tween.finished.connect(queue_free)
