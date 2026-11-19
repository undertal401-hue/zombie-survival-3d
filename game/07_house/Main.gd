extends Node2D

const ZOMBIE_SCENE: PackedScene = preload("res://03_zombies/Zombie.tscn")
const NAV_INSET := 42.0

## CAPA 2 / ÍTEM 12: índice de Zombie.Kind.BOSS y oleada a partir de la cual
## aparece el "Tanque Alfa". Se spawn EA (extra) al inicial: no altera
## ZOMBIE_SPAWN_COUNT ni la distribución ponderada de los 26 zombies de barrio.
const BOSS_KIND: int = 5
const BOSS_WAVE_THRESHOLD: int = 5

# Huecos de muro compartidos por paredes y puertas (valor unico).
const WALL_GAP_X: float = 1200.0
const WALL_GAP_WEST_Y: float = -600.0
const WALL_GAP_WIDTH: float = 200.0

# Umbrales de fase con histéresis: entrar en combate es rápido, salir requiere
# que no queden zombies cerca durante un rato (evita parpadeos de estado).
const COMBAT_ENTER_RADIUS: float = 300.0
const COMBAT_EXIT_RADIUS: float = 460.0
const COMBAT_HOLD_SECONDS: float = 2.0
const PHASE_SCAN_SECONDS: float = 0.25
const DISTANCE_FLUSH_SECONDS: float = 0.25
const MAX_FRAME_DISTANCE: float = 64.0

@export var zombie_count: int = Neighborhood.ZOMBIE_SPAWN_COUNT

var bake_ms: int = 0

# Hook del nodo `world`: el WorldDirector se inyecta desde fuera (ronda 2).
# Aquí solo se guarda la referencia; este archivo nunca lo crea.
var world_director: Node = null
# Alias que QA busca en Main/WaveManager (o Main/HordeManager). Lo inyecta
# el nodo `world` junto al WorldDirector; Main solo lo referencia.
var wave_manager: Node = null

# Mundo abierto: la camara cubre los 12600x12600 del bosque desde el primer
# frame. Cruzar una puerta solo cambia atmosfera, luz y avisos; nunca limites.
var _town_half: Vector2 = Vector2(2400.0, 1500.0)
var _world_half: Vector2 = Vector2(6300.0, 6300.0)
var _gates_occupied: int = 0
var _in_forest: bool = false

# Estado central: sondeos poco frecuentes para no castigar el perf.
var _phase_scan_timer: float = 0.0
var _combat_clear_timer: float = 0.0
var _pre_drive_phase: StringName = &"explore"
var _was_driving: bool = false
var _distance_accum: float = 0.0
var _distance_flush_timer: float = 0.0
var _last_player_position: Vector2 = Vector2.ZERO
## Una sola aparición del jefe por partida (oleada en que se generó, -1 = nunca).
var _boss_spawned_wave: int = -1

@onready var neighborhood: Neighborhood = $Level/Neighborhood
@onready var navigation_region: NavigationRegion2D = $NavigationRegion2D
@onready var ground: ColorRect = $Ground
@onready var player: CharacterBody2D = $Player
@onready var extraction: Area2D = $Extraction
@onready var forest: Node2D = $Level/Forest
@onready var solar_lighting: SolarLighting = $SolarLighting

