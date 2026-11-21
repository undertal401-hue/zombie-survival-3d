extends Node

## QA temporal. Modos: inputtest, inspect, play, smoke, hunger, capture, perf, mechanics.
## `mechanics` imprime solo el contrato de sistemas nuevos (r1) sin batería completa.
## `smoke` corre el juego real con el autopiloto y cierra con el centinela
## `PLAY_SMOKE_COMPLETE` (lo exige el CI como prueba de que el bucle de juego
## se ejecutó entero, no solo el primer frame).

## Default EXACTAMENTE igual al directorio usado hoy (user://qa_shots).
const DEFAULT_CAPTURE_DIR := "user://qa_shots"
## QA_CAPTURE_DIR permite redirigir las capturas; sin entorno se usa el default.
var capture_dir: String = OS.get_environment("QA_CAPTURE_DIR") if not OS.get_environment("QA_CAPTURE_DIR").is_empty() else DEFAULT_CAPTURE_DIR

var _held: Dictionary = {}
var _main: Node
var _player: CharacterBody2D
var _hud: Node
var _extraction: ExtractionZone
var _neighborhood: Neighborhood
var _last_position: Vector2
var _distance_travelled: float = 0.0
var _victory_fired: bool = false
var _game_over_fired: bool = false

## Resultado del smoke de juego en vivo (QA_MODE=smoke): el CI exige codigo
## de salida 0 y el centinela `PLAY_SMOKE_COMPLETE`.
var _smoke_ok: bool = false
var _kills: int = 0
var _damage_events: int = 0
var _damage_total: float = 0.0
var _perf_samples: int = 0
var _perf_physics_sum: float = 0.0
var _perf_physics_max: float = 0.0
var _perf_nav_sum: float = 0.0
var _perf_nav_max: float = 0.0
var _chase_samples: int = 0
var _chase_physics_sum: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.victory.connect(func() -> void: _victory_fired = true)
	EventBus.game_over.connect(func() -> void: _game_over_fired = true)
	# R1-fix: el payload de `zombie_died` no se tipa (puede llegar liberado);
	# un receptor tipado rechazaría la llamada y lanzaría un error.
	EventBus.zombie_died.connect(func(_zombie) -> void: _kills += 1)
	EventBus.player_damaged.connect(func(amount: float, _source: Node) -> void:
		_damage_events += 1
		_damage_total += amount
	)
	# Esperar un frame antes de instanciar Main: durante _ready() el root aún
	# está "busy setting up children" y add_child() fallaría.
	await get_tree().process_frame
	_ensure_main_scene()
	for i in range(30):
		await get_tree().physics_frame
	var mode: String = OS.get_environment("QA_MODE")
	if mode == "":
		mode = "inspect"
	match mode:
		"inputtest":
			await _input_test()
		"inspect":
			await _inspect()
		"play":
			await _play()
		"smoke":
			await _smoke()
			get_tree().quit(0 if _smoke_ok else 1)
			return
		"hunger":
			await _hunger_test()
		"capture":
			await _capture_mode()
		"perf":
			await _perf_mode()
		"mechanics":
			_print_mechanics_ready()
			get_tree().quit(0)
			return
	# Resumen siempre presente: en r1 es informativo (PENDING/PARTIAL), nunca FAIL.
	_print_mechanics_ready()
	get_tree().quit(0)

## El harness se ejecuta como QA.tscn, así que current_scene es este nodo y no
## Main. Si el world no está cargado, lo instanciamos y lo fijamos como escena
## actual para que el resto de los modos encuentren HUD/Level/Neighborhood.
func _ensure_main_scene() -> void:
	var current: Node = get_tree().current_scene
	if current != null and current.get_node_or_null("Level/Neighborhood") != null:
		return
	var main: Node = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main

func _key_for(action: String) -> int:
	match action:
		"move_forward": return KEY_W
		"move_back": return KEY_S
		"move_left": return KEY_A
		"move_right": return KEY_D
		"sprint": return KEY_SHIFT
		"attack": return KEY_SPACE
		"interact": return KEY_E
		"use_medkit": return KEY_Q
		"use_food": return KEY_F
		"restart": return KEY_R
	return 0

func _set_action(action: String, pressed: bool) -> void:
	if bool(_held.get(action, false)) == pressed:
		return
	_held[action] = pressed
	var event := InputEventKey.new()
	event.physical_keycode = _key_for(action)
	event.pressed = pressed
	Input.parse_input_event(event)

func _release_all() -> void:
	for action in _held.keys():
		if _held[action]:
			_set_action(action, false)

func _input_test() -> void:
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	var start: Vector2 = player.global_position
	_set_action("move_right", true)
	for i in range(30):
		await get_tree().physics_frame
	_set_action("move_right", false)
	for i in range(3):
		await get_tree().physics_frame
	var delta: Vector2 = player.global_position - start
	print("INPUT_TEST start=%s end=%s delta=%s" % [str(start), str(player.global_position), str(delta)])
	print("INPUT_TEST_%s" % ("OK" if delta.x > 40.0 else "FAIL "))

