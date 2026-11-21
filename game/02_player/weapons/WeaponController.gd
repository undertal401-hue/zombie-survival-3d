extends Node
class_name WeaponController

## =============================================================================
## WEAPON CONTROLLER - Gestor de armas del jugador
## =============================================================================
## Maneja: equipar, disparar, recargar, cambiar arma, ammo, efectos
## Comunica via señales y EventBus
## =============================================================================

signal weapon_changed(weapon: Weapon)
signal ammo_changed(current: int, total: int, in_chamber: int)
signal reloading_started(weapon: Weapon, duration: float)
signal reloading_finished(weapon: Weapon)
signal fire_requested(weapon: Weapon, from: Vector2, to: Vector2)
signal melee_attack(weapon: Weapon, direction: Vector2)
signal dry_fire(weapon: Weapon)

## Debe coincidir con Player.MELEE_COST: es el coste que Player descuenta.
const MELEE_STAMINA_MIN: float = 20.0

## ADR-002: micro-congelamiento SOLO en kills/headshots letales. 60 ms está
## dentro del rango 50-80 ms acordado; nunca se aplica a disparos normales.
const HIT_STOP_SECONDS: float = 0.06

## Loadout data-driven: los cuatro .tres son recursos reales (no Weapon.new()
## con campos copiados a mano). Su resource_path es válido: save/load funciona.
const RES_MACHETE: Weapon = preload("res://02_player/weapons/Machete.tres")
const RES_PISTOL: Weapon = preload("res://02_player/weapons/Pistol9mm.tres")
const RES_SHOTGUN: Weapon = preload("res://02_player/weapons/Shotgun12ga.tres")
const RES_RIFLE: Weapon = preload("res://02_player/weapons/Rifle556.tres")

@onready var player: CharacterBody2D = get_parent()

## Armas equipadas (slot -> Weapon instance)
var weapons: Array[Weapon] = []
var current_slot: int = -1
var current_weapon: Weapon

## Input
var _fire_held: bool = false
var _fire_pressed: bool = false
var _reload_pressed: bool = false

## Estado
var _burst_timer: float = 0.0
var _is_burst_firing: bool = false
## Evita spam del aviso de aguante al mantener disparo/melee.
var _no_stamina_timer: float = 0.0

## Shake aislado: solo modifica la cámara del jugador y restaura su offset base.
var _shake_timer: Timer
var _shake_camera: Camera2D
var _shake_base_offset: Vector2 = Vector2.ZERO

## Timer no escalado del hit-stop (ADR-002). Se guarda la referencia para
## poder liberarlo limpiamente al salir del árbol.
var _hit_stop_timer: SceneTreeTimer

func _ready() -> void:
	# El arma comparte el ciclo de vida del mundo: al pausar, morir o abrir el
	# inventario deja de procesar input, recargas y ráfagas.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	
	# Cargar armas por defecto (desde config o save)
	_load_default_loadout()
	
	# Equipar pistola (slot 1) por defecto, fallback a primera disponible
	var start_slot: int = 1 if weapons.size() > 1 and weapons[1] != null else -1
	if start_slot == -1:
		for i in weapons.size():
			if weapons[i] != null:
				start_slot = i
				break
	
	if start_slot >= 0:
		_equip_slot(start_slot)
	
	# Conectar señales de inventario
	Inventory.inventory_changed.connect(_on_inventory_changed)

	# ADR-002: el hit-stop dispara al morir un zombi (zombie_died / is_dead),
	# nunca desde _fire_shot(). El event bus es la única fuente de la muerte.
	if EventBus.has_signal("zombie_died") and not EventBus.zombie_died.is_connected(_on_zombie_died):
		EventBus.zombie_died.connect(_on_zombie_died)


func _exit_tree() -> void:
	# Red de seguridad: ninguna salida anómala (o --quit-after) debe dejar el
	# mundo ralentizado. La restauración normal la hace el timeout del timer.
	Engine.time_scale = 1.0
	if _hit_stop_timer != null and is_instance_valid(_hit_stop_timer):
		if _hit_stop_timer.timeout.is_connected(_restore_time_scale):
			_hit_stop_timer.timeout.disconnect(_restore_time_scale)
	_hit_stop_timer = null


## Callback del timer no escalado: devuelve el mundo a velocidad normal.
func _restore_time_scale() -> void:
	Engine.time_scale = 1.0
	_hit_stop_timer = null