func _ready() -> void:
	# Una partida nueva empieza en boot con estadísticas y azar reiniciados.
	# El autoload sobrevive a R, así que el reinicio lo hace este punto.
	GameState.reset_session()
	_connect_state_signals()
	GameState.register_actor(player, &"player")
	GameState.register_actor(extraction, &"extraction")
	var injected: Node = get_tree().get_first_node_in_group("world_director")
	if injected != null:
		set_world_director(injected)
	var manager: Node = get_tree().get_first_node_in_group("wave_manager")
	if manager == null:
		manager = get_node_or_null("WaveManager")
	if manager == null:
		manager = get_node_or_null("HordeManager")
	if manager != null:
		set_wave_manager(manager)

	Inventory.clear()
	Inventory.add_item("medkit", 1)
	# Las armas también son objetos: Inventory es la única fuente de verdad de
	# su condición y desgaste (Weapon._read_condition). Sin estas entradas los
	# cuatro .tres equipados no se gastarían nunca.
	for weapon_id: String in ["Machete", "Pistola 9mm", "Escopeta 12ga", "Fusil 5.56mm"]:
		Inventory.add_item(weapon_id, 1)
	# Sin munición de reserva de regalo: cada arma arranca solo con su cargador.
	# Los cartuchos (9mm/12ga/5.56) aparecen en botín y se pueden fabricar.
	_configure_world()
	# El director de mundo se conecta aquí, tras configurar el mundo y antes de
	# poblarlo, para que pueda aplicar clima/luz y programar su primera horda.
	if wave_manager != null:
		wave_manager.call("bind", forest, solar_lighting, player)
	_create_forest_gates()
	_bake_navigation()
	_spawn_zombies()
	
	# Dar pistola al jugador via WeaponController (ya se hace en _load_default_loadout)
	# El WeaponController ya equipa machete en slot 0 y pistola en slot 1
	pass
	
	# Refrescar HUD para mostrar munición inicial
	var hud := get_tree().get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("_refresh_resources"):
		hud.call("_refresh_resources")

	_last_player_position = player.global_position
	_was_driving = bool(player.get("is_driving"))
	# Mundo listo: el arranque termina y empieza la exploración.
	GameState.set_phase(&"drive" if _was_driving else &"explore")

## Conecta los eventos del juego con el estado central. Los subsistemas solo
## emiten; la contabilidad vive aquí para no repartir lógica por el proyecto.
func _connect_state_signals() -> void:
	EventBus.zombie_died.connect(_on_zombie_died_for_state)
	EventBus.player_damaged.connect(_on_player_damaged_for_state)
	# wave_started / horde_started los consume directamente GameState.
	# El jefe se engancha a horde_started (siempre nocturno) sin tocar
	# WorldDirector.gd: Main es el único punto de spawn extra permitido.
	if EventBus.has_signal("horde_started"):
		EventBus.horde_started.connect(_on_horde_started_for_boss)
	EventBus.craft_completed.connect(_on_craft_completed_for_state)
	EventBus.vehicle_state_changed.connect(_on_vehicle_state_changed_for_state)
	EventBus.zombie_alerted.connect(_on_zombie_alerted_for_state)
	EventBus.forest_entered.connect(_on_forest_entered_for_state)
	EventBus.forest_exited.connect(_on_forest_exited_for_state)
	EventBus.victory.connect(_on_victory_for_state)
	EventBus.game_over.connect(_on_game_over_for_state)

## Punto de inyección del WorldDirector creado por el nodo `world`.
func set_world_director(director: Node) -> void:
	world_director = director
	if director != null:
		GameState.register_actor(director, &"world_director")
		if director.has_method("start_wave"):
			set_wave_manager(director)

## Inyección del gestor de oleadas; el nodo `world` decide su nombre real.
func set_wave_manager(manager: Node) -> void:
	wave_manager = manager
	if manager != null:
		GameState.register_actor(manager, &"wave_manager")

## Puente único para iniciar oleadas. Si aún no hay manager, el evento llega
## igual al estado central, que se encarga de contarlo y subir la dificultad.
func start_wave(wave: int) -> void:
	if wave_manager != null and wave_manager.has_method("start_wave"):
		wave_manager.call("start_wave", wave)
	else:
		EventBus.wave_started.emit(wave)
	# Chequeo idempotente: si el manager emite horde_started, el guard evita
	# duplicar al jefe en la misma oleada.
	_maybe_spawn_boss_for_wave(wave)


## El boss aparece en hordas nocturnas avanzadas (wave >= 5). Se mantiene el
## spawn base intacto: los 26 zombies del barrio y su distribución de tipos
## siguen gobernados por Neighborhood.ZOMBIE_SPAWN_COUNT y _spawn_zombies().
func _on_horde_started_for_boss(wave) -> void:
	_maybe_spawn_boss_for_wave(int(wave))