func _inspect() -> void:
	var main := get_tree().current_scene
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	var extraction := get_tree().get_first_node_in_group("extraction") as ExtractionZone
	var neighborhood := main.get_node("Level/Neighborhood") as Neighborhood
	var map_size: Vector2 = neighborhood.map_size()
	print("MAP size=%s" % str(map_size))

	var houses: Array = get_tree().get_nodes_in_group("houses")
	var overlaps: int = 0
	var road_hits: Array[String] = []
	var access_fail: Array[String] = []
	var map_rid: RID = player.get_world_2d().navigation_map
	var start: Vector2 = player.global_position
	for i in range(houses.size()):
		var house := houses[i] as House
		var rect := Rect2(house.position - house.size * 0.5, house.size)
		for j in range(i + 1, houses.size()):
			var other := houses[j] as House
			if rect.intersects(Rect2(other.position - other.size * 0.5, other.size)):
				overlaps += 1
		for road in neighborhood._road_rects:
			if rect.intersects(road):
				road_hits.append("%s vs road %s" % [house.name, str(road)])
		var path := NavigationServer2D.map_get_path(map_rid, start, house.to_global(house.back_interior_point()), true)
		if path.size() <= 1 or path[path.size() - 1].distance_to(house.to_global(house.back_interior_point())) > 45.0:
			access_fail.append(house.name)
	print("HOUSES count=%d overlaps=%d road_hits=%d access_fail=%d" % [houses.size(), overlaps, road_hits.size(), access_fail.size()])
	for hit in road_hits.slice(0, 8):
		print("HOUSE_ROAD_HIT %s" % hit)
	for name in access_fail.slice(0, 8):
		print("HOUSE_ACCESS_FAIL %s" % name)

	var prop_hits: Array[String] = []
	var prop_names: Array[String] = []
	for child in neighborhood.get_children():
		var body := child as StaticBody2D
		if body == null:
			continue
		var rect := _body_rect(body)
		for road in neighborhood._road_rects:
			if rect.intersects(road):
				prop_hits.append("%s %s" % [body.name, str(rect)])
				break
	print("PROPS road_hits=%d" % prop_hits.size())
	for hit in prop_hits.slice(0, 12):
		print("PROP_ROAD_HIT %s" % hit)

	var spawns: Array[Vector2] = neighborhood.zombie_spawn_points()
	var bad_spawns: int = 0
	var space := player.get_world_2d().direct_space_state
	for spawn in spawns:
		var params := PhysicsPointQueryParameters2D.new()
		params.position = spawn
		params.collision_mask = 1
		params.collide_with_bodies = true
		params.collide_with_areas = false
		var hits := space.intersect_point(params, 4)
		var nav_distance: float = NavigationServer2D.map_get_closest_point(map_rid, spawn).distance_to(spawn)
		if not hits.is_empty() or nav_distance > 24.0:
			bad_spawns += 1
			print("BAD_SPAWN %s hits=%d nav=%.1f" % [str(spawn), hits.size(), nav_distance])
	print("SPAWNS count=%d bad=%d" % [spawns.size(), bad_spawns])

	var loots: Array = get_tree().get_nodes_in_group("loot")
	var fuel_paths: Array = []
	var fuel_sectors: Dictionary = {}
	for loot in loots:
		if str(loot.get("item_id")) != "combustible":
			continue
		var pos: Vector2 = loot.global_position
		var path := NavigationServer2D.map_get_path(map_rid, start, pos, true)
		var length: float = 0.0
		for k in range(1, path.size()):
			length += path[k - 1].distance_to(path[k])
		var sector: int = _sector_of(pos)
		fuel_sectors[sector] = true
		fuel_paths.append([length, pos, sector])
	fuel_paths.sort_custom(func(a, b): return a[0] < b[0])
	print("FUEL count=%d sectors=%d" % [fuel_paths.size(), fuel_sectors.size()])
	for entry in fuel_paths:
		print("FUEL_PATH len=%.0f pos=%s sector=%d" % [entry[0], str(entry[1]), entry[2]])
	var nearest_three: float = 0.0
	var nearest_sectors: Dictionary = {}
	for i in range(mini(3, fuel_paths.size())):
		nearest_three += fuel_paths[i][0]
		nearest_sectors[fuel_paths[i][2]] = true
	print("FUEL_NEAREST3 total_len=%.0f sectors=%d" % [nearest_three, nearest_sectors.size()])

	var food_count: int = 0
	var food_sectors: Dictionary = {}
	for loot in loots:
		if str(loot.get("item_id")) != "comida":
			continue
		food_count += 1
		food_sectors[_sector_of((loot as Node2D).global_position)] = true
	print("FOOD count=%d sectors=%d" % [food_count, food_sectors.size()])

	var path_ext := NavigationServer2D.map_get_path(map_rid, start, extraction.global_position, true)
	var ext_len: float = 0.0
	for k in range(1, path_ext.size()):
		ext_len += path_ext[k - 1].distance_to(path_ext[k])
	print("EXTRACTION path_points=%d len=%.0f" % [path_ext.size(), ext_len])

func _body_rect(body: StaticBody2D) -> Rect2:
	var min_corner := Vector2(INF, INF)
	var max_corner := Vector2(-INF, -INF)
	for child in body.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null:
			continue
		var shape := shape_node.shape
		if shape is RectangleShape2D:
			var size: Vector2 = (shape as RectangleShape2D).size
			min_corner = min_corner.min(-size * 0.5)
			max_corner = max_corner.max(size * 0.5)
		elif shape is CircleShape2D:
			var r: float = (shape as CircleShape2D).radius
			min_corner = min_corner.min(Vector2(-r, -r))
			max_corner = max_corner.max(Vector2(r, r))
	if min_corner.x == INF:
		return Rect2(body.global_position, Vector2.ZERO)
	return Rect2(body.global_position + min_corner, max_corner - min_corner)

func _sector_of(position: Vector2) -> int:
	var column: int = int((position.x + 2400.0) / 480.0)
	var row: int = int((position.y + 1500.0) / 300.0)
	var row_band: int = 0 if row <= 3 else (1 if row <= 5 else 2)
	var col_band: int = 0 if column <= 3 else (1 if column <= 7 else 2)
	return row_band * 3 + col_band

func _play() -> void:
	await _acquire_nodes()
	print("PLAY start pos=%s map=%s" % [str(_player.global_position), str(_neighborhood.map_size())])
	await _death_and_restart_test()
	print("PLAY after restart pos=%s hp=%.0f fuel=%d medkits=%d" % [
		str(_player.global_position), float(_player.get("hp")),
		Inventory.count("combustible"), Inventory.count("medkit")
	])
	await _check_borders_and_compass()
	await _collect_objective()
	await _ensure_combat()
	await _go_extraction()
	_print_summary()

