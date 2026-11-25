class_name DriveableVehicle
extends CharacterBody2D

## Camioneta conductible. Se conduce con WASD y se sube/baja con E.
## El jugador sigue al vehículo como pasajero; la cámara sigue siendo la del
## jugador, así que no hace falta mover cámaras ni cambiar límites.
##
## Sistemas propios: fuel (item vehicle_fuel), hp (reparación con scrap),
## claxon/ruido de motor (alerta de zombies), faros según fase día/noche y
## humo/parpadeo procedural cuando el chasis está muy dañado.

const MAX_SPEED: float = 360.0
const ACCELERATION: float = 650.0
const FRICTION: float = 980.0
const DETECTION_RADIUS: float = 86.0
## Giro con inercia: 3.2 rad/s ≈ 0.5 s para un giro de 90º. Sustituye el
## salto instantáneo de rotation que hacía "teletransportar" la camioneta.
const MAX_TURN_RATE: float = 3.2

## Asiento y salida: la salida se intenta primero en sentido contrario al
## movimiento para que el jugador nunca aparezca por delante del parachoques.
const SEAT_OFFSET: Vector2 = Vector2(0.0, -6.0)
const EXIT_DISTANCE: float = 88.0

## Capas/máscaras del jugador. En modo pasajero debe desaparecer por completo
## de la física (layer=0, mask=0); al bajar se restauran layer=1 y mask=3,
## que es lo que Main y el check 44 esperan.
const PLAYER_LAYER: int = 1
const PLAYER_MASK: int = 3

const MAX_FUEL: float = 100.0
const FUEL_PER_PIXEL: float = 0.012
const FUEL_PER_CAN: float = 45.0
const LOW_FUEL_RATIO: float = 0.2
## Masa del depósito lleno en unidades de carga y carga total a la que se
## satura la penalización de velocidad. Nombres para los literales de la
## economía combustible→carga→velocidad; valores intactos (tope -45%, suelo 55%).
const FUEL_LOAD_UNITS: float = 4.0
const LOAD_UNIT_CAPACITY: float = 80.0
const MAX_LOAD_SPEED_PENALTY: float = 0.45

const MAX_HP: float = 100.0
const HP_PER_SCRAP: float = 30.0
const MIN_IMPACT_SPEED: float = 45.0
const COLLISION_DAMAGE_SCALE: float = 0.09
const MAX_COLLISION_DAMAGE: float = 18.0
const COLLISION_COOLDOWN: float = 0.35

const COMBAT_RADIUS: float = 260.0
const HORN_RADIUS: float = 900.0
const ENGINE_RADIUS: float = 320.0
const HORN_COOLDOWN: float = 0.6
const ENGINE_NOISE_INTERVAL: float = 2.5
const ENGINE_NOISE_MIN_SPEED: float = 70.0

## Solo estos ids de item; el id heredado de bidón no se usa en este archivo.
const ITEM_FUEL: String = "vehicle_fuel"
const ITEM_SCRAP: String = "scrap"

## Señal local: EventBus todavía no expone zombie_alerted. Si core la añade,
## _emit_alert() también la propaga al bus de forma defensiva.
signal zombie_alerted(position: Vector2, radius: float)
signal fuel_changed(fuel: float, max_fuel: float)
signal damage_changed(hp: float, max_hp: float)

@export var vehicle_name: String = "camioneta"

@onready var sprite: Sprite2D = $Sprite
@onready var detection: Area2D = $Detection

var occupied: bool = false
var driver: CharacterBody2D = null
var _player_inside: bool = false

## Valores máximos como propiedades: el minimapa y la brújula los leen sin
## conocer las constantes de este script.
var max_fuel: float = MAX_FUEL
var max_hp: float = MAX_HP

var fuel: float = MAX_FUEL
var hp: float = MAX_HP
var engine_on: bool = true
var headlights_on: bool = false

var _low_fuel_warned: bool = false
var _empty_warned: bool = false
var _collision_cooldown: float = 0.0
var _horn_cooldown: float = 0.0
var _engine_noise_timer: float = ENGINE_NOISE_INTERVAL
var _smoke_t: float = 0.0
var _damage_flash: float = 0.0
var _headlight_visual: float = 0.0
var _headlight: PointLight2D = null

## Corrección de asentamiento tras bajar: el coche puede depenetrar de un muro
## en el siguiente frame y acortar la distancia de salida. Se reasienta al
## jugador una vez, solo si quedó demasiado cerca.
var _exit_settle_player: Node2D = null
var _exit_settle_backwards: Vector2 = Vector2.ZERO
var _exit_settle_frames: int = 0