func _maybe_spawn_boss_for_wave(wave: int) -> void:
	if _boss_spawned_wave >= 0:
		return
	var night: bool = false
	if wave_manager != null and wave_manager.has_method("current_phase"):
		night = String(wave_manager.call("current_phase")) == "night"
	var difficulty: float = float(GameState.difficulty())
	# horde_started ya implica noche; además se admite fase night con dificultad
	# alta aunque la numeración de oleadas venga de otro productor.
	if wave < BOSS_WAVE_THRESHOLD and not (night and difficulty >= 0.7):
		return
	if spawn_boss() != null:
		_boss_spawned_wave = wave


## API pública: genera "Tanque Alfa" con sus stats de Kind.BOSS (fase 1).
## `at_position` permite al director/world colocarlo en un punto concreto.
func spawn_boss(at_position: Vector2 = Vector2.ZERO) -> CharacterBody2D:
	if not is_inside_tree() or _boss_spawned_wave >= 0:
		return null
	var boss := ZOMBIE_SCENE.instantiate() as CharacterBody2D
	if boss == null:
		return null
	boss.name = "BossAlpha"
	var spawn_pos: Vector2 = at_position
	if spawn_pos == Vector2.ZERO:
		var points: Array[Vector2] = neighborhood.zombie_spawn_points()
		if points.is_empty():
			spawn_pos = Vector2(700.0, 0.0)
		else:
			# Entrada lejana al jugador: el aviso telegrafiado se lee mejor.
			spawn_pos = points[0]
			if player != null and is_instance_valid(player):
				var best: float = -1.0
				for point in points:
					var distance: float = point.distance_to(player.global_position)
					if distance > best:
						best = distance
						spawn_pos = point
	boss.position = spawn_pos
	boss.set("kind", BOSS_KIND)
	GameState.register_actor(boss, &"zombie")
	add_child(boss)
	_boss_spawned_wave = 0
	EventBus.priority_notification.emit("⚠ TANQUE ALFA ha entrado en el pueblo")
	return boss

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_update_travelled_distance(delta)
	_update_driving_phase()
	_update_combat_phase(delta)

## Distancia recorrida: se acumula y se vuelca periódicamente para no emitir
## señales en cada frame. Los teletransportes de QA no cuentan como progreso.
func _update_travelled_distance(delta: float) -> void:
	if bool(player.get("is_dead")):
		return
	var position_now: Vector2 = player.global_position
	_distance_accum += mini(position_now.distance_to(_last_player_position), MAX_FRAME_DISTANCE)
	_last_player_position = position_now
	_distance_flush_timer += delta
	if _distance_flush_timer >= DISTANCE_FLUSH_SECONDS:
		GameState.record("distance", _distance_accum)
		_distance_accum = 0.0
		_distance_flush_timer = 0.0

## Conducir cambia la fase a drive; al bajar se restaura la fase anterior.
func _update_driving_phase() -> void:
	var driving: bool = bool(player.get("is_driving"))
	if driving == _was_driving:
		return
	_was_driving = driving
	var current: StringName = GameState.phase()
	if driving:
		if current != &"death" and current != &"victory" and current != &"paused":
			_pre_drive_phase = current
		GameState.set_phase(&"drive")
	elif current == &"drive":
		GameState.set_phase(_pre_drive_phase)

## Zombies cerca => combate. Con histéresis y retardo para salir sin ruido.
func _update_combat_phase(delta: float) -> void:
	_phase_scan_timer += delta
	if _phase_scan_timer < PHASE_SCAN_SECONDS:
		return
	_phase_scan_timer = 0.0
	var current: StringName = GameState.phase()
	if current == &"death" or current == &"victory" or current == &"paused" or current == &"drive":
		_combat_clear_timer = 0.0
		return
	var radius: float = COMBAT_EXIT_RADIUS if current == &"combat" else COMBAT_ENTER_RADIUS
	if _has_near_zombie(radius):
		_combat_clear_timer = 0.0
		if current != &"combat":
			GameState.set_phase(&"combat")
		return
	_combat_clear_timer += PHASE_SCAN_SECONDS
	if _combat_clear_timer >= COMBAT_HOLD_SECONDS and current == &"combat":
		GameState.set_phase(&"explore")