## ============================================================================
## SMOKE DE JUEGO EN VIVO (QA_MODE=smoke)
## ============================================================================
## El juego REAL corre un numero FIJO de frames con el autopiloto y el arnes
## imprime un centinela inequivoco al terminar: `PLAY_SMOKE_COMPLETE`.
##
## Por que existe: la compuerta arrancaba la escena principal y apagaba el
## motor en el PRIMER frame, asi que ningun error de runtime del bucle de
## juego podia aparecer. Y el modo `play` depende de un `--quit-after`
## externo: si el juego acaba antes, el CI ve un codigo 0 sin centinela y
## puede parecer verde sin haber terminado el flujo.
##
## El CI exige (a) codigo de salida 0, (b) el centinela `PLAY_SMOKE_COMPLETE`,
## (c) ningun `SCRIPT ERROR|Parse Error|...` y (d) ningun `FAIL `.
## ============================================================================
func _smoke() -> void:
	_smoke_ok = false
	await _acquire_nodes()
	print("SMOKE start pos=%s map=%s" % [str(_player.global_position), str(_neighborhood.map_size())])

	# El autopiloto mueve al jugador (y pelea si aparece un zombi): obliga a
	# correr la IA, el combate, el HUD y las oleadas. El destino se elige en
	# una plaza realmente transitable: el barrio es procedural y una casa
	# generada al azar podia ocupar el punto fijo +X.
	var start_position: Vector2 = _player.global_position
	var target: Vector2 = _choose_smoke_target(start_position)
	print("SMOKE target=%s offset=%s" % [str(target), str(target - start_position)])
	var reached: bool = await _move_to(target, 600, 48.0, true)
	var moved: float = start_position.distance_to(_player.global_position)
	print("SMOKE move reached=%s moved=%.0f pos=%s" % [
		str(reached), moved, str(_player.global_position)])

	# Frames extra de juego vivo con el mundo en marcha.
	for i in range(180):
		await get_tree().physics_frame

	var alive: bool = not bool(_player.get("is_dead"))
	var hp: float = float(_player.get("hp"))
	print("SMOKE alive=%s hp=%.0f" % [str(alive), hp])
	# El smoke NO puede quedar verde si el autopiloto no se movio: eso
	# significa que la navegacion o la entrada de teclado estan rotas, y es
	# una regresion silenciosa que ni el alive ni el centinela detectan.
	# `reached` sigue siendo obligatorio: el contrato R1 exige verificar que
	# la entrada produce movimiento real hasta un destino alcanzable.
	if alive and reached and moved >= 100.0:
		_smoke_ok = true
		print("PLAY_SMOKE_COMPLETE reached=%s moved=%.0f" % [str(reached), moved])
	else:
		print("PLAY_SMOKE_FAILED alive=%s reached=%s moved=%.0f" % [
			str(alive), str(reached), moved])


func _hunger_test() -> void:
	await _acquire_nodes()
	_freeze_zombies()
	var max_hunger: float = float(_player.get("max_hunger"))
	print("HUNGER start=%.1f/%.1f food=%d" % [float(_player.get("hunger")), max_hunger, Inventory.count("comida")])
	print("CHECK hunger_initial_full=%s" % str(absf(float(_player.get("hunger")) - max_hunger) < 1.0))
	_check_hunger_hud("initial")

	_player.set("hunger", 50.0)
	for i in range(300):
		await get_tree().physics_frame
	var after_drain: float = float(_player.get("hunger"))
	print("HUNGER_DRAIN start=50.0 after=%.2f frames=300" % after_drain)
	print("CHECK hunger_drains=%s" % str(after_drain < 49.5 and after_drain > 48.0))

	var before_pause: float = float(_player.get("hunger"))
	get_tree().paused = true
	for i in range(60):
		await get_tree().process_frame
	var after_pause: float = float(_player.get("hunger"))
	get_tree().paused = false
	print("HUNGER_PAUSE before=%.2f after=%.2f" % [before_pause, after_pause])
	print("CHECK hunger_paused=%s" % str(absf(after_pause - before_pause) < 0.01))

	_player.set("hp", 100.0)
	_player.set("hunger", 0.0)
	_damage_events = 0
	_damage_total = 0.0
	for i in range(130):
		await get_tree().physics_frame
	var hp_one: float = float(_player.get("hp"))
	print("STARVATION after_2s hp=%.0f damage_events=%d" % [hp_one, _damage_events])
	print("CHECK starvation_gradual=%s" % str(hp_one < 100.0 and hp_one >= 96.0))
	_check_hunger_hud("starving")
	for i in range(130):
		await get_tree().physics_frame
	var hp_two: float = float(_player.get("hp"))
	print("STARVATION after_4s hp=%.0f damage_events=%d" % [hp_two, _damage_events])
	print("CHECK starvation_continues=%s" % str(hp_two < hp_one and hp_two > 90.0))

	var food := _find_food_loot()
	if food == null:
		print("CHECK food_loot=FAIL no_food_container")
	else:
		print("FOOD_LOOT pos=%s sector=%d" % [str(food.global_position), _sector_of(food.global_position)])
		var looted: bool = await _loot_container(food)
		print("CHECK food_looted=%s count=%d" % [str(looted and Inventory.count("comida") > 0), Inventory.count("comida")])

	_player.set("hunger", 20.0)
	for i in range(3):
		await get_tree().physics_frame
	_check_hunger_hud("low")
	var food_before: int = Inventory.count("comida")
	var hunger_before: float = float(_player.get("hunger"))
	_set_action("use_food", true)
	await get_tree().physics_frame
	_set_action("use_food", false)
	for i in range(4):
		await get_tree().physics_frame
	var hunger_after: float = float(_player.get("hunger"))
	var food_after: int = Inventory.count("comida")
	print("FOOD_EAT hunger=%.1f->%.1f food=%d->%d toast='%s'" % [
		hunger_before, hunger_after, food_before, food_after,
		(_hud.get_node("Toast") as Label).text
	])
	print("CHECK food_consumed=%s" % str(hunger_after > hunger_before + 20.0 and food_after == food_before - 1))
	print("CHECK food_toast=%s" % str((_hud.get_node("Toast") as Label).text.contains("Comida consumida")))

	Inventory.add_item("comida", 1)
	_player.set("hunger", max_hunger)
	for i in range(3):
		await get_tree().physics_frame
	food_before = Inventory.count("comida")
	hunger_before = float(_player.get("hunger"))
	_set_action("use_food", true)
	await get_tree().physics_frame
	_set_action("use_food", false)
	for i in range(4):
		await get_tree().physics_frame
	food_after = Inventory.count("comida")
	hunger_after = float(_player.get("hunger"))
	print("FOOD_FULL hunger=%.1f->%.1f food=%d->%d" % [hunger_before, hunger_after, food_before, food_after])
	print("CHECK food_full_blocked=%s" % str(food_after == food_before and hunger_after >= hunger_before - 0.1))

	_player.set("hunger", 10.0)
	_player.receive_damage(1000.0)
	for i in range(3):
		await get_tree().process_frame
	var death_hunger: float = float(_player.get("hunger"))
	print("DEATH_HUNGER hp=%.0f hunger=%.1f overlay=%s" % [
		float(_player.get("hp")), death_hunger,
		str((_hud.get_node("EndOverlay") as ColorRect).visible)
	])
	for i in range(60):
		await get_tree().process_frame
	var frozen_hunger: float = float(_player.get("hunger"))
	print("CHECK hunger_death_frozen=%s" % str(absf(frozen_hunger - death_hunger) < 0.01))
	await _restart_game()
	var hunger_reset: float = float(_player.get("hunger"))
	max_hunger = float(_player.get("max_hunger"))
	print("RESTART_HUNGER hunger=%.1f/%.1f food=%d" % [hunger_reset, max_hunger, Inventory.count("comida")])
	print("CHECK hunger_restart_full=%s" % str(absf(hunger_reset - max_hunger) < 1.0))
	print("CHECK food_restart_clear=%s" % str(Inventory.count("comida") == 0))
	_check_hunger_hud("restart")