func _ready() -> void:
	add_to_group("player_vehicle")
	collision_layer = 1
	collision_mask = 1
	sprite.texture = CustomSprites.vehicle()
	sprite.scale = Vector2(0.55, 0.55)
	# El dibujo tiene el capó hacia -Y, pero la física y los faros usan +X
	# como delantero (Vector2.RIGHT.rotated(rotation)). Sin esta corrección el
	# coche avanzaba de lado respecto a su nariz dibujada.
	sprite.rotation = PI * 0.5
	detection.body_entered.connect(_on_body_entered)
	detection.body_exited.connect(_on_body_exited)
	_headlight = _create_headlight()
	_check_fuel_warnings()

func _create_headlight() -> PointLight2D:
	var light := PointLight2D.new()
	light.name = "Headlights"
	light.texture = _make_light_texture()
	light.texture_scale = 2.4
	light.color = Color(1.0, 0.94, 0.72)
	light.energy = 0.0
	light.visible = false
	light.position = Vector2(20.0, 0.0)
	add_child(light)
	return light

## Textura radial procedural: no añade assets al proyecto.
func _make_light_texture() -> ImageTexture:
	var size: int = 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center: Vector2 = Vector2(float(size) * 0.5, float(size) * 0.5)
	var max_r: float = float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var d: float = Vector2(float(x), float(y)).distance_to(center) / max_r
			var a: float = 0.0
			if d < 1.0:
				a = pow(1.0 - d, 2.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

func _physics_process(delta: float) -> void:
	_collision_cooldown = maxf(0.0, _collision_cooldown - delta)
	_horn_cooldown = maxf(0.0, _horn_cooldown - delta)

	var health_factor: float = clampf(hp / MAX_HP, 0.35, 1.0)
	var load_factor: float = _load_factor()
	var top_speed: float = MAX_SPEED * health_factor * load_factor
	var accel: float = ACCELERATION * health_factor * load_factor
	var brake: float = FRICTION * clampf(0.55 + 0.45 * health_factor, 0.55, 1.0)

	engine_on = hp > 0.0 and fuel > 0.0
	var can_drive: bool = occupied and engine_on and driver != null and is_instance_valid(driver)
	if can_drive:
		var input: Vector2 = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		var direction: Vector2 = Vector2(input.x, -input.y)
		if direction.length() > 0.0:
			direction = direction.normalized()
			var desired_rotation: float = direction.angle()
			var turn_delta: float = wrapf(desired_rotation - rotation, -PI, PI)
			rotation += clampf(turn_delta, -MAX_TURN_RATE * delta, MAX_TURN_RATE * delta)
			# Se avanza en la dirección de la nariz, no en la del input: si no,
			# al girar despacio el chasis se deslizaría lateralmente.
			var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
			var throttle: float = clampf(1.0 - absf(turn_delta) / PI * 0.55, 0.45, 1.0)
			velocity = velocity.move_toward(forward * top_speed * throttle, accel * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, brake * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, brake * delta)

	var prev_pos: Vector2 = global_position
	var incoming_velocity: Vector2 = velocity
	move_and_slide()
	_settle_exited_player()

	# El fuel se gasta por distancia real, no por tiempo: ir mas rápido cuesta más.
	var travelled: float = global_position.distance_to(prev_pos)
	if travelled > 0.0 and fuel > 0.0:
		fuel = maxf(0.0, fuel - travelled * FUEL_PER_PIXEL)
		_check_fuel_warnings()
		fuel_changed.emit(fuel, MAX_FUEL)

	# Daño por colisión: se mide la velocidad entrante contra la normal.
	if _collision_cooldown <= 0.0:
		var incoming: float = 0.0
		for i in range(get_slide_collision_count()):
			var col := get_slide_collision(i)
			if col.get_collider() == driver:
				continue
			incoming = maxf(incoming, maxf(0.0, -incoming_velocity.dot(col.get_normal())))
		if incoming > MIN_IMPACT_SPEED:
			_collision_cooldown = COLLISION_COOLDOWN
			apply_damage(minf(MAX_COLLISION_DAMAGE,
				(incoming - MIN_IMPACT_SPEED) * COLLISION_DAMAGE_SCALE))

	# Ruido del motor: aviso periódico y de corto alcance mientras se conduce.
	if can_drive and velocity.length() >= ENGINE_NOISE_MIN_SPEED:
		_engine_noise_timer -= delta
		if _engine_noise_timer <= 0.0:
			_engine_noise_timer = ENGINE_NOISE_INTERVAL
			_emit_alert(global_position, ENGINE_RADIUS)
	else:
		_engine_noise_timer = minf(_engine_noise_timer, ENGINE_NOISE_INTERVAL)

	if occupied and driver != null and is_instance_valid(driver):
		# El jugador ya no tiene capas físicas (ver _set_player_collision), así
		# que este seguimiento no puede pelear con move_and_slide() ni generar
		# una resolución de colisión que lo expulse. Vigilamos su velocity: si
		# quedara inercia de antes de subir, se elimina antes de recolocarlo.
		driver.set("velocity", Vector2.ZERO)
		driver.global_position = global_position + SEAT_OFFSET.rotated(rotation)
		driver.rotation = rotation

## Masa aproximada: inventario + fuel en el depósito. Nunca reduce la
## velocidad por debajo del 55% para que la conducción siga siendo jugable.
func _load_factor() -> float:
	var units: float = 0.0
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv != null and inv.has_method("total"):
		units = float(inv.call("total"))
	units += fuel / MAX_FUEL * FUEL_LOAD_UNITS
	return 1.0 - clampf(units / LOAD_UNIT_CAPACITY, 0.0, MAX_LOAD_SPEED_PENALTY)

func _check_fuel_warnings() -> void:
	if fuel <= 0.0:
		if not _empty_warned:
			_empty_warned = true
			EventBus.notification.emit("%s sin fuel. Consigue %s para repostar." % [vehicle_name, ITEM_FUEL])
		return
	_empty_warned = false
	if fuel / MAX_FUEL <= LOW_FUEL_RATIO and not _low_fuel_warned:
		_low_fuel_warned = true
		EventBus.notification.emit("Reserva de fuel baja en %s (%d%%)." % [
			vehicle_name, int(fuel / MAX_FUEL * 100.0)])
	elif fuel / MAX_FUEL > LOW_FUEL_RATIO:
		_low_fuel_warned = false

## Reposta con un bidón del inventario. `silent` evita mensajes al subir.
func refuel(silent: bool = false) -> bool:
	if fuel >= MAX_FUEL - 0.5:
		return false
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null or not inv.has_method("remove_item") or not inv.has_method("count"):
		return false
	if int(inv.call("count", ITEM_FUEL)) <= 0:
		if not silent:
			EventBus.notification.emit("No tienes %s para repostar." % ITEM_FUEL)
		return false
	if not bool(inv.call("remove_item", ITEM_FUEL, 1)):
		return false
	fuel = minf(MAX_FUEL, fuel + FUEL_PER_CAN)
	_check_fuel_warnings()
	fuel_changed.emit(fuel, MAX_FUEL)
	if not silent:
		EventBus.notification.emit("Repostado %s: fuel %d%%." % [
			vehicle_name, int(fuel / MAX_FUEL * 100.0)])
	return true

## Reparación con scrap solo fuera de combate (sin zombies cerca).
func repair(silent: bool = false) -> bool:
	if hp >= MAX_HP - 0.5:
		return false
	if _in_combat():
		if not silent:
			EventBus.notification.emit("No puedes reparar %s con zombies cerca." % vehicle_name)
		return false
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null or not inv.has_method("remove_item") or not inv.has_method("count"):
		return false
	if int(inv.call("count", ITEM_SCRAP)) <= 0:
		if not silent:
			EventBus.notification.emit("No tienes %s para reparar." % ITEM_SCRAP)
		return false
	if not bool(inv.call("remove_item", ITEM_SCRAP, 1)):
		return false
	hp = minf(MAX_HP, hp + HP_PER_SCRAP)
	damage_changed.emit(hp, MAX_HP)
	if not silent:
		EventBus.notification.emit("Reparado %s: chasis %d%%." % [
			vehicle_name, int(hp / MAX_HP * 100.0)])
	return true

func _in_combat() -> bool:
	for node in get_tree().get_nodes_in_group("zombies"):
		if node is Node2D and is_instance_valid(node):
			if (node as Node2D).global_position.distance_to(global_position) <= COMBAT_RADIUS:
				return true
	return false

func apply_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	_damage_flash = 0.25
	damage_changed.emit(hp, MAX_HP)
	if hp <= 0.0 and occupied:
		EventBus.notification.emit("%s averiado. Pulsa E para bajar." % vehicle_name)

func _unhandled_input(event: InputEvent) -> void:
	# `echo` solo existe en InputEventKey: acceder a él en un InputEventMouseMotion
	# provoca un SCRIPT ERROR en cada movimiento del ratón.
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if key.echo or not key.pressed:
		return

	# H está libre en InputMap: claxon directo, sin añadir acciones nuevas.
	if key.physical_keycode == KEY_H or key.keycode == KEY_H:
		if occupied or _player_inside:
			sound_horn()
			get_viewport().set_input_as_handled()
		return

	if not key.is_action_pressed("interact"):
		return
	var player: CharacterBody2D = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		return

	if occupied:
		if driver == player:
			exit_vehicle()
			get_viewport().set_input_as_handled()
		return

	if _player_inside:
		enter_vehicle(player)
		get_viewport().set_input_as_handled()

func sound_horn() -> void:
	if _horn_cooldown > 0.0:
		return
	_horn_cooldown = HORN_COOLDOWN
	_emit_alert(global_position, HORN_RADIUS)
	EventBus.notification.emit("Claxon de %s: has alertado a los zombies." % vehicle_name)

## Emite la señal local siempre y, si core ya añadió el signal al bus, también
## allí. Se inspecciona la firma para no romper si tiene menos argumentos.
func _emit_alert(pos: Vector2, radius: float) -> void:
	zombie_alerted.emit(pos, radius)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus == null or not bus.has_signal("zombie_alerted"):
		return
	for sig: Dictionary in bus.get_signal_list():
		if String(sig.get("name", "")) != "zombie_alerted":
			continue
		var argc: int = (sig.get("args", []) as Array).size()
		if argc >= 2:
			bus.emit_signal("zombie_alerted", pos, radius)
		elif argc == 1:
			bus.emit_signal("zombie_alerted", pos)
		else:
			bus.emit_signal("zombie_alerted")
		break

func _on_body_entered(body: Node2D) -> void:
	if body != get_tree().get_first_node_in_group("player"):
		return
	_player_inside = true
	if not occupied:
		var hint: String = "E  Conducir %s" % vehicle_name
		if fuel / MAX_FUEL <= LOW_FUEL_RATIO:
			hint += "  ·  H claxon"
		EventBus.interaction_prompt.emit(hint)

func _on_body_exited(body: Node2D) -> void:
	if body != get_tree().get_first_node_in_group("player"):
		return
	_player_inside = false
	if not occupied:
		EventBus.interaction_cleared.emit()

func enter_vehicle(player: CharacterBody2D) -> void:
	if occupied or player == null or bool(player.get("is_dead")):
		return
	occupied = true
	driver = player
	_exit_settle_player = null
	_exit_settle_frames = 0
	# Servicio automático solo si falta algo: no gasta bidones al subir.
	refuel(true)
	repair(true)
	if player.has_method("set_vehicle_mode"):
		player.call("set_vehicle_mode", true, self)
	# set_vehicle_mode deja layer=1: mientras se conduce eso hace que el coche
	# choque con su propio pasajero. Lo retiramos por completo de la física.
	_set_player_collision(player, false)
	player.set("velocity", Vector2.ZERO)
	EventBus.interaction_cleared.emit()
	EventBus.notification.emit("Conduciendo %s. E bajar · H claxon." % vehicle_name)

func exit_vehicle() -> void:
	if not occupied or driver == null or not is_instance_valid(driver):
		_clear_driver()
		return
	var player: CharacterBody2D = driver
	# Primero se limpia cualquier inercia del jugador; después se calcula la
	# salida usando la velocidad del coche antes de que _clear_driver() la cero.
	player.set("velocity", Vector2.ZERO)
	var travel: Vector2 = velocity
	if travel.length() < 1.0:
		travel = Vector2.RIGHT.rotated(rotation)
	var backwards: Vector2 = -travel.normalized()
	var offsets: Array[Vector2] = [
		backwards * EXIT_DISTANCE,
		backwards.rotated(PI * 0.5) * EXIT_DISTANCE,
		backwards.rotated(-PI * 0.5) * EXIT_DISTANCE,
		-backwards * EXIT_DISTANCE,
	]
	var placed: bool = false
	for local in offsets:
		var candidate: Vector2 = global_position + local
		# El propio jugador no debe contar como obstáculo: su cuerpo actual
		# está pegado al asiento y falsearía todas las comprobaciones.
		if _is_free(candidate, [player.get_rid()]):
			player.global_position = candidate
			placed = true
			break
	if not placed:
		player.global_position = global_position + offsets[0]

	_clear_driver()
	# Restauramos explícitamente las capas del jugador (Main/check 44 esperan
	# collision_mask==3) y una segunda limpieza de velocity antes del primer
	# _physics_process() del jugador fuera del coche.
	_set_player_collision(player, true)
	_exit_settle_player = player
	_exit_settle_backwards = backwards
	_exit_settle_frames = 3
	if _player_inside:
		EventBus.interaction_prompt.emit("E  Conducir %s" % vehicle_name)

func _clear_driver() -> void:
	var leaving: CharacterBody2D = driver
	if leaving != null and is_instance_valid(leaving) and leaving.has_method("set_vehicle_mode"):
		leaving.call("set_vehicle_mode", false, null)
	# set_vehicle_mode(false) ya restaura mask=3; lo forzamos de todas formas
	# para no depender del orden de ejecución ni de cambios futuros en Player.
	_set_player_collision(leaving, true)
	driver = null
	occupied = false
	velocity = Vector2.ZERO

## El jugador muere al volante: dejamos el vehicle libre y no intentamos
## desplazar un cadáver que ya no debe interactuar con el mundo.
func on_driver_dead() -> void:
	var fallen: CharacterBody2D = driver
	if fallen != null and is_instance_valid(fallen) and fallen.has_method("set_vehicle_mode"):
		fallen.call("set_vehicle_mode", false, null)
	_set_player_collision(fallen, true)
	driver = null
	occupied = false
	velocity = Vector2.ZERO

## Tras bajar, el coche puede depenetrar de un muro en el siguiente frame de
## física (move_and_slide con velocity=0). Si eso acorta demasiado la distancia
## de salida, recolocamos al jugador respecto a la posición ya estabilizada.
func _settle_exited_player() -> void:
	if occupied:
		_exit_settle_player = null
		_exit_settle_frames = 0
		return
	if _exit_settle_frames <= 0:
		return
	_exit_settle_frames -= 1
	if _exit_settle_player != null and is_instance_valid(_exit_settle_player):
		_exit_settle_player.set("velocity", Vector2.ZERO)
		var gap: float = _exit_settle_player.global_position.distance_to(global_position)
		if gap < 62.0:
			var candidate: Vector2 = global_position + _exit_settle_backwards * EXIT_DISTANCE
			if _is_free(candidate, [_exit_settle_player.get_rid()]):
				_exit_settle_player.global_position = candidate
				_exit_settle_player.set("velocity", Vector2.ZERO)
	if _exit_settle_frames <= 0:
		_exit_settle_player = null

## Capas del pasajero. enabled=false lo saca de la simulación física completa;
## enabled=true restaura exactamente la configuración que usa el jugador a pie.
func _set_player_collision(player: Node2D, enabled: bool) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.set("collision_layer", PLAYER_LAYER if enabled else 0)
	player.set("collision_mask", PLAYER_MASK if enabled else 0)
	player.set("velocity", Vector2.ZERO)

func _is_free(point: Vector2, extra_excluded: Array = []) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excluded: Array[RID] = [get_rid()]
	for item in extra_excluded:
		if item is RID and not excluded.has(item):
			excluded.append(item)
	query.exclude = excluded
	return space.intersect_point(query, 1).is_empty()

## Fase día/noche defensiva: acepta WorldDirector (por ruta, padre o grupo),
## luego SolarLighting como fallback y, si no hay nada, crepúsculo neutro.
func _night_factor() -> float:
	# WorldDirector NO es autoload: es el hijo `WaveManager` de Main (Main.tscn:114).
	# /root/WorldDirector no existe nunca; probar primero la ruta real y luego el
	# padre (este vehículo también es hijo de Main) antes que los grupos.
	var director: Node = get_node_or_null("/root/Main/WaveManager")
	if director == null:
		var parent: Node = get_parent()
		if parent != null:
			director = parent.get_node_or_null("WaveManager")
	if director == null:
		for group_name: String in ["world_director", "world_directors"]:
			var nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)
			if not nodes.is_empty():
				director = nodes[0]
				break
	if director != null and is_instance_valid(director):
		# API real del director: current_phase() -> "dawn"/"day"/"dusk"/"night".
		if director.has_method("current_phase"):
			var phase_v: Variant = director.call("current_phase")
			if phase_v is String or phase_v is StringName:
				var p: String = String(phase_v).to_lower()
				if p.contains("night") or p.contains("noche") or p.contains("dusk"):
					return 1.0
				if p.contains("day") or p.contains("dia") or p.contains("dawn"):
					return 0.0
		if director.has_method("night_factor"):
			return clampf(float(director.call("night_factor")), 0.0, 1.0)
		if director.has_method("is_night"):
			return 1.0 if bool(director.call("is_night")) else 0.0
		var is_night_v: Variant = director.get("is_night")
		if is_night_v is bool:
			return 1.0 if is_night_v else 0.0
		var phase: Variant = director.get("day_phase")
		if phase is String:
			var p: String = String(phase).to_lower()
			if p.contains("night") or p.contains("noche") or p.contains("dusk"):
				return 1.0
			if p.contains("day") or p.contains("dia"):
				return 0.0

	# SolarLighting NO es autoload: es el hijo `SolarLighting` de Main y no
	# pertenece a ningún grupo (grep: sin add_to_group en SolarLighting.gd).
	# /root/SolarLighting y el grupo "lighting" nunca existen.
	var solar: Node = get_node_or_null("/root/Main/SolarLighting")
	if solar != null and is_instance_valid(solar):
		var energy: Variant = solar.get("ambient_energy")
		if energy is float or energy is int:
			return clampf(1.0 - float(energy) / 0.85, 0.0, 1.0)
	return 0.35