## Hit-stop: se llama ÚNICAMENTE desde _on_zombie_died (muerte o headshot
## letal confirmado por el evento zombie_died). Nunca desde un disparo normal.
func hit_stop(seconds: float = HIT_STOP_SECONDS) -> void:
	# process_always = true e ignore_time_scale = true -> el temporizador sigue
	# corriendo aunque Engine.time_scale = 0.05 y aunque el árbol esté pausado.
	# Firma Godot 4: create_timer(time, process_always, process_in_physics,
	# ignore_time_scale) = create_timer(seconds, true, false, true).
	if _hit_stop_timer != null and is_instance_valid(_hit_stop_timer):
		if _hit_stop_timer.timeout.is_connected(_restore_time_scale):
			_hit_stop_timer.timeout.disconnect(_restore_time_scale)
	Engine.time_scale = 0.05
	_hit_stop_timer = get_tree().create_timer(seconds, true, false, true)
	_hit_stop_timer.timeout.connect(_restore_time_scale)


## Puente entre la muerte confirmada y el hit-stop. `is_dead` ya es verdad en
## el zombie que emite zombie_died; no hay hit-stop en impactos no letales.
## R1-fix: el payload de `zombie_died` no se tipa (puede llegar liberado);
## este receptor no lo usa, así que lo acepta sin restringir.
func _on_zombie_died(_zombie) -> void:
	hit_stop()

## El combate solo está activo mientras la partida corre y el jugador puede actuar.
func _gameplay_blocked() -> bool:
	if get_tree().paused:
		return true
	if player == null or player.is_dead or player.inventory_open:
		return true
	# Al conducir no se dispara ni se recarga: el vehículo tiene el control.
	if bool(player.get("is_driving")):
		return true
	return false

## Comprueba aguante sin tocar el tiempo global. El coste se descuenta en Player
## (dueño de la barra) cuando el disparo/golpe llega a ejecutarse de verdad.
func _has_stamina_for(cost: float) -> bool:
	if player == null:
		return false
	var current: float = float(player.get("stamina"))
	return current + 0.0001 >= maxf(cost, 0.0)

func _notify_no_stamina() -> void:
	if _no_stamina_timer > 0.0:
		return
	_no_stamina_timer = 0.9
	EventBus.notification.emit("Sin aguante")

func _process(delta: float) -> void:
	if current_weapon == null or get_tree().paused or player == null or player.is_dead:
		return

	# La recarga es estado del arma, no input del jugador: avanza aunque el
	# inventario esté abierto. Así la barra tiene progreso real y el arma no
	# queda bloqueada hasta cerrar el menú sin explicación.
	if current_weapon.is_reloading:
		if current_weapon.update_reload(delta):
			emit_signal("reloading_finished", current_weapon)
			EventBus.notification.emit("%s recargada" % current_weapon.weapon_name)

	# La dispersión y el retroceso se recuperan aunque el inventario esté abierto
	# o se conduzca: es estado del arma, no input del jugador. Pausa y muerte ya
	# salieron arriba, así que nunca se acumula recuperación "gratis".
	current_weapon.recover_spread(delta)
	_no_stamina_timer = maxf(_no_stamina_timer - delta, 0.0)

	# Con el inventario abierto se prohíbe disparar, cambiar de arma y recargar
	# de nuevo, pero la recarga ya iniciada sigue avanzando arriba.
	if _gameplay_blocked():
		return

	# Burst firing
	if _is_burst_firing:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_timer = current_weapon.burst_delay
			if current_weapon.burst_shots_fired < current_weapon.burst_count:
				_fire_shot()
			else:
				_is_burst_firing = false

	# Input handling
	_handle_input()

func _physics_process(delta: float) -> void:
	if current_weapon == null or _gameplay_blocked():
		return
	
	# Auto-fire si automático y held
	if current_weapon.is_automatic and _fire_held and not _is_burst_firing:
		# Al terminar una ráfaga el contador queda en burst_count y can_fire()
		# devuelve false. Reiniciarlo aquí permite la siguiente ráfaga mientras
		# el botón siga presionado (antes solo se reiniciaba al volver a pulsar).
		if current_weapon.burst_count > 1 and current_weapon.burst_shots_fired >= current_weapon.burst_count:
			current_weapon.burst_shots_fired = 0
		_try_fire()