func _freeze_zombies() -> void:
	for zombie in get_tree().get_nodes_in_group("zombies"):
		var node := zombie as Node2D
		if node == null:
			continue
		node.set_physics_process(false)
		node.global_position = Vector2(10000.0, 10000.0)

func _find_food_loot() -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for loot in get_tree().get_nodes_in_group("loot"):
		if str(loot.get("item_id")) != "comida" or bool(loot.get("_looted")):
			continue
		var node := loot as Node2D
		if node == null:
			continue
		var distance: float = node.global_position.distance_squared_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best

func _check_hunger_hud(label: String) -> void:
	var text: String = (_hud.get_node("Status/Margin/VBox/HungerLabel") as Label).text
	var bar: ProgressBar = _hud.get_node("Status/Margin/VBox/HungerBar")
	print("HUNGER_HUD %s text='%s' value=%.0f/%.0f" % [label, text, bar.value, bar.max_value])
	print("CHECK hunger_hud_%s=%s" % [
		label,
		str(text.begins_with("HAMBRE") and absf(bar.value - float(_player.get("hunger"))) < 1.5)
	])

func _acquire_nodes() -> void:
	for i in range(20):
		await get_tree().physics_frame
	_main = get_tree().current_scene
	_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	_hud = _main.get_node("HUD")
	_extraction = get_tree().get_first_node_in_group("extraction") as ExtractionZone
	_neighborhood = _main.get_node("Level/Neighborhood") as Neighborhood
	_last_position = _player.global_position
	_victory_fired = false
	_game_over_fired = false

func _death_and_restart_test() -> void:
	var target := _nearest_zombie(10000.0)
	if target == null:
		print("CHECK death_test=FAIL no_zombies")
		return
	var hp_start: float = float(_player.get("hp"))
	print("DEATH_TEST target=%s dist=%.0f hp_start=%.0f" % [
		str(target.global_position), target.global_position.distance_to(_player.global_position), hp_start
	])
	var reached: bool = await _move_to(target.global_position, 6000, 42.0, false)
	_release_all()
	print("DEATH_TEST reached=%s dist=%.0f" % [reached, target.global_position.distance_to(_player.global_position)])
	var frames: int = 0
	while frames < 2400 and not _game_over_fired:
		await get_tree().physics_frame
		_sample_perf()
		frames += 1
	var hp_after: float = float(_player.get("hp"))
	print("DEATH_RESULT frames=%d hp_start=%.0f hp_after=%.0f damage_events=%d damage_total=%.0f game_over=%s" % [
		frames, hp_start, hp_after, _damage_events, _damage_total, str(_game_over_fired)
	])
	print("CHECK damage_received=%s" % str(_damage_events > 0 and (hp_after < hp_start or _game_over_fired)))
	print("CHECK death_overlay=%s title=%s" % [
		str((_hud.get_node("EndOverlay") as ColorRect).visible),
		(_hud.get_node("EndOverlay/EndPanel/EndTitle") as Label).text
	])
	await _restart_game()

func _restart_game() -> void:
	var old_main: Node = get_tree().current_scene
	_set_action("restart", true)
	await get_tree().physics_frame
	_set_action("restart", false)
	var reloaded: bool = false
	for i in range(240):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene != old_main:
			reloaded = true
			break
	print("CHECK restart_reload=%s" % str(reloaded))
	await _acquire_nodes()
	var start: Vector2 = _neighborhood.start_position()
	print("CHECK restart_start=%s hp=%.0f fuel=%d medkits=%d" % [
		str(_player.global_position.distance_to(start) < 2.0),
		float(_player.get("hp")), Inventory.count("combustible"), Inventory.count("medkit")
	])
	_distance_travelled = 0.0
	_damage_events = 0
	_damage_total = 0.0
	_kills = 0
	_perf_samples = 0
	_perf_physics_sum = 0.0
	_perf_physics_max = 0.0
	_perf_nav_sum = 0.0
	_perf_nav_max = 0.0
	_chase_samples = 0
	_chase_physics_sum = 0.0