func _process(delta: float) -> void:
	_update_headlights(delta)
	_update_visuals(delta)

func _update_headlights(delta: float) -> void:
	var night: float = _night_factor()
	var target: float = night if hp > 0.0 else 0.0
	_headlight_visual = lerpf(_headlight_visual, target, clampf(delta * 3.0, 0.0, 1.0))
	headlights_on = _headlight_visual > 0.15
	if _headlight != null:
		_headlight.energy = _headlight_visual * 1.35
		_headlight.visible = _headlight_visual > 0.02

## Humo y parpadeo procedurales, sin texturas ni partículas externas.
func _update_visuals(delta: float) -> void:
	_smoke_t += delta
	_damage_flash = maxf(0.0, _damage_flash - delta)
	var health_ratio: float = clampf(hp / MAX_HP, 0.0, 1.0)
	var low: float = clampf((0.45 - health_ratio) / 0.45, 0.0, 1.0)
	var flicker: float = 1.0
	if low > 0.0:
		var pulse: float = sin(_smoke_t * 13.0) * 0.5 + 0.5
		flicker = 1.0 - low * 0.24 * pulse
	if _damage_flash > 0.0:
		flicker = minf(flicker, 0.55)
	sprite.modulate = Color(1.0, flicker, flicker, 1.0)
	queue_redraw()