func _has_near_zombie(radius: float) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var center: Vector2 = player.global_position
	var radius_sq: float = radius * radius
	for zombie in get_tree().get_nodes_in_group("zombies"):
		var node := zombie as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if center.distance_squared_to(node.global_position) <= radius_sq:
			return true
	return false

func _on_zombie_died_for_state(_zombie: Node2D) -> void:
	GameState.record("kill")

func _on_player_damaged_for_state(amount: float, _source: Node) -> void:
	GameState.record("damage", amount)

func _on_craft_completed_for_state(_item_id = null, amount = 1) -> void:
	GameState.record("craft", float(amount))

func _on_vehicle_state_changed_for_state(_vehicle = null, _fuel = 0, _hp = 0) -> void:
	GameState.record("vehicle_state")

func _on_zombie_alerted_for_state(_zombie = null, _source = null) -> void:
	GameState.record("zombie_alerted")

func _on_forest_entered_for_state() -> void:
	GameState.record("forest_entered")

func _on_forest_exited_for_state() -> void:
	GameState.record("forest_exited")

func _on_victory_for_state() -> void:
	GameState.set_phase(&"victory")

func _on_game_over_for_state() -> void:
	GameState.set_phase(&"death")

## Ajusta suelo, muros, inicio y extraccion al barrio; la camara al mundo completo.
func _configure_world() -> void:
	var total: Vector2 = neighborhood.map_size()
	var half: Vector2 = total * 0.5
	_town_half = half

	# El suelo cubre todo el mundo (pueblo + anillo de bosque). El pueblo
	# conserva su color original gracias a Forest/UrbanBase.
	var world_half: Vector2 = half
	if forest != null and forest.has_method("world_half"):
		world_half = forest.call("world_half")
	_world_half = world_half
	ground.position = -world_half
	ground.size = world_half * 2.0
	ground.color = Color(0.055, 0.075, 0.06, 1)

	# Estado de zona limpio (tambien tras un reinicio de partida).
	_in_forest = false
	_gates_occupied = 0
	if solar_lighting != null:
		solar_lighting.reset_to_defaults()

	# Tres huecos de 200 px fuera de las rutas que verifican los tests:
	# WallTop x=1200, WallLeft y=-600, WallBottom x=1200. WallRight sigue solido.
	_configure_wall($Level/WallTop, Vector2(0.0, -half.y + 20.0), Vector2(total.x, 40.0), WALL_GAP_X, WALL_GAP_WIDTH)
	_configure_wall($Level/WallBottom, Vector2(0.0, half.y - 20.0), Vector2(total.x, 40.0), WALL_GAP_X, WALL_GAP_WIDTH)
	_configure_wall($Level/WallLeft, Vector2(-half.x + 20.0, 0.0), Vector2(40.0, total.y), WALL_GAP_WEST_Y, WALL_GAP_WIDTH)
	_configure_wall($Level/WallRight, Vector2(half.x - 20.0, 0.0), Vector2(40.0, total.y))

	player.position = neighborhood.start_position()
	extraction.position = neighborhood.extraction_position()
	$Pickup1.position = neighborhood.start_position() + Vector2(90.0, -30.0)
	$Pickup2.position = neighborhood.plaza_position() + Vector2(0.0, 120.0)

	# Mundo abierto: limites del bosque (+-6300) tambien dentro del pueblo.
	_set_camera_limits(world_half)

func _set_camera_limits(half: Vector2) -> void:
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.limit_left = int(-half.x)
	camera.limit_top = int(-half.y)
	camera.limit_right = int(half.x)
	camera.limit_bottom = int(half.y)