func _check_borders_and_compass() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var camera := _player.get_node("Camera2D") as Camera2D
	print("BORDER_START pos=%s viewport=%s camera=%s" % [
		str(_player.global_position), str(viewport_size), str(camera.get_screen_center_position())
	])
	_set_action("move_left", true)
	for i in range(90):
		await get_tree().physics_frame
		_track_distance()
		_sample_perf()
	_set_action("move_left", false)
	var left_x: float = _player.global_position.x
	_set_action("move_right", true)
	for i in range(90):
		await get_tree().physics_frame
		_track_distance()
		_sample_perf()
		if _player.global_position.x >= -2050.0:
			break
	_set_action("move_right", false)
	_set_action("move_back", true)
	for i in range(90):
		await get_tree().physics_frame
		_track_distance()
		_sample_perf()
	_set_action("move_back", false)
	for i in range(4):
		await get_tree().physics_frame
	var bottom_y: float = _player.global_position.y
	var center: Vector2 = camera.get_screen_center_position()
	var half_view: Vector2 = viewport_size * 0.5
	# Mundo abierto: la camara acompaña al jugador y solo se frena en los bordes
	# del mundo (12600x12600), no en los muros del pueblo.
	var world_half := Vector2(6300.0, 6300.0)
	var forest: Node = _main.get_node_or_null("Level/Forest") if _main != null else null
	if forest != null and forest.has_method("world_half"):
		world_half = forest.call("world_half")
	var expected_center := Vector2(
		clampf(_player.global_position.x, -world_half.x + half_view.x, world_half.x - half_view.x),
		clampf(_player.global_position.y, -world_half.y + half_view.y, world_half.y - half_view.y)
	)
	print("BORDER_RESULT left_x=%.1f bottom_y=%.1f camera=%s expected=%s" % [
		left_x, bottom_y, str(center), str(expected_center)
	])
	print("CHECK border_left=%s" % str(left_x <= -2340.0 and left_x >= -2349.0))
	print("CHECK border_bottom=%s" % str(bottom_y >= 1435.0 and bottom_y <= 1449.0))
	print("CHECK camera_clamp=%s" % str(center.distance_to(expected_center) < 3.0))
	var open_world: bool = (camera.limit_left <= -world_half.x + 100.0
		and camera.limit_right >= world_half.x - 100.0
		and camera.limit_top <= -world_half.y + 100.0
		and camera.limit_bottom >= world_half.y - 100.0)
	print("CHECK open_world=%s limits=%d,%d,%d,%d" % [
		str(open_world), camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom
	])
	_check_compass("start")

func _check_compass(label: String) -> void:
	# Fase 4 sustituyó el antiguo CompassLabel de texto por la brújula visual
	# (HUD/Compass), que resuelve el objetivo en su variable _objective.
	var compass: Control = _hud.get_node_or_null("Compass") as Control
	var objective: Node2D = compass.get("_objective") as Node2D if compass != null else null
	var valid: bool = compass != null and objective != null
	var offset: Vector2 = _extraction.global_position - _player.global_position
	print("COMPASS %s objective=%s dist=%.0f" % [label, str(objective != null), offset.length()])
	print("CHECK compass_%s=%s" % [label, str(valid)])

func _collect_objective() -> void:
	var containers: Array = []
	for loot in get_tree().get_nodes_in_group("loot"):
		if str(loot.get("item_id")) == "combustible":
			containers.append(loot)
	containers.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_squared_to(_player.global_position) < b.global_position.distance_squared_to(_player.global_position)
	)
	var sectors: Dictionary = {}
	var attempts: int = 0
	for loot in containers:
		if Inventory.count("combustible") >= 3 or attempts >= 6:
			break
		attempts += 1
		print("FUEL_TARGET pos=%s sector=%d" % [str(loot.global_position), _sector_of(loot.global_position)])
		var ok: bool = await _loot_container(loot)
		if ok:
			sectors[_sector_of(loot.global_position)] = true
		else:
			print("FUEL_LOOT_FAIL pos=%s" % str(loot.global_position))
	print("OBJECTIVE fuel=%d sectors=%d distance=%.0f" % [
		Inventory.count("combustible"), sectors.size(), _distance_travelled
	])
	var resources: String = (_hud.get_node("Status/Margin/VBox/ResourcesLabel") as Label).text
	print("CHECK objective_fuel=%s" % str(Inventory.count("combustible") >= 3))
	print("CHECK objective_sectors=%s" % str(sectors.size() >= 3))
	print("CHECK objective_hud='%s'" % resources)

func _loot_container(loot: Node2D) -> bool:
	var item_id: String = str(loot.get("item_id"))
	var before: int = Inventory.count(item_id)
	var reached: bool = await _move_to(loot.global_position, 3600, 22.0, true)
	_release_all()
	for i in range(4):
		await get_tree().physics_frame
	var distance: float = _player.global_position.distance_to(loot.global_position)
	var prompt: String = (_hud.get_node("Prompt") as Label).text
	print("LOOT_APPROACH reached=%s dist=%.1f prompt='%s'" % [reached, distance, prompt])
	if distance > 30.0:
		for i in range(50):
			_set_move_vector((loot.global_position - _player.global_position).normalized())
			await get_tree().physics_frame
			_track_distance()
		_release_all()
		for i in range(3):
			await get_tree().physics_frame
		distance = _player.global_position.distance_to(loot.global_position)
		prompt = (_hud.get_node("Prompt") as Label).text
		print("LOOT_NUDGE dist=%.1f prompt='%s'" % [distance, prompt])
	print("CHECK loot_prompt=%s" % str(prompt.begins_with("E  Saquear")))
	if distance > 30.0:
		print("LOOT_FAIL unreachable dist=%.1f" % distance)
		return false
	_set_action("interact", true)
	await get_tree().physics_frame
	_set_action("interact", false)
	for i in range(4):
		await get_tree().physics_frame
	var after: int = Inventory.count(item_id)
	var looted: bool = bool(loot.get("_looted"))
	print("LOOT_RESULT item=%s before=%d after=%d looted=%s" % [item_id, before, after, str(looted)])
	return after > before or looted

func _ensure_combat() -> void:
	print("COMBAT kills=%d" % _kills)
	if _kills > 0:
		return
	var zombie := _nearest_zombie(10000.0)
	if zombie == null:
		print("CHECK combat=FAIL no_zombies")
		return
	print("COMBAT_FORCE target=%s dist=%.0f" % [str(zombie.global_position), zombie.global_position.distance_to(_player.global_position)])
	await _move_to(zombie.global_position, 5000, 44.0, false)
	await _fight(zombie)
	print("CHECK combat=%s kills=%d" % [str(_kills > 0), _kills])