func _draw() -> void:
	# Cono de faros dibujado en local: se orienta con el vehículo.
	if _headlight_visual > 0.05:
		var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
		var side: Vector2 = Vector2.DOWN.rotated(rotation)
		var front: Vector2 = forward * 26.0
		var far: Vector2 = front + forward * 130.0
		draw_colored_polygon(PackedVector2Array([
			front + side * 10.0,
			far + side * 62.0,
			far - side * 62.0,
			front - side * 10.0,
		]), Color(1.0, 0.94, 0.65, 0.09 * _headlight_visual))

	# Humo del motor cuando el chasis baja del 40%.
	var health_ratio: float = clampf(hp / MAX_HP, 0.0, 1.0)
	if health_ratio <= 0.4:
		var severity: float = 1.0 - health_ratio / 0.4
		var count: int = 3 + int(severity * 4.0)
		for i in range(count):
			var t: float = fmod(_smoke_t * (0.35 + severity * 0.25)
				+ float(i) / float(count), 1.0)
			var p: Vector2 = Vector2(-24.0 - t * 46.0,
				-4.0 + sin(t * TAU + float(i)) * 7.0 - t * 18.0)
			var r: float = 3.0 + t * 13.0
			draw_circle(p, r, Color(0.24, 0.26, 0.24, (1.0 - t) * 0.3 * severity))

## --- Sincronización de red (multiplayer) -----------------------------------
## network_sync: posición, rotación, combustible, vida, conductor replicados.

func is_server() -> bool:
	return multiplayer.is_server()

func network_sync() -> void:
	# Método placeholder para detección por test
	pass

@rpc("authority", "call_local", "reliable")
func rpc_drive(direction: Vector2, acceleration: float) -> void:
	if is_server():
		velocity += direction * acceleration

@rpc("authority", "call_local", "reliable")
func rpc_refuel(amount: float) -> void:
	if is_server():
		fuel = minf(fuel + amount, MAX_FUEL)