func _handle_input() -> void:
	if _gameplay_blocked():
		return
	
	# Disparo / ataque: "attack" (Espacio, clic derecho) es alias de "shoot".
	# _try_fire() ya enruta a melee cuando el arma equipada es cuerpo a cuerpo.
	var fire_now: bool = Input.is_action_just_pressed("shoot") or Input.is_action_just_pressed("attack")
	var fire_held_now: bool = Input.is_action_pressed("shoot") or Input.is_action_pressed("attack")
	
	if fire_now and not _fire_pressed:
		# Cada pulsación empieza una ráfaga nueva; nunca se dispara sin munición.
		if current_weapon != null and not _is_burst_firing:
			current_weapon.burst_shots_fired = 0
		_try_fire()
	_fire_pressed = fire_now
	_fire_held = fire_held_now
	
	# Recarga
	if Input.is_action_just_pressed("reload") and not _reload_pressed:
		_start_reload()
	_reload_pressed = Input.is_action_pressed("reload")
	
	# Cambio arma (rueda ratón / 1-5)
	_handle_weapon_switch()

func _handle_weapon_switch() -> void:
	# Teclas 1-5
	for i in range(5):
		var action: String = "weapon_slot_%d" % (i + 1)
		if Input.is_action_just_pressed(action):
			if i < weapons.size() and weapons[i] != null:
				_equip_slot(i)
			else:
				EventBus.notification.emit("Ranura %d vacía" % (i + 1))
			return
	
	# Scroll (si configurado) - usar action strength para wheel
	var scroll_up: bool = Input.is_action_just_pressed("wheel_up")
	var scroll_down: bool = Input.is_action_just_pressed("wheel_down")
	if scroll_up or scroll_down:
		var new_slot: int = _next_filled_slot(1 if scroll_up else -1)
		if new_slot >= 0:
			_equip_slot(new_slot)
		elif weapons.is_empty():
			EventBus.notification.emit("Sin armas equipadas")

## Siguiente ranura ocupada en dirección `step` (+1/-1), o -1 si no hay ninguna.
## Evita el módulo por cero con loadouts vacíos y salta ranuras sin arma.
func _next_filled_slot(step: int) -> int:
	if weapons.is_empty():
		return -1
	var count: int = weapons.size()
	var start: int = current_slot if current_slot >= 0 else 0
	for i in range(1, count + 1):
		var idx: int = ((start + step * i) % count + count) % count
		if weapons[idx] != null:
			return idx
	return -1

func _try_fire() -> void:
	if current_weapon == null:
		return
	
	if current_weapon.category == Weapon.Category.MELEE:
		_do_melee()
		return
	
	if not current_weapon.can_fire():
		if current_weapon.ammo_in_chamber <= 0:
			_start_reload()
		elif current_weapon.burst_shots_fired >= current_weapon.burst_count:
			# esperar fin de burst
			pass
		else:
			emit_signal("dry_fire", current_weapon)
			if current_weapon.dry_fire_sound:
				_play_sound_at_position(current_weapon.dry_fire_sound, player.global_position)
		return
	
	_fire_shot()

func _fire_shot() -> void:
	if current_weapon == null:
		return
	
	# Un disparo suelto nunca debe salir sin munición ni con la ráfaga agotada.
	if not current_weapon.can_fire():
		_is_burst_firing = false
		return
	
	# Las balas NO consumen estamina (FASE 1 Punto 5).
	# El melee tiene su propio chequeo de aguante en _on_melee_attack (Player.gd)
	# y en _has_stamina_for(MELEE_STAMINA_MIN) más abajo.
	var now: float = Time.get_ticks_msec() / 1000.0
	# Dentro de una ráfaga el cadence es burst_delay, no el intervalo normal.
	var interval: float = current_weapon.burst_delay if _is_burst_firing else current_weapon.get_fire_interval()
	if now - current_weapon.last_shot_time < interval:
		return
	
	current_weapon.last_shot_time = now
	current_weapon.consume_ammo()
	current_weapon.apply_spread()
	
	# Burst logic: contar cada disparo y parar al llegar a burst_count.
	if current_weapon.burst_count > 1:
		current_weapon.burst_shots_fired += 1
		if current_weapon.burst_shots_fired >= current_weapon.burst_count:
			_is_burst_firing = false
		else:
			_is_burst_firing = true
			_burst_timer = current_weapon.burst_delay
	else:
		current_weapon.burst_shots_fired = 0
	
	# Emitir para que Player haga el raycast
	var from: Vector2 = player.global_position
	var to: Vector2 = player.get_global_mouse_position()
	emit_signal("fire_requested", current_weapon, from, to)
	
	# Telemetría defensiva: el contador lo lleva GameState si está presente.
	CombatTelemetry.record(self, "shots", 1.0)
	
	# Efectos locales
	_spawn_muzzle_flash(from, to)
	_spawn_shell_casing()
	_play_fire_sound()
	_apply_camera_shake()
	
	# Actualizar HUD ammo
	emit_signal("ammo_changed", 
		current_weapon.ammo_in_chamber, 
		current_weapon.current_ammo, 
		current_weapon.ammo_in_chamber)