func _go_extraction() -> void:
	print("EXTRACTION_ROUTE fuel=%d pos=%s" % [Inventory.count("combustible"), str(_player.global_position)])
	var reached: bool = await _move_to(_extraction.global_position, 10000, 36.0, true)
	print("EXTRACTION reached=%s dist=%.0f" % [reached, _player.global_position.distance_to(_extraction.global_position)])
	# La victoria ya no es inmediata: ExtractionZone tiene una cuenta atrás
	# de 12 s (EXTRACTION_COUNTDOWN). Esperar solo 30 frames físicos (~0,5 s)
	# daba un falso negativo en este modo. 60 × 0,25 s = 15 s de margen.
	for i in range(60):
		if _victory_fired:
			break
		await get_tree().create_timer(0.25).timeout
	var overlay := _hud.get_node("EndOverlay") as ColorRect
	var title := _hud.get_node("EndOverlay/EndPanel/EndTitle") as Label
	print("VICTORY fired=%s overlay=%s title='%s'" % [str(_victory_fired), str(overlay.visible), title.text])
	print("CHECK extraction=%s" % str(_victory_fired and overlay.visible and title.text.contains("EXTRACCIÓN")))
	_check_compass("extraction")

## Elige un destino corto, dentro del mapa y sin una casa ni un zombi sobre
## el trayecto. El smoke prueba entrada y movimiento, no una ruta larga: por
## eso 170 px bastan para superar el umbral de 100 px tras la tolerancia.
func _choose_smoke_target(start: Vector2) -> Vector2:
	var offsets: Array[Vector2] = [
		Vector2(170.0, 0.0),
		Vector2(0.0, -170.0),
		Vector2(-170.0, 0.0),
		Vector2(0.0, 170.0),
		Vector2(150.0, -150.0),
		Vector2(-150.0, -150.0),
		Vector2(150.0, 150.0),
		Vector2(-150.0, 150.0),
	]
	var half: Vector2 = _neighborhood.map_size() * 0.5
	for offset in offsets:
		var target: Vector2 = start + offset
		if absf(target.x) > half.x - 32.0 or absf(target.y) > half.y - 32.0:
			continue
		if _smoke_path_is_clear(start, target):
			return target
	# Fallback explicito: el primer candidato queda registrado en el log y el
	# smoke falla de forma visible si ni siquiera puede recorrerse.
	return start + Vector2(170.0, 0.0)


func _smoke_path_is_clear(start: Vector2, target: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(start, target, 1, [_player.get_rid()])
	if not _player.get_world_2d().direct_space_state.intersect_ray(query).is_empty():
		return false
	for zombie in get_tree().get_nodes_in_group("zombies"):
		var node := zombie as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if _distance_to_segment(node.global_position, start, target) < 88.0:
			return false
	return true


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment: Vector2 = end - start
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)
	var ratio: float = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


func _move_to(target: Vector2, timeout: int, stop_distance: float, fight_threats: bool = true) -> bool:
	var path := PackedVector2Array()
	var repath_timer: int = 0
	var last_progress: Vector2 = _player.global_position
	var stuck_frames: int = 0
	for frame in range(timeout):
		if _player == null or not is_instance_valid(_player):
			_release_all()
			return false
		if bool(_player.get("is_dead")) or _game_over_fired or _victory_fired:
			_release_all()
			return false
		var offset: Vector2 = target - _player.global_position
		if offset.length() <= stop_distance:
			_release_all()
			return true
		if fight_threats:
			var threat := _nearest_zombie(72.0)
			if threat != null:
				_release_movement()
				await _fight(threat)
				if bool(_player.get("is_dead")) or _game_over_fired:
					_release_all()
					return false
				repath_timer = 0
				continue
		repath_timer -= 1
		if repath_timer <= 0:
			path = _navigation_path(target)
			repath_timer = 12
		var waypoint: Vector2 = target
		if path.size() > 1:
			for point in path:
				if point.distance_to(_player.global_position) > 18.0:
					waypoint = point
					break
		var direction: Vector2 = waypoint - _player.global_position
		if direction.length() < 0.1:
			direction = offset
		_set_move_vector(direction.normalized())
		var sprinting: bool = (
			offset.length() > 500.0
			and float(_player.get("stamina")) > 35.0
			and _nearest_zombie(220.0) == null
		)
		_set_action("sprint", sprinting)
		await get_tree().physics_frame
		_track_distance()
		_sample_perf()
		stuck_frames += 1
		if stuck_frames >= 60:
			if _player.global_position.distance_to(last_progress) < 6.0:
				var nudge: Vector2 = direction.orthogonal().normalized()
				_set_move_vector(nudge)
				for i in range(15):
					await get_tree().physics_frame
					_track_distance()
				repath_timer = 0
			last_progress = _player.global_position
			stuck_frames = 0
	_release_all()
	print("MOVE_TIMEOUT target=%s dist=%.0f" % [str(target), _player.global_position.distance_to(target)])
	return _player.global_position.distance_to(target) <= stop_distance * 2.0

func _fight(zombie: Node2D) -> bool:
	print("FIGHT start pos=%s hp=%.0f" % [str(zombie.global_position), float(zombie.get("hp"))])
	var frames: int = 0
	while frames < 1200:
		if not is_instance_valid(zombie) or not zombie.is_in_group("zombies"):
			_release_all()
			print("FIGHT kill frames=%d kills=%d" % [frames, _kills])
			return true
		if bool(_player.get("is_dead")) or _game_over_fired:
			_release_all()
			return false
		var offset: Vector2 = zombie.global_position - _player.global_position
		_aim_at(zombie.global_position)
		if offset.length() > 42.0:
			_set_move_vector(offset.normalized())
		else:
			_release_movement()
		_set_action("attack", frames % 34 == 0)
		if float(_player.get("hp")) < 45.0 and Inventory.count("medkit") > 0:
			_set_action("use_medkit", frames % 70 == 0)
		await get_tree().physics_frame
		_track_distance()
		_sample_perf()
		frames += 1
	_release_all()
	print("FIGHT timeout hp=%.0f" % float(_player.get("hp")))
	return not is_instance_valid(zombie) or not zombie.is_in_group("zombies")