## Configura un muro. Con gap_center/gap_width el muro se parte en dos tramos
## dejando un paso real (colision y visual) para acceder al bosque.
func _configure_wall(body: StaticBody2D, center: Vector2, wall_size: Vector2,
		gap_center: float = INF, gap_width: float = 0.0) -> void:
	body.position = center

	var horizontal: bool = wall_size.x >= wall_size.y
	var extent: float = wall_size.x if horizontal else wall_size.y
	var thickness: float = wall_size.y if horizontal else wall_size.x
	var has_gap: bool = gap_width > 0.0 and gap_center < 1000000.0
	var axis_center: float = center.x if horizontal else center.y
	var gap_local: float = gap_center - axis_center

	var segments: Array = []
	if has_gap:
		segments.append(Vector2(-extent * 0.5, gap_local - gap_width * 0.5))
		segments.append(Vector2(gap_local + gap_width * 0.5, extent * 0.5))
	else:
		segments.append(Vector2(-extent * 0.5, extent * 0.5))

	for i in range(segments.size()):
		var seg: Vector2 = segments[i]
		var length: float = seg.y - seg.x
		if length <= 0.0:
			continue
		var mid: float = (seg.x + seg.y) * 0.5
		var shape_center: Vector2
		var shape_size: Vector2
		if horizontal:
			shape_center = Vector2(mid, 0.0)
			shape_size = Vector2(length, thickness)
		else:
			shape_center = Vector2(0.0, mid)
			shape_size = Vector2(thickness, length)

		var collision: CollisionShape2D
		var visual: Polygon2D
		if i == 0:
			collision = body.get_node("CollisionShape2D") as CollisionShape2D
			visual = body.get_node("Visual") as Polygon2D
		else:
			collision = body.get_node_or_null("CollisionShape2DGate") as CollisionShape2D
			if collision == null:
				collision = CollisionShape2D.new()
				collision.name = "CollisionShape2DGate"
				body.add_child(collision)
			visual = body.get_node_or_null("VisualGate") as Polygon2D
			if visual == null:
				visual = Polygon2D.new()
				visual.name = "VisualGate"
				visual.color = Color(0.4, 0.4, 0.4, 1)
				body.add_child(visual)

		var rect := RectangleShape2D.new()
		rect.size = shape_size
		collision.shape = rect
		collision.position = shape_center

		var hx: float = shape_size.x * 0.5
		var hy: float = shape_size.y * 0.5
		visual.polygon = PackedVector2Array([
			shape_center + Vector2(-hx, -hy), shape_center + Vector2(hx, -hy),
			shape_center + Vector2(hx, hy), shape_center + Vector2(-hx, hy),
		])

## Crea las tres puertas. Cuelgan de Main (no de Level) para que el parser de
## navegacion no las trate como obstaculos del grupo nav_obstacles.
func _create_forest_gates() -> void:
	var gates := Node2D.new()
	gates.name = "ForestGates"
	add_child(gates)

	_make_gate(gates, "GateNorth", Vector2(WALL_GAP_X, -_town_half.y + 20.0), Vector2(WALL_GAP_WIDTH, 140.0))
	_make_gate(gates, "GateWest", Vector2(-_town_half.x + 20.0, WALL_GAP_WEST_Y), Vector2(140.0, WALL_GAP_WIDTH))
	_make_gate(gates, "GateSouth", Vector2(WALL_GAP_X, _town_half.y - 20.0), Vector2(WALL_GAP_WIDTH, 140.0))

func _make_gate(parent: Node2D, gate_name: String, pos: Vector2, size: Vector2) -> void:
	var area := Area2D.new()
	area.name = gate_name
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	area.add_child(shape)
	area.body_entered.connect(_on_gate_body_entered)
	area.body_exited.connect(_on_gate_body_exited)
	parent.add_child(area)

func _on_gate_body_entered(body: Node2D) -> void:
	if not _is_player_actor(body):
		return
	if _gates_occupied == 0:
		_gates_occupied = 1
		call_deferred("_refresh_forest_zone")
	else:
		_gates_occupied += 1