func _do_melee() -> void:
	if current_weapon == null:
		return
	
	# El golpe exige aguante; si no hay, ni se emite la señal ni se anima.
	# MELEE_STAMINA_MIN refleja Player.MELEE_COST (coste real del swing).
	if not _has_stamina_for(MELEE_STAMINA_MIN):
		_notify_no_stamina()
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - current_weapon.last_shot_time < current_weapon.melee_cooldown:
		return
	
	current_weapon.last_shot_time = now
	
	var direction: Vector2 = (player.get_global_mouse_position() - player.global_position).normalized()
	emit_signal("melee_attack", current_weapon, direction)
	
	# Efectos
	_play_fire_sound()
	_apply_camera_shake(current_weapon.melee_hit_stop)
	
	# Sin hit-stop global: Engine.time_scale afecta a TODO el mundo (zombies,
	# física, HUD) y su timer se ralentiza a sí mismo. El impacto se expresa
	# solo con shake de cámara y partículas, sin tocar el estado del engine.

func _start_reload(force_empty: bool = false) -> void:
	if current_weapon == null:
		return
	
	if current_weapon.is_reloading:
		return
	
	# Verificar si hay munición en inventario
	if current_weapon.ammo_type != "" and Inventory.count(current_weapon.ammo_type) <= 0:
		EventBus.notification.emit("Sin munición para %s" % current_weapon.weapon_name)
		return
	
	if current_weapon.start_reload(force_empty):
		emit_signal("reloading_started", current_weapon, current_weapon.reload_timer)
		_play_reload_sound(force_empty)
		EventBus.notification.emit("Recargando %s..." % current_weapon.weapon_name)

func _equip_slot(slot: int) -> void:
	if slot < 0 or slot >= weapons.size():
		return
	if weapons[slot] == null:
		return
	if slot == current_slot:
		return
	
	# Cancelar recarga actual
	if current_weapon != null and current_weapon.is_reloading:
		current_weapon.cancel_reload()
	
	current_slot = slot
	# La instancia del slot ES el estado real: duplicarla y reinicializarla aquí
	# regalaba un cargador lleno cada vez que se cambiaba de arma.
	current_weapon = weapons[slot]
	
	# Una ráfaga o un disparo mantenido del arma anterior no siguen en la nueva.
	_is_burst_firing = false
	_burst_timer = 0.0
	_fire_held = false
	_fire_pressed = false
	
	emit_signal("weapon_changed", current_weapon)
	emit_signal("ammo_changed", 
		current_weapon.ammo_in_chamber, 
		current_weapon.current_ammo, 
		current_weapon.ammo_in_chamber)
	
	EventBus.notification.emit("Equipado: %s" % current_weapon.weapon_name)

## Al subir a un vehículo se aborta cualquier recarga en curso y se devuelve
## la munición ya insertada. También se corta la ráfaga: ningún arma debe
## seguir disparando en segundo plano mientras se conduce.
func cancel_reload_for_vehicle() -> void:
	for weapon in weapons:
		if weapon != null and weapon.is_reloading:
			weapon.cancel_reload(true)
	_is_burst_firing = false
	_burst_timer = 0.0
	_fire_held = false
	_fire_pressed = false
	if current_weapon != null:
		emit_signal("ammo_changed",
			current_weapon.ammo_in_chamber,
			current_weapon.current_ammo,
			current_weapon.ammo_in_chamber)