func _nearest_zombie(max_distance: float) -> Node2D:
	var best: Node2D = null
	var best_distance: float = max_distance
	for zombie in get_tree().get_nodes_in_group("zombies"):
		var node := zombie as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var distance: float = node.global_position.distance_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best

func _densest_zombie() -> Node2D:
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	var best: Node2D = null
	var best_neighbour: float = INF
	for zombie in zombies:
		var node := zombie as Node2D
		if node == null:
			continue
		var nearest: float = INF
		for other in zombies:
			var other_node := other as Node2D
			if other_node == null or other_node == node:
				continue
			nearest = minf(nearest, node.global_position.distance_to(other_node.global_position))
		if nearest < best_neighbour:
			best_neighbour = nearest
			best = node
	return best

func _navigation_path(target: Vector2) -> PackedVector2Array:
	var rid: RID = _player.get_world_2d().navigation_map
	return NavigationServer2D.map_get_path(rid, _player.global_position, target, true)

func _set_move_vector(direction: Vector2) -> void:
	_set_action("move_right", direction.x > 0.3)
	_set_action("move_left", direction.x < -0.3)
	_set_action("move_back", direction.y > 0.3)
	_set_action("move_forward", direction.y < -0.3)

func _release_movement() -> void:
	_set_action("move_right", false)
	_set_action("move_left", false)
	_set_action("move_back", false)
	_set_action("move_forward", false)
	_set_action("sprint", false)

func _aim_at(world_position: Vector2) -> void:
	var viewport := get_viewport()
	var screen_position: Vector2 = viewport.get_canvas_transform() * world_position
	var event := InputEventMouseMotion.new()
	event.position = screen_position
	event.global_position = screen_position
	Input.parse_input_event(event)

func _track_distance() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_distance_travelled += _player.global_position.distance_to(_last_position)
	_last_position = _player.global_position

func _sample_perf() -> void:
	_perf_samples += 1
	var physics: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var navigation: float = Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS)
	_perf_physics_sum += physics
	_perf_physics_max = maxf(_perf_physics_max, physics)
	_perf_nav_sum += navigation
	_perf_nav_max = maxf(_perf_nav_max, navigation)
	if _is_chasing():
		_chase_samples += 1
		_chase_physics_sum += physics

func _is_chasing() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie.get("target") != _player:
			continue
		if float(zombie.get("_alert_timer")) <= 0.0:
			continue
		if (zombie as Node2D).global_position.distance_to(_player.global_position) < 600.0:
			return true
	return false

func _print_summary() -> void:
	var physics_avg: float = 0.0
	var nav_avg: float = 0.0
	var chase_avg: float = 0.0
	if _perf_samples > 0:
		physics_avg = _perf_physics_sum / float(_perf_samples) * 1000.0
		nav_avg = _perf_nav_sum / float(_perf_samples) * 1000.0
	if _chase_samples > 0:
		chase_avg = _chase_physics_sum / float(_chase_samples) * 1000.0
	print("PLAY_SUMMARY distance=%.0f kills=%d damage_events=%d damage_total=%.0f fuel=%d medkits=%d victory=%s" % [
		_distance_travelled, _kills, _damage_events, _damage_total,
		Inventory.count("combustible"), Inventory.count("medkit"), str(_victory_fired)
	])
	print("PERF samples=%d physics_avg=%.2fms physics_max=%.2fms nav_avg=%.3fms nav_max=%.3fms chase_samples=%d chase_physics_avg=%.2fms" % [
		_perf_samples, physics_avg, _perf_physics_max * 1000.0,
		nav_avg, _perf_nav_max * 1000.0, _chase_samples, chase_avg
	])

func _cardinal(offset: Vector2) -> String:
	var directions := ["E", "SE", "S", "SO", "O", "NO", "N", "NE"]
	var index: int = posmod(int(round(offset.angle() / (PI / 4.0))), 8)
	return directions[index]

func _perf_mode() -> void:
	await _acquire_nodes()
	_player.global_position = Vector2(240.0, -150.0)
	_player.set("hp", 1000000.0)
	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	for i in range(zombies.size()):
		var angle: float = TAU * float(i) / float(zombies.size())
		(zombies[i] as Node2D).global_position = _player.global_position + Vector2(cos(angle), sin(angle)) * 260.0
	for i in range(90):
		await get_tree().physics_frame
	var actions := ["move_right", "move_back", "move_left", "move_forward"]
	var fps_sum: float = 0.0
	var fps_min: float = INF
	var fps_max: float = 0.0
	var process_sum: float = 0.0
	var process_max: float = 0.0
	var fps_samples: int = 0
	for block in range(6):
		var action: String = actions[block % actions.size()]
		_set_action(action, true)
		for i in range(120):
			await get_tree().physics_frame
			_track_distance()
			_sample_perf()
			var fps: float = Engine.get_frames_per_second()
			if fps > 0.0:
				fps_sum += fps
				fps_min = minf(fps_min, fps)
				fps_max = maxf(fps_max, fps)
				fps_samples += 1
			var process_time: float = Performance.get_monitor(Performance.TIME_PROCESS)
			process_sum += process_time
			process_max = maxf(process_max, process_time)
		_set_action(action, false)
	_release_all()
	var fps_avg: float = fps_sum / float(maxi(1, fps_samples))
	var process_avg: float = process_sum / 720.0 * 1000.0
	var physics_avg: float = _perf_physics_sum / float(maxi(1, _perf_samples)) * 1000.0
	var nav_avg: float = _perf_nav_sum / float(maxi(1, _perf_samples)) * 1000.0
	var chase_avg: float = _chase_physics_sum / float(maxi(1, _chase_samples)) * 1000.0
	print("PERF_MODE distance=%.0f fps_avg=%.1f fps_min=%.1f fps_max=%.1f process_avg=%.2fms process_max=%.2fms physics_avg=%.2fms nav_avg=%.3fms chase_samples=%d chase_physics_avg=%.2fms" % [
		_distance_travelled, fps_avg, fps_min, fps_max, process_avg, process_max * 1000.0,
		physics_avg, nav_avg, _chase_samples, chase_avg
	])