func _on_gate_body_exited(body: Node2D) -> void:
	if not _is_player_actor(body):
		return
	_gates_occupied = maxi(0, _gates_occupied - 1)
	if _gates_occupied == 0:
		call_deferred("_refresh_forest_zone")

## Durante la conducción el jugador sigue en el grupo "player", pero la
## camioneta también cruza la puerta: ambos cuerpos deben contar como uno.
func _is_player_actor(body: Node2D) -> bool:
	if body == player:
		return true
	if body != null and body.is_in_group("player_vehicle"):
		return bool(body.get("occupied"))
	return false

## La posicion del jugador es la fuente de verdad; las puertas solo disparan
## la reevaluacion, asi no hay parpadeos al cruzar varias zonas seguidas.
func _refresh_forest_zone() -> void:
	if player == null:
		return
	var outside: bool = true
	if forest != null and forest.has_method("in_forest"):
		outside = bool(forest.call("in_forest", player.global_position))
	if outside == _in_forest:
		return
	_in_forest = outside
	# Sin transicion de camara: los limites ya son del mundo completo.

	if _in_forest:
		EventBus.forest_entered.emit()
		if solar_lighting != null:
			solar_lighting.set_ambient_energy(0.62)
			solar_lighting.set_sun_energy(0.08)
		EventBus.notification.emit("¡Bosque: visibilidad reducida. Sigue la brújula.")
	else:
		EventBus.forest_exited.emit()
		if solar_lighting != null:
			solar_lighting.reset_to_defaults()
		EventBus.notification.emit("Vuelves a las calles del pueblo.")

## Genera el navmesh del barrio. El contorno queda dentro de los muros y las
## paredes (grupo "nav_obstacles") se restan como obstaculos.
func _bake_navigation() -> void:
	var started: int = Time.get_ticks_msec()
	var navpoly: NavigationPolygon = navigation_region.navigation_polygon
	navpoly.clear()

	# El contorno cubre todo el mundo; los muros siguen recortando el area y
	# sus tres huecos dejan pasar la navegacion hacia el anillo de bosque.
	var half: Vector2 = _world_half
	if not (forest != null and forest.has_method("in_forest")):
		half = neighborhood.map_size() * 0.5
	navpoly.add_outline(PackedVector2Array([
		Vector2(-half.x + NAV_INSET, -half.y + NAV_INSET),
		Vector2(half.x - NAV_INSET, -half.y + NAV_INSET),
		Vector2(half.x - NAV_INSET, half.y - NAV_INSET),
		Vector2(-half.x + NAV_INSET, half.y - NAV_INSET),
	]))

	navigation_region.bake_navigation_polygon(false)
	bake_ms = Time.get_ticks_msec() - started

func _spawn_zombies() -> void:
	var points: Array[Vector2] = neighborhood.zombie_spawn_points()
	var count: int = mini(zombie_count, points.size())
	
	# Distribución de tipos: 40% Walker, 20% Runner, 15% Tank, 15% Spitter, 10% Screamer
	var type_weights: Array = [
		{ "type": 0, "weight": 40 },  # WALKER
		{ "type": 1, "weight": 20 },  # RUNNER
		{ "type": 2, "weight": 15 },  # TANK
		{ "type": 3, "weight": 15 },  # SPITTER
		{ "type": 4, "weight": 10 },  # SCREAMER
	]
	
	var total_weight: int = 0
	for t in type_weights:
		total_weight += t.weight
	
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = zombie_count * 12345
	
	for i in range(count):
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody2D
		zombie.name = "Zombie%d" % (i + 1)
		zombie.position = points[i]
		GameState.register_actor(zombie, &"zombie")
		
		# Seleccionar tipo basado en pesos
		var r: int = rng.randi_range(1, total_weight)
		var acc: int = 0
		var selected_type: int = 0
		for t in type_weights:
			acc += t.weight
			if r <= acc:
				selected_type = t.type
				break
		
		zombie.set("kind", selected_type)
		add_child(zombie)