func add_weapon(weapon_resource: Weapon, slot: int = -1) -> bool:
	var instance: Weapon = weapon_resource.duplicate()
	instance._initialize_state()
	
	if slot >= 0 and slot < weapons.size():
		weapons[slot] = instance
	else:
		# Buscar slot libre
		for i in range(weapons.size()):
			if weapons[i] == null:
				weapons[i] = instance
				if current_weapon == null:
					_equip_slot(i)
				return true
		weapons.append(instance)
	
	if current_weapon == null:
		_equip_slot(weapons.find(instance))
	
	return true

func get_weapon_in_slot(slot: int) -> Weapon:
	if slot >= 0 and slot < weapons.size():
		return weapons[slot]
	return null

func _on_inventory_changed() -> void:
	# Actualizar ammo display si arma actual usa ese tipo
	if current_weapon != null and current_weapon.ammo_type != "":
		emit_signal("ammo_changed",
			current_weapon.ammo_in_chamber,
			current_weapon.current_ammo,
			current_weapon.ammo_in_chamber)

func _spawn_muzzle_flash(from: Vector2, to: Vector2) -> void:
	var direction: Vector2 = (to - from).normalized()
	var weapon_type: int = _get_particle_weapon_type()
	
	# Usar ParticleManager para muzzle flash
	if ParticleManager.instance != null:
		ParticleManager.instance.spawn_muzzle_flash(from, direction, weapon_type)
	
	# Fallback si no hay ParticleManager: el destello se parentea al root del mundo,
	# nunca al jugador, para que permanezca fijo aunque el jugador se mueva.
	if current_weapon.muzzle_flash != null and ParticleManager.instance == null:
		var flash: Node2D = current_weapon.muzzle_flash.instantiate() as Node2D
		_effects_parent().add_child(flash)
		flash.global_position = from + direction * current_weapon.muzzle_flash_offset.x
		flash.rotation = direction.angle()
		flash.scale *= current_weapon.muzzle_flash_scale
		get_tree().create_timer(1.0).timeout.connect(flash.queue_free)

## Los efectos efímeros se parentean a la escena actual para que se liberen
## automáticamente con reload_current_scene() (p. ej. al pulsar R tras morir).
func _effects_parent() -> Node:
	var scene: Node = get_tree().current_scene
	return scene if scene != null else get_tree().root

func _get_particle_weapon_type() -> int:
	if current_weapon == null:
		return 0
	match current_weapon.category:
		Weapon.Category.PISTOL: return 0
		Weapon.Category.SHOTGUN: return 1
		Weapon.Category.RIFLE: return 2
		Weapon.Category.HEAVY: return 3
		_: return 0

func _spawn_shell_casing() -> void:
	if current_weapon.shell_casing == null:
		return
	
	var casing: RigidBody2D = current_weapon.shell_casing.instantiate()
	_effects_parent().add_child(casing)
	
	var eject_dir: Vector2 = Vector2.RIGHT.rotated(player.rotation + PI * 0.8)
	var eject_pos: Vector2 = player.global_position + eject_dir * 10.0
	casing.global_position = eject_pos
	casing.rotation = player.rotation + (CombatTelemetry.random(self) - 0.5) * 0.4
	casing.apply_impulse(eject_dir * current_weapon.shell_eject_force)
	casing.apply_torque_impulse((CombatTelemetry.random(self) - 0.5) * 20.0)
	# Los casquillos son efecto efímero: no deben acumularse en el mundo.
	get_tree().create_timer(5.0).timeout.connect(casing.queue_free)

func _play_fire_sound() -> void:
	if current_weapon.fire_sound:
		_play_sound_at_position(current_weapon.fire_sound, player.global_position)

func _play_reload_sound(empty: bool) -> void:
	if empty and current_weapon.reload_empty_sound:
		_play_sound_at_position(current_weapon.reload_empty_sound, player.global_position)
	elif current_weapon.reload_sound:
		_play_sound_at_position(current_weapon.reload_sound, player.global_position)

func _play_sound_at_position(sound: AudioStream, position: Vector2) -> void:
	var player_node: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player_node.stream = sound
	player_node.position = position
	_effects_parent().add_child(player_node)
	player_node.play()
	# Auto-free cuando termine
	player_node.finished.connect(player_node.queue_free.bind())