func _capture_mode() -> void:
	var main := get_tree().current_scene
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if capture_dir == DEFAULT_CAPTURE_DIR:
		var shot_dir: DirAccess = DirAccess.open("user://")
		if shot_dir != null:
			shot_dir.make_dir_recursive("qa_shots")
	else:
		DirAccess.make_dir_recursive_absolute(capture_dir)
	var shots := [
		["start", Vector2(-2100, 1350)],
		["west_border", Vector2(-2340, 1350)],
		["south_border", Vector2(-2100, 1440)],
		["plaza", Vector2(240, -150)],
		["market", Vector2(240, 1050)],
		["north", Vector2(0, -1050)],
		["east_border", Vector2(2340, 0)],
		["depot", Vector2(1680, 900)],
		["extraction", Vector2(2160, -1330)],
		["southwest_corner", Vector2(-2340, 1440)],
		["northeast_corner", Vector2(2340, -1440)],
	]
	for shot in shots:
		player.global_position = shot[1]
		for i in range(24):
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(capture_dir.path_join("%s.png" % shot[0]))
		var camera := player.get_node("Camera2D") as Camera2D
		var compass_node = main.get_node_or_null("HUD/Compass")
		var compass: String = "activa" if compass_node != null else "N/A"
		print("SHOT %s pos=%s camera=%s compass='%s'" % [
			shot[0], str(player.global_position), str(camera.get_screen_center_position()), compass
		])

# ============================================================================
# CONTRATO DE CALIDAD R1 — sistemas nuevos en implementación paralela.
# Todo se consulta de forma defensiva: una API ausente produce PENDING, nunca
# un SCRIPT ERROR ni un CHECK en falso. Útil también como modo "mechanics".
# ============================================================================

func _has_prop(obj: Object, prop: String) -> bool:
	if obj == null:
		return false
	for entry in obj.get_property_list():
		if String(entry.get("name", "")) == prop:
			return true
	return false

func _mechanics_ready_report() -> Dictionary:
	var report: Dictionary = {}

	# 1. GameState autoload: capa compatible (get_state+load_state) O
	# API canónica de core (phase+stats+rng).
	var gs: Node = get_node_or_null("/root/GameState")
	report["game_state"] = gs != null and (
		(gs.has_method("get_state") and gs.has_method("load_state"))
		or (gs.has_method("phase") and gs.has_method("stats") and gs.has_method("rng"))
	)

	# 2. Crafting (Inventario.craft / craft_item o autoload /root/Crafting).
	var inv_node: Node = get_node_or_null("/root/Inventory")
	var can_craft: bool = inv_node != null and (inv_node.has_method("craft") or inv_node.has_method("craft_item"))
	var craft_node: Node = get_node_or_null("/root/Crafting")
	if craft_node != null and craft_node.has_method("craft"):
		can_craft = true
	report["crafting"] = can_craft

	# 3. Condición de armas (Weapon.condition|durability|wear + repair/is_broken).
	# Tras Player._die() el jugador sale del grupo "player" y el WeaponController
	# dejaría de verse. Se buscan tres rutas, en orden, sin tocar grupos ni textos:
	# 1) grupo player, 2) Main/Player, 3) cualquier WeaponController bajo Main.
	var scene: Node = get_tree().current_scene
	var player_node: Node = get_tree().get_first_node_in_group("player")
	var wc: Node = null
	if player_node != null:
		wc = player_node.get_node_or_null("WeaponController")
	if wc == null and scene != null:
		var main_player: Node = scene.get_node_or_null("Player")
		if main_player != null:
			wc = main_player.get_node_or_null("WeaponController")
	if wc == null and scene != null:
		var weapon_controllers: Array[Node] = scene.find_children("*", "WeaponController", true, false)
		if not weapon_controllers.is_empty():
			wc = weapon_controllers[0]
	var weapon_ready: bool = false
	if wc != null and wc.has_method("get_weapon_in_slot"):
		for slot in range(5):
			var weapon: Variant = wc.call("get_weapon_in_slot", slot)
			if weapon == null:
				continue
			for prop in ["condition", "durability", "wear"]:
				if _has_prop(weapon, prop):
					weapon_ready = true
			if weapon.has_method("repair") or weapon.has_method("is_broken"):
				weapon_ready = true
	report["weapon_condition"] = weapon_ready

	# 4. Hordas: WaveManager | HordeManager | WorldDirector en Main con
	# start_wave(), y EventBus.wave_started O horde_started.
	# `scene` ya se resolvió en el apartado 3 (se reutiliza, sin redeclarar).
	var horde: Node = scene.get_node_or_null("WaveManager") if scene != null else null
	if horde == null and scene != null:
		horde = scene.get_node_or_null("HordeManager")
	if horde == null and scene != null:
		horde = scene.get_node_or_null("WorldDirector")
	report["hordes"] = (
		horde != null and horde.has_method("start_wave")
		and (EventBus.has_signal("wave_started") or EventBus.has_signal("horde_started"))
	)

	# 5. Vehículo con combustible (`fuel` o `vehicle_fuel`) y daño.
	var car: Node = scene.get_node_or_null("VehicleNorth") if scene != null else null
	report["vehicle_fuel_damage"] = (
		car != null
		and (_has_prop(car, "fuel") or _has_prop(car, "vehicle_fuel"))
		and (car.has_method("refuel") or car.has_method("apply_damage") or car.has_method("take_damage"))
	)

	var active: int = 0
	for key in ["game_state", "crafting", "weapon_condition", "hordes", "vehicle_fuel_damage"]:
		if bool(report.get(key, false)):
			active += 1
	report["active"] = active
	report["total"] = 5
	return report

func _print_mechanics_ready() -> void:
	var report: Dictionary = _mechanics_ready_report()
	var flags: Array[String] = []
	for key in ["game_state", "crafting", "weapon_condition", "hordes", "vehicle_fuel_damage"]:
		flags.append("%s=%s" % [key, str(bool(report.get(key, false)))])
	var active: int = int(report.get("active", 0))
	var status: String = "OK" if active == 5 else ("PENDING" if active == 0 else "PARTIAL")
	print("MECHANICS_READY %d/5 %s" % [active, ", ".join(flags)])
	print("CHECK mechanics_ready=%s active=%d/5 (informativo en r1; OK exige 5/5)" % [status, active])

