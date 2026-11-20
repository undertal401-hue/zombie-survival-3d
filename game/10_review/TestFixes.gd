extends Node

func _ready() -> void:
	await get_tree().process_frame
	var main: Node = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for i in range(10):
		await get_tree().process_frame
	for i in range(5):
		await get_tree().physics_frame

	var player: CharacterBody2D = main.get_node("Player")
	var menu: CanvasLayer = main.get_node("InventoryMenu")
	var hud: CanvasLayer = main.get_node("HUD")
	var solar = main.get_node_or_null("SolarLighting")
	var inv = get_node("/root/Inventory")
	var wc: WeaponController = player.get_node_or_null("WeaponController")

	print("=== TEST FIXES ===")
	
	# 1. inventory_open property exists
	print("1. inventory_open exists: ", _has_prop(player, "inventory_open"))
	print("   inventory_open value: ", player.inventory_open)
	
	# 2. HUD shows ammo at start
	var resources_label = hud.get_node("Status/Margin/VBox/ResourcesLabel")
	print("2. HUD resources text: '", resources_label.text, "'")
	
	# 3. display_name for pistol_ammo
	print("3. display_name(pistol_ammo): '", inv.call("display_name", "pistol_ammo"), "'")
	
	# 4. SolarLighting exists
	print("4. SolarLighting in Main: ", solar != null)
	if solar != null:
		var cm = solar.get_node("CanvasModulate")
		var sun = solar.get_node("SunLight")
		print("   CanvasModulate color: ", cm.color)
		print("   SunLight energy: ", sun.energy, " shadow_enabled: ", sun.shadow_enabled)
	
	# 5. Raycast mask test
	var probe_body := CharacterBody2D.new()
	probe_body.collision_layer = 2
	probe_body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	cs.shape = circle
	probe_body.add_child(cs)
	main.add_child(probe_body)
	probe_body.global_position = player.global_position + Vector2(200, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var from: Vector2 = player.global_position
	var to: Vector2 = probe_body.global_position
	var q1 := PhysicsRayQueryParameters2D.create(from, to, 1)
	var q3 := PhysicsRayQueryParameters2D.create(from, to, 3)
	var space := player.get_world_2d().direct_space_state
	var r1 := space.intersect_ray(q1)
	var r3 := space.intersect_ray(q3)
	print("5. Raycast mask=1 (old): empty=", r1.is_empty(), " collider=", (r1.get("collider") if not r1.is_empty() else "none"))
	print("   Raycast mask=3 (new): empty=", r3.is_empty(), " collider=", (r3.get("collider") if not r3.is_empty() else "none"))
	probe_body.queue_free()
	
	# 6. Zombie layer
	var zscene: PackedScene = load("res://03_zombies/Zombie.tscn")
	var z := zscene.instantiate()
	print("6. Zombie collision_layer: ", z.collision_layer, " mask: ", z.collision_mask)
	z.queue_free()
	
	# 7. Inventory menu open/close with Tab (simulated)
	print("7. Menu initially open: ", menu.get("_open"))
	menu.call("open")
	await get_tree().process_frame
	await get_tree().process_frame
	print("   After open(): ", menu.get("_open"), " player.inventory_open: ", player.inventory_open)
	menu.call("close")
	await get_tree().process_frame
	await get_tree().process_frame
	print("   After close(): ", menu.get("_open"), " player.inventory_open: ", player.inventory_open)
	
	# 8. Food consumption test (single consume)
	inv.call("clear")
	inv.call("add_item", "comida", 1)
	player.hunger = 20.0
	await get_tree().process_frame
	var before_food = inv.call("count", "comida")
	var before_hunger = player.hunger
	menu.call("_on_eat_pressed", "comida")
	await get_tree().process_frame
	print("8. Food test: before_count=", before_food, " after_count=", inv.call("count", "comida"))
	print("   before_hunger=", before_hunger, " after_hunger=", player.hunger)
	
	# 9. Extraction zone exists
	var ext = main.get_node("Extraction")
	print("9. Extraction exists: ", ext != null, " in_group extraction: ", ext.is_in_group("extraction"))
	
	# 10. Input bindings
	for action in ["inventory", "use_food", "attack", "shoot", "move_forward", "move_back", "move_left", "move_right", "reload", "weapon_slot_1", "weapon_slot_2"]:
		var exists = InputMap.has_action(action)
		var events = []
		if exists:
			for e in InputMap.action_get_events(action):
				if e is InputEventKey:
					events.append("Key(phys=%d)" % e.physical_keycode)
				elif e is InputEventMouseButton:
					events.append("Mouse(%d)" % e.button_index)
		print("10. Input ", action, " exists=", exists, " events=", events)
	
	# 11. CanvasLayer layer property (not z_index)
	print("11. HUD layer: ", hud.layer, " (z_index: ", hud.get("z_index"), ")")
	print("    Menu layer: ", menu.layer, " (z_index: ", menu.get("z_index"), ")")
	
	# 12. Loot counts
	var loots = get_tree().get_nodes_in_group("loot")
	var counts = {}
	for loot in loots:
		var id = str(loot.get("item_id"))
		counts[id] = int(counts.get(id, 0)) + 1
	print("12. Loot total: ", loots.size(), " by_item: ", counts)
	
	# 13. Menu food row creation (no SCRIPT ERROR)
	inv.call("clear")
	inv.call("add_item", "comida", 3)
	inv.call("add_item", "medkit", 1)
	inv.call("add_item", "combustible", 1)
	inv.call("add_item", "pistol_ammo", 20)
	menu.call("open")
	await get_tree().process_frame
	await get_tree().process_frame
	var list = menu.get_node("Panel/ItemsSection/ItemsContainer/ItemsList")
	print("13. Menu open: ", menu.get("_open"), " itemlist children: ", list.get_child_count())
	var has_eat_btn = _find_button_by_text(list, "Comer") != null
	var has_use_btn = _find_button_by_text(list, "Usar") != null
	var has_reload_btn = _find_button_by_text(list, "Recargar") != null
	print("    Interactive buttons: Comer=", has_eat_btn, " Usar=", has_use_btn, " Recargar=", has_reload_btn)
	var slot_row = menu.get_node_or_null("Panel/WeaponSection/SlotsRow")
	print("    Weapon slot buttons: ", slot_row.get_child_count() if slot_row != null else -1)
	
	# 14. Attack/shoot separation
	print("14. Attack events: ", InputMap.action_get_events("attack").size(), " Shoot events: ", InputMap.action_get_events("shoot").size())
	
	# 15. WeaponController test
	print("15. WeaponController exists: ", wc != null)
	if wc != null:
		print("    Current weapon: ", wc.current_weapon.weapon_name if wc.current_weapon else "none")
		print("    Current slot: ", wc.current_slot)
		print("    Weapons array size: ", wc.weapons.size())
		for i in range(wc.weapons.size()):
			var w = wc.weapons[i]
			if w != null:
				print("      Slot ", i, ": ", w.weapon_name, " (", w.ammo_type, " ", w.get_total_ammo(), ")")
	
	# 16. Reload action
	print("16. Reload action exists: ", InputMap.has_action("reload"))
	
	# 17. Munición limitada: recargar consume balas del inventario
	if wc != null and wc.current_weapon != null:
		var gun := wc.current_weapon
		gun.ammo_in_chamber = 0
		gun.current_ammo = 0
		inv.call("clear")
		inv.call("add_item", "pistol_ammo", 12)
		print("17. Antes recargar: reserva=", inv.call("count", "pistol_ammo"), " cargador=", gun.current_ammo)
		gun.finish_reload()
		print("    Después recargar: reserva=", inv.call("count", "pistol_ammo"), " cargador=", gun.current_ammo, " recamara=", gun.ammo_in_chamber)
	
	# 18. Botones del menú ejecutan acciones reales
	inv.call("add_item", "comida", 1)
	inv.call("add_item", "medkit", 1)
	player.hp = 40.0
	menu.call("open")
	await get_tree().process_frame
	var use_btn := _find_button_by_text(menu, "Usar") as Button
	var eat_btn := _find_button_by_text(menu, "Comer") as Button
	if use_btn != null:
		use_btn.pressed.emit()
	if eat_btn != null and menu.get("_open"):
		eat_btn.pressed.emit()
	print("18. Click Usar -> medkit=", inv.call("count", "medkit"), " hp=", int(player.hp),
		" | Click Comer -> comida=", inv.call("count", "comida"))
	
	# 19. Velocidad reducida con pistola
	if wc != null:
		var machete := wc.get_weapon_in_slot(0)
		var pistol := wc.get_weapon_in_slot(1)
		print("19. Speed multiplier machete=", machete.move_speed_multiplier if machete != null else -1,
			" pistol=", pistol.move_speed_multiplier if pistol != null else -1)
	
	# 20. Melee no debe alterar el tiempo global ni congelar el mundo
	if wc != null:
		Engine.time_scale = 1.0
		wc.call("_equip_slot", 0)
		wc.call("_do_melee")
		var timers := 0
		for child in wc.get_children():
			if child is Timer:
				timers += 1
		print("20. Machete equipado: ", wc.current_weapon.weapon_name,
			" time_scale=", Engine.time_scale, " timers=", timers)
		wc.call("_equip_slot", 1)
	
	# 21. Movimiento real tras atacar con machete
	if wc != null:
		menu.call("close")
		wc.call("_equip_slot", 0)
		wc.call("_do_melee")
		var start_pos: Vector2 = player.global_position
		Input.action_press("move_right")
		for i in range(8):
			await get_tree().process_frame
			await get_tree().physics_frame
		Input.action_release("move_right")
		var moved: float = player.global_position.distance_to(start_pos)
		print("21. Desplazamiento tras golpe machete: ", snappedf(moved, 0.01), "px (time_scale=", Engine.time_scale, ")")
		wc.call("_equip_slot", 1)
	
	# 22. C1: cambiar de slot conserva la munición real (sin recarga gratis)
	if wc != null and wc.weapons.size() > 1 and wc.weapons[1] != null:
		var gun22: Weapon = wc.weapons[1]
		gun22.current_ammo = 4
		gun22.ammo_in_chamber = 0
		gun22.is_reloading = false
		wc.call("_equip_slot", 0)
		wc.call("_equip_slot", 1)
		var same_instance: bool = (wc.current_weapon == gun22)
		print("22. C1 conserva munición al cambiar slot: mag=", wc.current_weapon.current_ammo,
			" ch=", wc.current_weapon.ammo_in_chamber, " same_instance=", same_instance)

	# 23-25. C2: el cargador se gasta al disparar y la recarga no sobrecarga
	if wc != null and wc.weapons.size() > 1 and wc.weapons[1] != null:
		var gun23: Weapon = wc.weapons[1]
		gun23.current_ammo = 11
		gun23.ammo_in_chamber = 1
		gun23.burst_shots_fired = 0
		gun23.consume_ammo()
		var mag_after_1: int = gun23.current_ammo
		var ch_after_1: int = gun23.ammo_in_chamber
		gun23.consume_ammo()
		print("23. C2 consume_ammo: 1 disparo mag=", mag_after_1, " ch=", ch_after_1,
			" | 2 disparos mag=", gun23.current_ammo, " ch=", gun23.ammo_in_chamber,
			" total=", gun23.get_total_ammo())

		inv.call("clear")
		inv.call("add_item", "pistol_ammo", 20)
		gun23.current_ammo = 11
		gun23.ammo_in_chamber = 1
		var started_full: bool = gun23.start_reload()
		gun23.finish_reload()
		print("24. C2 recarga con arma llena: start=", started_full,
			" reserva=", inv.call("count", "pistol_ammo"), " total=", gun23.get_total_ammo())

		gun23.current_ammo = 0
		gun23.ammo_in_chamber = 0
		gun23.start_reload()
		gun23.finish_reload()
		print("25. C2 recarga desde vacío: mag=", gun23.current_ammo, " ch=", gun23.ammo_in_chamber,
			" total=", gun23.get_total_ammo(), " reserva=", inv.call("count", "pistol_ammo"))

	# 26-27. C3: la ráfaga termina y no se dispara sin munición
	if wc != null and wc.weapons.size() > 2:
		var burst_gun: Weapon = Weapon.new()
		burst_gun.weapon_name = "Rifle ráfaga (prueba)"
		burst_gun.category = Weapon.Category.RIFLE
		burst_gun.burst_count = 3
		burst_gun.burst_delay = 0.02
		burst_gun.fire_rate = 600.0
		burst_gun.ammo_type = "pistol_ammo"
		burst_gun.magazine_size = 12
		burst_gun.ammo_per_shot = 1
		burst_gun.chambered_round = true
		burst_gun.start_with_full_mag = true
		burst_gun._initialize_state()
		wc.weapons[2] = burst_gun
		
		var shots: Array[int] = [0]
		var counter: Callable = func(_w: Weapon, _f: Vector2, _t: Vector2) -> void: shots[0] += 1
		wc.fire_requested.connect(counter)
		wc.call("_equip_slot", 2)
		wc.call("_try_fire")
		var burst_start_ms: int = Time.get_ticks_msec()
		while wc._is_burst_firing and Time.get_ticks_msec() - burst_start_ms < 1500:
			await get_tree().process_frame
		print("26. C3 ráfaga: disparos=", shots[0], " contador=", burst_gun.burst_shots_fired,
			" activa=", wc._is_burst_firing, " total=", burst_gun.get_total_ammo())
		
		var shots_before: int = shots[0]
		burst_gun.current_ammo = 0
		burst_gun.ammo_in_chamber = 0
		burst_gun.burst_shots_fired = 0
		wc.call("_try_fire")
		for i in range(10):
			await get_tree().process_frame
		print("27. C3 sin munición: disparos extra=", shots[0] - shots_before,
			" ráfaga_activa=", wc._is_burst_firing)
		
		wc.fire_requested.disconnect(counter)
		wc.weapons[2] = null
		wc.call("_equip_slot", 1)

	# 28. C4: el machete alcanza a un zombie en contacto (~20px entre centros)
	if wc != null:
		menu.call("close")
		wc.call("_equip_slot", 0)
		var machete: Weapon = wc.current_weapon
		machete.last_shot_time = 0.0
		player._melee_cooldown = 0.0
		player.stamina = 100.0
		var target: Node2D = load("res://03_zombies/Zombie.tscn").instantiate()
		main.add_child(target)
		# El arco usa player.rotation (sigue al ratón), no la dirección del ratón.
		var facing: Vector2 = Vector2.RIGHT.rotated(player.rotation)
		target.global_position = player.global_position + facing * 20.0
		var hp_before: float = target.hp
		wc.call("_do_melee")
		print("28. C4 machete: rango=", machete.melee_range, " dist=20 rot=",
			snappedf(player.rotation, 0.01), " hp ", hp_before, " -> ", target.hp)
		target.queue_free()
		wc.call("_equip_slot", 1)

	# 29. C5: el escupitajo daña al jugador, crea charco y se destruye
	var hp_acid_start: float = player.hp
	var puddles_start: int = get_tree().get_nodes_in_group("acid_puddles").size()
	var spit: Node2D = load("res://03_zombies/projectiles/AcidSpit.tscn").instantiate()
	var acid_has_signal: bool = spit.has_signal("body_entered")
	main.add_child(spit)
	spit.global_position = player.global_position + Vector2(60.0, 0.0)
	spit.call("launch", Vector2.LEFT, 15.0, 200.0)
	var acid_start_ms: int = Time.get_ticks_msec()
	while is_instance_valid(spit) and Time.get_ticks_msec() - acid_start_ms < 1200:
		await get_tree().process_frame
	print("29. C5 ácido: body_entered=", acid_has_signal,
		" hp ", hp_acid_start, " -> ", player.hp,
		" charcos=", get_tree().get_nodes_in_group("acid_puddles").size() - puddles_start,
		" proyectil_vivo=", is_instance_valid(spit))

	# 30. Gating: inventario abierto, juego pausado y jugador muerto no disparan
	if wc != null:
		var gate_gun: Weapon = wc.weapons[1]
		gate_gun.current_ammo = 11
		gate_gun.ammo_in_chamber = 1
		wc.call("_equip_slot", 1)
		var gate_shots: Array[int] = [0]
		var gate_counter: Callable = func(_w: Weapon, _f: Vector2, _t: Vector2) -> void: gate_shots[0] += 1
		wc.fire_requested.connect(gate_counter)
		
		menu.call("open")
		await get_tree().process_frame
		Input.action_press("shoot")
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release("shoot")
		var shots_menu: int = gate_shots[0]
		menu.call("close")
		await get_tree().process_frame
		
		get_tree().paused = true
		Input.action_press("shoot")
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release("shoot")
		var shots_paused: int = gate_shots[0] - shots_menu
		get_tree().paused = false
		await get_tree().process_frame
		
		player.is_dead = true
		Input.action_press("shoot")
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release("shoot")
		var shots_dead: int = gate_shots[0] - shots_menu - shots_paused
		player.is_dead = false
		wc.fire_requested.disconnect(gate_counter)
		print("30. Gating -> disparos: menú=", shots_menu, " pausa=", shots_paused,
			" muerto=", shots_dead, " process_mode=", wc.process_mode)

	# 31. La acción "attack" (Espacio / clic der.) dispara y también hace melee
	if wc != null:
		menu.call("close")
		wc.call("_equip_slot", 0)
		wc.current_weapon.last_shot_time = 0.0
		var melee_hits: Array[int] = [0]
		var melee_counter: Callable = func(_w: Weapon, _d: Vector2) -> void: melee_hits[0] += 1
		wc.melee_attack.connect(melee_counter)
		Input.action_press("attack")
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release("attack")
		wc.melee_attack.disconnect(melee_counter)
		
		wc.call("_equip_slot", 1)
		wc.current_weapon.last_shot_time = 0.0
		var attack_shots: Array[int] = [0]
		var atk_counter: Callable = func(_w: Weapon, _f: Vector2, _t: Vector2) -> void: attack_shots[0] += 1
		wc.fire_requested.connect(atk_counter)
		Input.action_press("attack")
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release("attack")
		wc.fire_requested.disconnect(atk_counter)
		print("31. attack -> melee=", melee_hits[0], " disparos=", attack_shots[0])

	# 32. Fase 2: todos los efectos de partículas tienen material y textura
	var particle_paths: Array[String] = [
		"res://assets/particles/BloodParticles.tscn",
		"res://assets/particles/ImpactParticles.tscn",
		"res://assets/particles/MuzzleFlashParticles.tscn",
		"res://03_zombies/projectiles/AcidSpit.tscn",
	]
	var particle_report: Array[String] = []
	for path in particle_paths:
		var inst: Node = load(path).instantiate()
		var target: GPUParticles2D = inst as GPUParticles2D
		if target == null:
			target = inst.get_node_or_null("Particles") as GPUParticles2D
		var has_mat: bool = target != null and target.process_material != null
		var has_tex: bool = target != null and target.texture != null
		particle_report.append("%s=%s/%s" % [path.get_file(), has_mat, has_tex])
		inst.free()
	print("32. Partículas material/textura: ", ", ".join(particle_report))

	# 33. Fase 2: el HUD sigue las señales del arma y oculta munición melee
	if wc != null:
		var hud_label: Label = hud.get_node("Status/Margin/VBox/ResourcesLabel")
		wc.call("_equip_slot", 1)
		wc.current_weapon.current_ammo = 11
		wc.current_weapon.ammo_in_chamber = 1
		wc.ammo_changed.emit(1, 11, 0)
		var text_pistol: String = hud_label.text
		wc.call("_equip_slot", 0)
		var text_melee: String = hud_label.text
		print("33. HUD pistola='", text_pistol, "' | machete='", text_melee, "'")
		wc.call("_equip_slot", 1)

	# 34. Fase 2: menú con layout válido, icono de arma y cierre al terminar
	var menu_panel: Control = menu.get_node("Panel")
	var menu_ws: Control = menu.get_node("Panel/WeaponSection")
	var menu_is: Control = menu.get_node("Panel/ItemsSection")
	var menu_icon: TextureRect = menu.get_node("Panel/WeaponSection/WeaponInfo/WeaponIcon")
	var menu_eat: Label = menu.get_node("Panel/EatHint")
	var close_connected: bool = (EventBus.game_over.is_connected(menu.close)
		and EventBus.victory.is_connected(menu.close))
	var icon_state: String = "oculto" if not menu_icon.visible else ("textura" if menu_icon.texture != null else "vacio")
	print("34. Menú: panel=", menu_panel.size, " weapon=", menu_ws.size,
		" items=", menu_is.size, " eat_y=", int(menu_eat.position.y),
		" icono=", icon_state, " cierre_fin=", close_connected)

	# 35. Fase 2: PlayerVisual libera ataques sin frames y clamp hit flash
	var pv: Node = player.get_node_or_null("PlayerVisual")
	if pv != null:
		pv.call("play_attack", 1)
		var attacking_start: bool = pv.get("_is_attacking")
		pv.call("_process", 1.0)
		var attacking_end: bool = pv.get("_is_attacking")
		pv.call("play_hurt")
		pv.call("_process", 1.0)
		var pv_sprite: AnimatedSprite2D = pv.get_node("AnimatedSprite2D") as AnimatedSprite2D
		var pv_mat: ShaderMaterial = pv_sprite.material as ShaderMaterial
		var flash: float = float(pv_mat.get_shader_parameter("hit_flash_progress"))
		print("35. PlayerVisual: ataque=", attacking_start, "->", attacking_end,
			" flash_tras_timeout=", snappedf(flash, 0.01))

	# 36. Fase 2: shake consecutivo no acumula el offset base
	if wc != null:
		var cam: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			var shake_timer: Timer = wc.get("_shake_timer") as Timer
			if shake_timer != null:
				shake_timer.stop()
			wc.set("_shake_camera", null)
			wc.set("_shake_base_offset", Vector2.ZERO)
			cam.offset = Vector2.ZERO
			var original_mag: float = wc.current_weapon.camera_shake_magnitude
			wc.current_weapon.camera_shake_magnitude = 100.0
			wc.call("_apply_camera_shake", 0.2)
			cam.offset = Vector2(1000, 0)  # desplazamiento del primer shake
			wc.call("_apply_camera_shake", 0.2)
			var shake_base: Vector2 = wc.get("_shake_base_offset")
			print("36. Shake base tras 2 disparos: ", shake_base, " (debe ser 0,0)")
			wc.current_weapon.camera_shake_magnitude = original_mag
			cam.offset = Vector2.ZERO
			if shake_timer != null:
				shake_timer.stop()

	# 37. Fase 3: derrota muestra overlay de fin y pausa el juego
	EventBus.game_over.emit()
	await get_tree().process_frame
	var go_overlay: ColorRect = hud.get_node("EndOverlay") as ColorRect
	var go_title: Label = hud.get_node("EndOverlay/EndPanel/EndTitle") as Label
	var go_hint: Label = hud.get_node("EndOverlay/EndPanel/EndHint") as Label
	print("37. Game over: overlay=", go_overlay.visible, " pausa=", get_tree().paused,
		" titulo='", go_title.text, "' pista='", go_hint.text, "'")
	get_tree().paused = false

	# 38. Fase 4: minimapa y brújula presentes, con script y objetivo resuelto
	var minimap: Control = hud.get_node_or_null("Minimap") as Control
	var compass: Control = hud.get_node_or_null("Compass") as Control
	if minimap != null:
		minimap.queue_redraw()
	if compass != null:
		compass.queue_redraw()
	await get_tree().process_frame
	var mini_ok: bool = minimap != null and minimap.script != null
	var comp_ok: bool = compass != null and compass.script != null
	var comp_obj: bool = compass != null and compass.get("_objective") != null
	print("38. Minimap/Brujula: minimapa=", mini_ok, " compass=", comp_ok,
		" objetivo=", comp_obj,
		" mini_size=", (minimap.size if minimap != null else Vector2.ZERO),
		" comp_size=", (compass.size if compass != null else Vector2.ZERO))

	# 39. Regresión de geometría: la lista de objetos no debe tapar los slots
	# de armas (bug original: SlotsRow sobresalía del WeaponSection).
	var slots_row: Control = menu.get_node("Panel/WeaponSection/SlotsRow") as Control
	var items_container: Control = menu.get_node("Panel/ItemsSection/ItemsContainer") as Control
	var weapon_bottom: float = menu_ws.position.y + menu_ws.size.y
	var slots_bottom: float = menu_ws.position.y + slots_row.position.y + slots_row.size.y
	var items_top: float = menu_is.position.y
	var items_container_top: float = menu_is.position.y + items_container.position.y
	var items_container_bottom: float = items_container_top + items_container.size.y
	var items_bottom: float = menu_is.position.y + menu_is.size.y
	var no_overlap: bool = (slots_bottom <= weapon_bottom and items_top >= slots_bottom
		and items_container_top >= items_top and items_container_bottom <= items_bottom)
	print("39. Geometria menu: slots_bottom=", int(slots_bottom),
		" weapon_bottom=", int(weapon_bottom), " items_top=", int(items_top),
		" container=", int(items_container_top), "..", int(items_container_bottom),
		" sin_solape=", no_overlap)

	# 40. Expansión del mapa: el bosque debe cubrir >=10x el área del pueblo.
	var forest_node: Node2D = main.get_node_or_null("Level/Forest") as Node2D
	var neighborhood_node: Node = main.get_node_or_null("Level/Neighborhood")
	var town_size: Vector2 = Vector2(4800, 3000)
	if neighborhood_node != null and neighborhood_node.has_method("map_size"):
		town_size = neighborhood_node.call("map_size")
	var world_size: Vector2 = Vector2.ZERO
	var tree_total: int = 0
	if forest_node != null:
		if forest_node.has_method("world_half"):
			world_size = (forest_node.call("world_half") as Vector2) * 2.0
		if forest_node.has_method("tree_count"):
			tree_total = int(forest_node.call("tree_count"))
	var area_ratio: float = 0.0
	if town_size.x > 0.0 and town_size.y > 0.0:
		area_ratio = (world_size.x * world_size.y) / (town_size.x * town_size.y)
	print("40. Bosque: mundo=", world_size, " arboles=", tree_total,
		" area_x=", snappedf(area_ratio, 0.01),
		" ok=", (area_ratio >= 10.0 and tree_total > 500))

	# 41. Accesos: 3 puertas, 3 huecos en muros y camara de mundo abierto desde el inicio.
	var gates_node: Node = main.get_node_or_null("ForestGates")
	var gate_total: int = gates_node.get_child_count() if gates_node != null else 0
	var gap_total: int = 0
	for wall_name in ["WallTop", "WallLeft", "WallBottom"]:
		var wall: Node = main.get_node_or_null("Level/%s" % wall_name)
		if wall != null and wall.get_node_or_null("CollisionShape2DGate") != null:
			gap_total += 1
	var test_camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	var initial_limit: int = test_camera.limit_left if test_camera != null else -1
	var saved_pos: Vector2 = player.global_position
	player.global_position = Vector2(3000.0, 0.0)
	main.call("_refresh_forest_zone")
	var deep_limit: int = test_camera.limit_left if test_camera != null else -1
	player.global_position = saved_pos
	main.call("_refresh_forest_zone")
	var restored_limit: int = test_camera.limit_left if test_camera != null else -1
	print("41. Accesos: gates=", gate_total, " huecos=", gap_total,
		" camara_mundo=", initial_limit, "->", deep_limit, "->", restored_limit,
		" ok=", (gate_total == 3 and gap_total == 3 and initial_limit == -6300
			and deep_limit == -6300 and restored_limit == -6300))

	# 42. Navegacion extendida al bosque y matorrales que la recortan.
	var nav_region: NavigationRegion2D = main.get_node_or_null("NavigationRegion2D") as NavigationRegion2D
	var outline_min: float = 0.0
	var outline_max: float = 0.0
	if nav_region != null and nav_region.navigation_polygon != null:
		var outline: PackedVector2Array = nav_region.navigation_polygon.get_outline(0)
		for pt in outline:
			outline_min = minf(outline_min, pt.x)
			outline_max = maxf(outline_max, pt.x)
	var thickets_node: Node = main.get_node_or_null("Level/Forest/NavThickets")
	var thickets: int = thickets_node.get_child_count() if thickets_node != null else 0
	print("42. Nav: bake_ms=", main.get("bake_ms"), " outline_x=", outline_min, "..", outline_max,
		" matorrales=", thickets,
		" ok=", (outline_min <= -6200.0 and outline_max >= 6200.0 and thickets > 0))

	# 43. Sprite procedural original: fotogramas reales en el jugador y textura
	# en la camioneta, sin depender de archivos de imagen externos.
	var pv_sprite: AnimatedSprite2D = null
	if pv != null:
		pv_sprite = pv.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var walk_frames: int = 0
	if pv_sprite != null and pv_sprite.sprite_frames != null:
		walk_frames = pv_sprite.sprite_frames.get_frame_count("walk")
	var test_vehicle: Node = main.get_node_or_null("VehicleNorth")
	var vehicle_sprite: Sprite2D = null
	if test_vehicle != null:
		vehicle_sprite = test_vehicle.get_node_or_null("Sprite") as Sprite2D
	print("43. Sprites: jugador_frames=", walk_frames,
		" camioneta_textura=", (vehicle_sprite != null and vehicle_sprite.texture != null),
		" ok=", (walk_frames >= 4 and vehicle_sprite != null and vehicle_sprite.texture != null))

	# 44. Vehículo: subir, avanzar con WASD, bajar y restaurar el control del jugador.
	if test_vehicle != null:
		var car_start: Vector2 = test_vehicle.global_position
		player.global_position = car_start + Vector2(120.0, 0.0)
		await get_tree().physics_frame
		test_vehicle.call("enter_vehicle", player)
		await get_tree().physics_frame
		var driving: bool = bool(player.get("is_driving"))
		Input.action_press("move_forward")
		for i in range(20):
			await get_tree().physics_frame
		Input.action_release("move_forward")
		var car_moved: float = test_vehicle.global_position.distance_to(car_start)
		var follow_gap: float = player.global_position.distance_to(test_vehicle.global_position)
		test_vehicle.call("exit_vehicle")
		await get_tree().physics_frame
		var restored: bool = not bool(player.get("is_driving")) and player.collision_mask == 3
		print("44. Vehiculo: conduce=", driving, " avance=", snappedf(car_moved, 0.1),
			" separacion=", snappedf(follow_gap, 0.1), " control_restaurado=", restored,
			" ok=", (driving and car_moved > 10.0 and follow_gap < 20.0 and restored))

	# 45. Zombies del bosque: spawnean al entrar y se limpian al salir.
	var forest_zombie_manager: Node = main.get_node_or_null("ForestZombies")
	var spawn_points: int = 0
	if forest_node != null and forest_node.has_method("forest_zombie_spawn_points"):
		spawn_points = (forest_node.call("forest_zombie_spawn_points") as Array).size()
	EventBus.forest_entered.emit()
	await get_tree().physics_frame
	var spawned: int = 0
	for fz in get_tree().get_nodes_in_group("zombies"):
		if bool(fz.get_meta("forest_zombie", false)):
			spawned += 1
	EventBus.forest_exited.emit()
	await get_tree().physics_frame
	var remaining: int = 0
	for zz in get_tree().get_nodes_in_group("zombies"):
		if bool(zz.get_meta("forest_zombie", false)):
			remaining += 1
	print("45. Zombies bosque: puntos=", spawn_points, " spawneados=", spawned,
		" restantes=", remaining,
		" ok=", (spawn_points >= 6 and spawned >= 6 and remaining == 0))

	# ========================================================================
	# CHECKS 46+ — CONTRATO DE CALIDAD R1 (sistemas en implementación paralela)
	# Regla: ausente = PENDING, parcial = PARTIAL, completo = OK. Nunca FAIL
	# por una API que todavía no existe. Todo se consulta con has_method /
	# get_node_or_null / _has_prop para no lanzar SCRIPT ERROR ajeno.
	# ========================================================================

	# 46. GameState autoload: se aceptan DOS APIs (capa compatible y canónica).
	# Compat: get_state + load_state. Canon: phase + stats + rng (core r1bis).
	var gs: Node = get_node_or_null("/root/GameState")
	var gs_methods: Array[String] = []
	if gs != null:
		for method_name in ["reset", "new_game", "get_state", "load_state", "get_wave",
			"get_difficulty", "is_game_over", "is_victory", "phase", "set_phase",
			"difficulty", "set_difficulty", "rng", "stats", "record",
			"register_actor", "unregister_actor"]:
			if gs.has_method(method_name):
				gs_methods.append(method_name)
	var gs_compat: bool = gs != null and gs.has_method("get_state") and gs.has_method("load_state")
	var gs_canon: bool = gs != null and gs.has_method("phase") and gs.has_method("stats") and gs.has_method("rng")
	var gs_ok: bool = gs_compat or gs_canon
	var gs_any_api: bool = gs != null and (
		gs.has_method("get_state") or gs.has_method("load_state") or gs.has_method("phase")
		or gs.has_method("stats") or gs.has_method("rng") or gs.has_method("set_phase")
	)
	var gs_state: String = "OK" if gs_ok else ("PENDING" if not gs_any_api else "PARTIAL")
	print("46. GameState: autoload=", gs != null, " metodos=", gs_methods,
		" compat=", gs_compat, " canon=", gs_canon, " estado=", gs_state)
	if gs_compat:
		var state_dict: Dictionary = gs.call("get_state")
		print("    get_state() keys=", state_dict.keys())
	elif gs_canon:
		print("    phase=", gs.call("phase"), " stats=", gs.call("stats"))

	# 47. Crafting: Inventory.craft() o autoload /root/Crafting con recetas.
	var crafting_node: Node = get_node_or_null("/root/Crafting")
	var inv_can_craft: bool = inv.has_method("craft") or inv.has_method("craft_item")
	var recipes: Variant = null
	if crafting_node != null and crafting_node.has_method("get_recipes"):
		recipes = crafting_node.call("get_recipes")
	elif _has_prop(inv, "recipes"):
		recipes = inv.get("recipes")
	var recipe_count: int = 0
	if recipes is Dictionary or recipes is Array:
		recipe_count = (recipes as Array).size() if recipes is Array else (recipes as Dictionary).size()
	var can_craft: bool = inv_can_craft or (crafting_node != null and crafting_node.has_method("craft"))
	var craft_state: String = "OK" if can_craft and recipe_count > 0 else (
		"PENDING" if not can_craft and recipe_count == 0 else "PARTIAL")
	print("47. Crafting: autoload=", crafting_node != null, " Inventory.craft=", inv_can_craft,
		" recetas=", recipe_count, " estado=", craft_state)

	# 48. Condición/durabilidad de armas (Weapon.condition|durability|wear).
	var cond_props: Array[String] = []
	var cond_methods: Array[String] = []
	if wc != null:
		var probe_weapon: Weapon = wc.get_weapon_in_slot(1)
		if probe_weapon == null:
			probe_weapon = wc.current_weapon
		if probe_weapon != null:
			for prop_name in ["condition", "durability", "wear"]:
				if _has_prop(probe_weapon, prop_name):
					cond_props.append(prop_name)
			for method_name in ["is_broken", "is_worn_out", "repair", "repair_weapon"]:
				if probe_weapon.has_method(method_name):
					cond_methods.append(method_name)
	var cond_state: String = "OK" if not cond_props.is_empty() and not cond_methods.is_empty() else (
		"PENDING" if cond_props.is_empty() and cond_methods.is_empty() else "PARTIAL")
	print("48. Condicion armas: props=", cond_props, " metodos=", cond_methods,
		" estado=", cond_state)

	# 49. Hordas/oleadas: WaveManager | HordeManager | WorldDirector en Main,
	# con start_wave() y wave_started O horde_started en EventBus.
	var horde_manager: Node = main.get_node_or_null("WaveManager")
	if horde_manager == null:
		horde_manager = main.get_node_or_null("HordeManager")
	if horde_manager == null:
		horde_manager = main.get_node_or_null("WorldDirector")
	var wave_methods: Array[String] = []
	if horde_manager != null:
		for method_name in ["start_wave", "get_wave", "is_horde_active", "horde_size"]:
			if horde_manager.has_method(method_name):
				wave_methods.append(method_name)
	var wave_signal: bool = EventBus.has_signal("wave_started") or EventBus.has_signal("horde_started")
	var zombie_count_now: int = get_tree().get_nodes_in_group("zombies").size()
	var horde_state: String = "OK" if wave_signal and wave_methods.has("start_wave") else (
		"PENDING" if not wave_signal and wave_methods.is_empty() else "PARTIAL")
	print("49. Hordas: manager=", horde_manager != null, " wave_signal=", wave_signal,
		" metodos=", wave_methods, " zombies=", zombie_count_now,
		" estado=", horde_state)

	# 50. Vehículo con combustible y daño (camioneta norte).
	# Se acepta la prop `fuel` o su alias `vehicle_fuel`.
	var test_car: Node = main.get_node_or_null("VehicleNorth")
	var car_props: Array[String] = []
	var car_methods: Array[String] = []
	if test_car != null:
		for prop_name in ["fuel", "vehicle_fuel", "max_fuel", "health", "hp"]:
			if _has_prop(test_car, prop_name):
				car_props.append(prop_name)
		for method_name in ["consume_fuel", "refuel", "apply_damage", "take_damage", "is_out_of_fuel"]:
			if test_car.has_method(method_name):
				car_methods.append(method_name)
	var has_fuel_prop: bool = car_props.has("fuel") or car_props.has("vehicle_fuel")
	var has_fuel: bool = has_fuel_prop and (car_methods.has("refuel") or car_methods.has("consume_fuel"))
	var has_damage: bool = car_methods.has("apply_damage") or car_methods.has("take_damage")
	var car_state: String = "OK" if has_fuel and has_damage else (
		"PENDING" if car_props.is_empty() and car_methods.is_empty() else "PARTIAL")
	print("50. Vehicle fuel/damage: props=", car_props, " metodos=", car_methods,
		" estado=", car_state)

	# ------------------------------------------------------------------------
	# CHECKS 51-54 — CONTRATO DE CALIDAD R2 (sistemas nuevos en implementación
	# paralela: 13_audio, 14_quests, 15_fx, 16_meta). Se ejecutan en RONDA 3.
	# Regla idéntica a 46-50: OK / PARTIAL / PENDING, nunca FAIL. Todo se
	# consulta con get_node_or_null, has_method y has_signal; si el nodo aún no
	# existe pero el script ya está en disco se reporta PARTIAL, y PENDING si
	# no hay nada. Estos checks NO alteran el resumen mechanics_ready de 5
	# sistemas del contrato r1 (textos y rutas congelados).
	# ------------------------------------------------------------------------
	var r51: Dictionary = _probe_r2_system(main, [
			["play_sfx", "play_sound", "play", "play_effect"],
			# R1: la música adaptativa se eliminó (ver AudioPolicyTest). La lista
			# de métodos reflejaba la API vieja (play_music/set_music); ahora
			# comprueba la API real de ambiente y SFX.
			["set_ambience", "set_ambience_volume", "play_telegraph", "play_loot_rarity"],
			["set_volume", "set_master_volume", "set_bus_volume"],
		], ["sfx_played", "volume_changed", "audio_ready"], [],
		["Main/AudioDirector", "/root/AudioDirector", "/root/Audio", "Main/Audio"],
		["res://13_audio/AudioDirector.gd"], false)
	print("51. AudioDirector: estado=", r51.get("state", "PENDING"),
		" ruta=", r51.get("path", "none"), " grupos=", r51.get("groups", "0/0"),
		" metodos=", str(r51.get("methods", [])), " senales=", str(r51.get("signals", [])))

	var r52: Dictionary = _probe_r2_system(main, [
			["get_active_quests", "active_quest_count"],
			["get_progress", "quest_progress"],
			["complete_quest"], ["abandon_quest"],
		], ["quest_started", "quest_progress", "quest_completed"],
		["zombie_died", "craft_completed", "wave_started", "horde_started", "notification"],
		["Main/QuestDirector", "/root/QuestDirector"],
		["res://14_quests/QuestDirector.gd"], true)
	print("52. QuestDirector: estado=", r52.get("state", "PENDING"),
		" ruta=", r52.get("path", "none"), " grupos=", r52.get("groups", "0/0"),
		" metodos=", str(r52.get("methods", [])), " senales=", str(r52.get("signals", [])),
		" bus=", str(r52.get("bus", [])))

	var r53: Dictionary = _probe_r2_system(main, [
			["spawn_impact", "spawn_blood", "spawn_shell", "spawn_dust"],
			["set_weather", "current_weather"],
			["active_particle_count"],
		], [],
		["player_damaged", "zombie_died", "vehicle_state_changed", "notification"],
		["Main/CombatFX", "/root/CombatFX", "Main/FX/CombatFX"],
		["res://15_fx/CombatFX.gd"], false)
	print("53. CombatFX: estado=", r53.get("state", "PENDING"),
		" ruta=", r53.get("path", "none"), " grupos=", r53.get("groups", "0/0"),
		" metodos=", str(r53.get("methods", [])), " bus=", str(r53.get("bus", [])))

	var r54: Dictionary = _probe_r2_system(main, [
			["unlock", "is_unlocked"],
			["record_run"],
			["get_unlocked", "get_progress"],
			["get_title", "save_progress"],
		], ["achievement_unlocked"],
		["victory", "game_over", "zombie_died", "craft_completed"],
		["/root/MetaProgress", "Main/MetaProgress"],
		["res://16_meta/MetaProgress.gd"], true)
	print("54. MetaProgress: estado=", r54.get("state", "PENDING"),
		" ruta=", r54.get("path", "none"), " grupos=", r54.get("groups", "0/0"),
		" metodos=", str(r54.get("methods", [])), " senales=", str(r54.get("signals", [])),
		" bus=", str(r54.get("bus", [])))

	var new_systems_ok: int = 0
	for state in [gs_state, craft_state, cond_state, horde_state, car_state]:
		if state == "OK":
			new_systems_ok += 1
	print("CHECK mechanics_ready=%s active=%d/5" % [
		"OK" if new_systems_ok == 5 else ("PENDING" if new_systems_ok == 0 else "PARTIAL"),
		new_systems_ok
	])

	# --- COMPUERTA DURA PARA CI -------------------------------------------
	# Las comprobaciones 46-54 son informativas (PENDING/PARTIAL). Estas otras
	# sí son invariantes: si fallan, el proceso termina con codigo 1.
	var hard_failures: Array[String] = []
	# Las pruebas de arriba mutan el mundo (slot 2, crafting, inventario), así
	# que la compuerta se evalúa sobre una partida recién creada.
	main.queue_free()
	for i in range(3):
		await get_tree().process_frame
	var gate_main: Node = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(gate_main)
	for i in range(8):
		await get_tree().process_frame
	if get_tree().get_first_node_in_group("hud") == null:
		hard_failures.append("HUD ausente")
	if gate_main.get_node_or_null("WaveManager") == null:
		hard_failures.append("WaveManager ausente")
	var gate_player: Node = gate_main.get_node_or_null("Player")
	var gate_wc: WeaponController = null
	if gate_player != null:
		gate_wc = gate_player.get_node_or_null("WeaponController") as WeaponController
	if gate_wc == null or gate_wc.weapons.size() != 5:
		hard_failures.append("loadout de 5 ranuras ausente")
	else:
		for slot: int in range(4):
			var slot_weapon: Weapon = gate_wc.get_weapon_in_slot(slot)
			if slot_weapon == null:
				hard_failures.append("ranura de arma %d vacia" % slot)
			else:
				# Una carga rota (recurso sin script Weapon, identidad vacia o
				# sin dano) no debe contar como "arma presente" y dar OK.
				if slot_weapon.get_script() == null:
					hard_failures.append("ranura %d sin script Weapon" % slot)
				if slot_weapon.weapon_name.strip_edges().is_empty() \
					or slot_weapon.weapon_name == "Unnamed Weapon":
					hard_failures.append("ranura %d sin identidad" % slot)
				if slot_weapon.base_damage <= 0.0:
					hard_failures.append("ranura %d sin dano" % slot)
	if Inventory.count("Machete") <= 0:
		hard_failures.append("condicion de armas no inicializada")
	if not EventBus.has_signal("victory") or not EventBus.has_signal("game_over"):
		hard_failures.append("EventBus sin senales de fin de partida")
	print("HARD_GATE failures=%d" % hard_failures.size())
	for f in hard_failures:
		print("  - " + f)

	print("=== TEST COMPLETE ===")
	
	for i in range(4):
		await get_tree().process_frame
	# La salida se programa ANTES de los assert: si un assert falla en debug,
	# el proceso ya tiene el codigo de fallo y el CI no puede dar verde aunque
	# el arnes se detenga. En release los asserts se compilan fuera y los
	# hard_failures de arriba siguen gobernando la salida.
	var gate_exit_code: int = 1 if not hard_failures.is_empty() else 0
	get_tree().quit(gate_exit_code)
	if gate_wc != null:
		for slot: int in range(4):
			var w: Weapon = gate_wc.get_weapon_in_slot(slot)
			if w != null:
				assert(w.get_script() != null,
					"HARD_GATE: ranura %d sin script Weapon" % slot)
				assert(not w.weapon_name.strip_edges().is_empty()
					and w.weapon_name != "Unnamed Weapon",
					"HARD_GATE: ranura %d sin identidad" % slot)
				assert(w.base_damage > 0.0,
					"HARD_GATE: ranura %d sin dano" % slot)

func _has_prop(obj: Object, prop: String) -> bool:
	for p in obj.get_property_list():
		if String(p.get("name", "")) == prop:
			return true
	return false

func _find_button_by_text(node: Node, text: String) -> Node:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := _find_button_by_text(child, text)
		if found != null:
			return found
	return null

## Sondeo defensivo compartido por los checks 51-54 (r2, ejecutar en r3).
## Cada grupo de required_groups se satisface con AL MENOS un método presente,
## para no dar PARTIAL falsos si un agente elige un sinónimo de la API.
## require_signal=true exige además al menos una señal local del sistema.
## main_node es la escena Main instanciada en _ready(): Main está colgada de
## /root, así que `Main/AudioDirector` se resuelve desde get_tree().root, no
## desde TestFixes. Último recurso: buscar por nombre bajo main con find_children.
func _probe_r2_system(main_node: Node, required_groups: Array, candidate_signals: Array,
		bus_signals: Array, paths: Array, script_paths: Array,
		require_signal: bool) -> Dictionary:
	var node: Node = null
	var found_path: String = "none"
	for path in paths:
		var route: String = String(path)
		var candidate: Node = get_tree().root.get_node_or_null(route)
		if candidate == null and not route.begins_with("/"):
			# Compatibilidad con rutas relativas al propio TestFixes.
			candidate = get_node_or_null(route)
		if candidate != null:
			node = candidate
			found_path = route
			break
	if node == null and main_node != null:
		var tried_names: Array[String] = []
		for path in paths:
			var name_hint: String = String(path).get_file()
			if name_hint.is_empty() or tried_names.has(name_hint):
				continue
			tried_names.append(name_hint)
			var matches: Array[Node] = main_node.find_children(name_hint, "", true, false)
			if not matches.is_empty():
				node = matches[0]
				found_path = "main:" + name_hint
				break
	var methods: Array[String] = []
	var signals: Array[String] = []
	var bus: Array[String] = []
	var groups_ok: int = 0
	if node != null:
		for group in required_groups:
			var satisfied: bool = false
			for method_name in group:
				if node.has_method(String(method_name)):
					if not methods.has(String(method_name)):
						methods.append(String(method_name))
					satisfied = true
			if satisfied:
				groups_ok += 1
		for signal_name in candidate_signals:
			if node.has_signal(String(signal_name)):
				signals.append(String(signal_name))
	for signal_name in bus_signals:
		if EventBus.has_signal(String(signal_name)):
			bus.append(String(signal_name))
	var state: String = "PENDING"
	if node != null:
		var complete: bool = groups_ok == required_groups.size()
		if require_signal:
			complete = complete and not signals.is_empty()
		state = "OK" if complete else "PARTIAL"
	else:
		# El script ya existe en disco pero aún no está instanciado/bindeado.
		for script_path in script_paths:
			if ResourceLoader.exists(String(script_path)):
				state = "PARTIAL"
				break
	return {
		"state": state,
		"path": found_path,
		"groups": "%d/%d" % [groups_ok, required_groups.size()],
		"methods": methods,
		"signals": signals,
		"bus": bus,
	}