func _apply_camera_shake(duration_override: float = -1.0) -> void:
	var cam: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return

	var mag: float = current_weapon.camera_shake_magnitude
	var dur: float = duration_override if duration_override > 0 else current_weapon.camera_shake_duration

	# Si la cámara objetivo cambió (cambio de arma/escena), restaurar la anterior.
	if _shake_camera != null and is_instance_valid(_shake_camera) and _shake_camera != cam:
		_shake_camera.offset = _shake_base_offset
		_shake_camera = null
		if _shake_timer != null and is_instance_valid(_shake_timer):
			_shake_timer.stop()

	if _shake_timer == null or not is_instance_valid(_shake_timer):
		_shake_timer = Timer.new()
		_shake_timer.one_shot = true
		add_child(_shake_timer)

	if _shake_timer.timeout.is_connected(_on_shake_timeout):
		_shake_timer.timeout.disconnect(_on_shake_timeout)
	_shake_timer.timeout.connect(_on_shake_timeout)

	# Capturar la base solo si no hay shake en curso; si disparamos durante un
	# shake, cam.offset ya está desplazado y recapturarlo acumularía el temblor.
	var shake_active: bool = (_shake_camera == cam and not _shake_timer.is_stopped())
	if not shake_active:
		_shake_base_offset = cam.offset
	_shake_camera = cam
	# Jitter + kick direccional. El kick crece con el retroceso acumulado: en una
	# ráfaga la cámara se desplaza cada vez más hacia arriba respecto al aim.
	# El offset base nunca se recalcula durante un shake (regresión check 36).
	var jitter_x: float = CombatTelemetry.random(self) * 2.0 - 1.0
	var jitter_y: float = CombatTelemetry.random(self) * 2.0 - 1.0
	var kick_dir: Vector2 = Vector2.UP.rotated(player.rotation)
	var kick: Vector2 = kick_dir * current_weapon.current_recoil * 70.0 * current_weapon.recoil_camera_kick
	cam.offset = _shake_base_offset + Vector2(jitter_x * mag, jitter_y * mag) + kick
	_shake_timer.wait_time = maxf(dur, 0.01)
	_shake_timer.start()

func _on_shake_timeout() -> void:
	if _shake_camera != null and is_instance_valid(_shake_camera):
		_shake_camera.offset = _shake_base_offset
	_shake_camera = null

func _load_default_loadout() -> void:
	# Cuatro recursos reales en sus ranuras naturales; la quinta queda libre.
	# add_weapon() duplica el recurso y reinicia su estado: cada slot conserva
	# su propia munición, bloom y desgaste sin compartir referencias.
	add_weapon(RES_MACHETE, 0)
	add_weapon(RES_PISTOL, 1)
	add_weapon(RES_SHOTGUN, 2)
	add_weapon(RES_RIFLE, 3)
	weapons.resize(5)

## API pública para save/load
## Las instancias son duplicate() de los .tres y no conservan resource_path,
## así que se serializa el nombre y se resuelve contra las plantillas reales.
func _template_by_name(weapon_name: String) -> Weapon:
	for template: Weapon in [RES_MACHETE, RES_PISTOL, RES_SHOTGUN, RES_RIFLE]:
		if template != null and template.weapon_name == weapon_name:
			return template
	return null

func get_save_data() -> Dictionary:
	var data: Dictionary = {}
	data["current_slot"] = current_slot
	var entries: Array = []
	for w in weapons:
		if w == null:
			entries.append(null)
		else:
			entries.append({
				"weapon_name": w.weapon_name,
				"slot": weapons.find(w),
				"state": w.get_state_dict(),
			})
	data["weapons"] = entries
	return data

func load_save_data(data: Dictionary) -> void:
	var saved_slot: int = int(data.get("current_slot", 0))
	var weapons_data: Array = data.get("weapons", [])
	weapons.clear()
	weapons.resize(5)
	for entry in weapons_data:
		if entry == null:
			continue
		var template: Weapon = _template_by_name(String(entry.get("weapon_name", "")))
		if template == null:
			continue
		var instance: Weapon = template.duplicate()
		instance.load_state_dict(entry.get("state", {}))
		var slot: int = int(entry.get("slot", -1))
		if slot >= 0 and slot < weapons.size():
			weapons[slot] = instance
	current_slot = -1
	current_weapon = null
	if saved_slot >= 0 and saved_slot < weapons.size() and weapons[saved_slot] != null:
		_equip_slot(saved_slot)
	else:
		for i in range(weapons.size()):
			if weapons[i] != null:
				_equip_slot(i)
				break
