extends CharacterBody2D

const SPEED := 200.0
const SPRINT_SPEED := 320.0
const MAX_HP := 100.0
const MAX_STAMINA := 100.0

const MELEE_RANGE := 46.0
const MELEE_DAMAGE := 34.0
const MELEE_COOLDOWN := 0.55
const MELEE_COST := 20.0
const MELEE_ARC := 0.8

const SPRINT_DRAIN := 22.0
const STAMINA_REGEN := 16.0
const REGEN_DELAY := 0.7
const MEDKIT_HEAL := 45.0

## Combate: la regeneración baja en combate, sin pausar el mundo ni tocar
## Engine.time_scale. El suelo de aguante evita disparos "gratis" al agotarse.
const FIRE_STAMINA_MIN := 4.0
const COMBAT_REGEN_MULTIPLIER := 0.4
const COMBAT_STATE_TIME := 4.0
## Combo melee: tres golpes encadenables; el tercero es el finisher.
const COMBO_WINDOW := 1.2

const FOOD_ITEM_ID := "comida"
const FOOD_RESTORE := 35.0
const FOOD_FULL_MARGIN := 5.0
const STARVATION_TICK := 2.0
const STARVATION_DAMAGE := 2.0

## Ajustables desde el inspector o por código. Con 0.2/s una barra llena
## dura unos 8 minutos; la comida recupera 35 puntos.
@export var max_hunger: float = 100.0
@export var hunger_drain_per_second: float = 0.2
@export var hunger_warning_threshold: float = 30.0

@onready var input_handler: InputHandler = $InputHandler
@onready var weapon_controller: WeaponController = $WeaponController
@onready var player_visual: PlayerVisual = $PlayerVisual

var hp: float = MAX_HP
var stamina: float = MAX_STAMINA
var hunger: float = 0.0
var is_dead: bool = false

var _melee_cooldown: float = 0.0
var _swing_time: float = 0.0
var _regen_delay: float = 0.0
## Estado de combate y combo melee (0..2; -1 = sin combo activo).
var _combat_timer: float = 0.0
var _combo_step: int = -1
var _combo_timer: float = 0.0
## El knockback melee se guarda como impulso: aplicarlo desde la señal no sirve
## porque _physics_process() sobrescribe velocity justo después.
var _melee_knockback: Vector2 = Vector2.ZERO
var _knockback_timer: float = 0.0
const KNOCKBACK_TIME: float = 0.12
var _last_stamina_int: int = int(MAX_STAMINA)
var _last_hunger_int: int = -1
var _starvation_timer: float = 0.0
var _hunger_warning_shown: bool = false
var _starvation_warned: bool = false

## Inventario
var inventory_open: bool = false

## Vehículo: mientras se conduce el jugador viaja como pasajero y no procesa
## movimiento propio. La máscara se desactiva para que la camioneta no choque
## con él, pero la capa se mantiene para que las puertas del bosque lo detecten.
var is_driving: bool = false
var active_vehicle: Node2D = null

func _ready() -> void:
	add_to_group("player")
	hunger = max_hunger
	EventBus.player_health_changed.emit(hp, MAX_HP)
	EventBus.player_stamina_changed.emit(stamina, MAX_STAMINA)
	_emit_hunger_if_changed(true)
	
	# Conectar señales del WeaponController
	weapon_controller.fire_requested.connect(_on_fire_requested)
	weapon_controller.melee_attack.connect(_on_melee_attack)
	weapon_controller.weapon_changed.connect(_on_weapon_changed)
	weapon_controller.ammo_changed.connect(_on_ammo_changed)
	
	# Conectar señales visuales
	weapon_controller.fire_requested.connect(_on_fire_visual)
	weapon_controller.melee_attack.connect(_on_melee_visual)
	weapon_controller.reloading_started.connect(_on_reload_visual)
	weapon_controller.reloading_finished.connect(_on_reload_finished_visual)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_update_hunger(delta)
	if is_dead:
		return

	if is_driving:
		# El vehículo actualiza nuestra posición; solo mantenemos el visual
		# sincronizado y no permitimos armas, inventario ni interacciones.
		if player_visual != null and active_vehicle != null:
			player_visual.update_from_player(self, active_vehicle.velocity, weapon_controller)
		return

	_combat_timer = maxf(_combat_timer - delta, 0.0)
	if _combo_timer > 0.0:
		_combo_timer = maxf(_combo_timer - delta, 0.0)
		if _combo_timer <= 0.0:
			_combo_step = -1
	_melee_cooldown = maxf(_melee_cooldown - delta, 0.0)
	if _swing_time > 0.0:
		_swing_time = maxf(_swing_time - delta, 0.0)
		queue_redraw()
	var move: Vector2 = input_handler.get_move_vector()
	var direction: Vector2 = Vector2.ZERO
	
	if not inventory_open:
		move = input_handler.get_move_vector()
		direction = Vector2(move.x, -move.y)
		if direction.length() > 0.0:
			direction = direction.normalized()
	else:
		direction = Vector2.ZERO

	var sprinting: bool = Input.is_action_pressed("sprint") and stamina > 0.0 and direction.length() > 0.0
	# Armas pesadas o de dos manos reducen la velocidad al caminar y correr.
	var speed_modifier: float = 1.0
	if weapon_controller != null and weapon_controller.current_weapon != null:
		speed_modifier = weapon_controller.current_weapon.move_speed_multiplier
	var speed: float = (SPRINT_SPEED if sprinting else SPEED) * speed_modifier

	if sprinting:
		stamina = maxf(stamina - SPRINT_DRAIN * delta, 0.0)
		_regen_delay = REGEN_DELAY
	else:
		_regen_delay = maxf(_regen_delay - delta, 0.0)
		if _regen_delay <= 0.0:
			# En combate la barra se rellena más despacio, pero el mundo sigue
			# avanzando a velocidad normal: no hay time_scale ni congelación.
			var regen: float = STAMINA_REGEN
			if _combat_timer > 0.0:
				regen *= COMBAT_REGEN_MULTIPLIER
			stamina = minf(stamina + regen * delta, MAX_STAMINA)
	_emit_stamina_if_changed()

	velocity = direction * speed
	if _knockback_timer > 0.0:
		_knockback_timer = maxf(_knockback_timer - delta, 0.0)
		velocity += _melee_knockback * (_knockback_timer / KNOCKBACK_TIME)
	move_and_slide()

	# Puntería: el jugador conserva rotation como dirección de avance (+X)
	# porque el combate (arco melee, fogonazo, casquillos y kick) la consume.
	# Se asigna directamente en vez de look_at para dejar una única fuente de
	# verdad; el sprite hijo aplica su propia compensación de +PI/2.
	var mouse: Vector2 = get_global_mouse_position()
	var to_mouse: Vector2 = mouse - global_position
	if to_mouse.length_squared() > 0.25:
		rotation = to_mouse.angle()

	# Actualizar visual después de fijar la puntería para evitar desfase.
	if player_visual != null:
		player_visual.update_from_player(self, velocity, weapon_controller)

	if not inventory_open:
		if Input.is_action_just_pressed("use_medkit"):
			use_medkit()
		if Input.is_action_just_pressed("use_food"):
			use_food()
	
	if Input.is_action_just_pressed("inventory"):
		EventBus.notification.emit("Inventario: usa Tab o Escape para cerrar")

## Golpe en cono corto. Cuesta aguante y respeta paredes (raycast de linea de vista).
## Handler para disparo de arma (desde WeaponController)
func _on_fire_requested(weapon: Weapon, from_pos: Vector2, to_pos: Vector2) -> void:
	if is_dead:
		return
	
	# Doble check de aguante: WeaponController ya filtra antes de consumir bala,
	# aquí se cobra el coste real solo si el disparo llega a ejecutarse.
	var cost: float = maxf(FIRE_STAMINA_MIN, weapon.get_stamina_cost())
	if stamina + 0.0001 < cost:
		return
	stamina = maxf(stamina - cost, 0.0)
	_regen_delay = REGEN_DELAY
	_mark_combat()
	_emit_stamina_if_changed()
	
	var direction: Vector2 = (to_pos - from_pos).normalized()
	
	# Dispersión aleatoria (rng('combat') si GameState está disponible) más el
	# retroceso acumulado: un sesgo fijo que abre la ráfaga hacia un lado.
	var roll: float = CombatTelemetry.random(self) * 2.0 - 1.0
	var spread: float = roll * weapon.get_effective_spread()
	direction = direction.rotated(spread)
	direction = direction.rotated(weapon.get_recoil_angle())
	
	var end_pos: Vector2 = from_pos + direction * weapon.range
	var origin: Vector2 = from_pos
	var excluded: Array[RID] = [get_rid()]
	var remaining_penetration: int = weapon.penetration
	var walls_pierced: int = 0
	
	# Un rayo por pared atravesada. Tope de 8 iteraciones para evitar bucles
	# patológicos si un collider devuelve una posición degenerada.
	for _i in range(8):
		var query := PhysicsRayQueryParameters2D.create(origin, end_pos, 3, excluded)
		var result := get_world_2d().direct_space_state.intersect_ray(query)
		if result.is_empty():
			if _i == 0:
				EventBus.notification.emit("Sin objetivo")
			break
		var hit_pos: Vector2 = result.position
		var collider: Object = result.collider
		if collider == null:
			break
		
		var is_zombie: bool = collider.has_method("take_damage") and collider.is_in_group("zombies")
		if not is_zombie and remaining_penetration > 0 and collider is CollisionObject2D:
			# Pared atravesable: chispa, excluir este collider y seguir desde
			# justo después del punto de impacto.
			if ParticleManager.instance != null:
				ParticleManager.instance.spawn_impact(hit_pos, direction, _get_surface_type(collider))
			excluded.append((collider as CollisionObject2D).get_rid())
			walls_pierced += 1
			remaining_penetration -= 1
			origin = hit_pos + direction * 2.0
			continue
		
		if is_zombie:
			# Falloff por distancia: el daño baja de base_damage a min_damage
			# entre damage_falloff_start y damage_falloff_end.
			var damage: float = weapon.base_damage
			if weapon.damage_falloff_start > 0.0 and weapon.damage_falloff_end > weapon.damage_falloff_start:
				var shot_distance: float = from_pos.distance_to(hit_pos)
				if shot_distance > weapon.damage_falloff_start:
					var t: float = clampf((shot_distance - weapon.damage_falloff_start) /
						(weapon.damage_falloff_end - weapon.damage_falloff_start), 0.0, 1.0)
					damage = lerpf(weapon.base_damage, weapon.min_damage, t)
			# El hitbox del zombie mide 16x16 centrado (y-8 .. y+8): la cabeza
			# es el cuarto superior y las piernas el cuarto inferior. El umbral
			# anterior (y-10) estaba fuera del hitbox y hacía imposible el headshot.
			var zombie: CharacterBody2D = collider as CharacterBody2D
			if zombie != null:
				if hit_pos.y < zombie.global_position.y - 4.0:
					damage *= weapon.headshot_multiplier
				elif hit_pos.y > zombie.global_position.y + 4.0:
					damage *= weapon.limb_multiplier
			# Cada pared atravesada debilita el proyectil un 25%.
			if walls_pierced > 0:
				damage *= pow(0.75, walls_pierced)
			collider.call("take_damage", damage, self)
			# Daño real (ya con headshot/limb/falloff/penetración) a telemetría.
			CombatTelemetry.record(self, "damage", damage)
			EventBus.notification.emit("Impacto!")
			if ParticleManager.instance != null:
				ParticleManager.instance.spawn_blood(hit_pos, direction, 15)
		else:
			EventBus.notification.emit("Impacto en obstáculo")
			if ParticleManager.instance != null:
				ParticleManager.instance.spawn_impact(hit_pos, direction, _get_surface_type(collider))
		break
	# El destello lo genera WeaponController/ParticleManager en coordenadas del mundo.
	# No se dibuja aquí: si fuera hijo del jugador, se movería con él.

func _get_surface_type(collider: Object) -> int:
	if collider == null:
		return ImpactParticles.SurfaceType.CONCRETE
	if collider is CharacterBody2D:
		return ImpactParticles.SurfaceType.FLESH
	if collider is StaticBody2D:
		# Podríamos checkear el material o nombre para diferenciar
		return ImpactParticles.SurfaceType.CONCRETE
	if collider is RigidBody2D:
		return ImpactParticles.SurfaceType.WOOD
	return ImpactParticles.SurfaceType.CONCRETE

## Handler para ataque melee (desde WeaponController)
func _on_melee_attack(weapon: Weapon, direction: Vector2) -> void:
	if is_dead or _melee_cooldown > 0.0 or stamina < MELEE_COST:
		return
	
	# Combo de tres tiempos: al encadenar dentro de COMBO_WINDOW avanza el paso;
	# si se deja pasar el margen se reinicia al primer golpe.
	if _combo_timer > 0.0:
		_combo_step = (_combo_step + 1) % 3
	else:
		_combo_step = 0
	_combo_timer = COMBO_WINDOW
	var combo_damage: float = _combo_damage_multiplier()
	
	_melee_cooldown = MELEE_COOLDOWN
	stamina = maxf(stamina - MELEE_COST, 0.0)
	_regen_delay = REGEN_DELAY
	_mark_combat()
	_swing_time = 0.14
	_emit_stamina_if_changed()
	queue_redraw()
	# La animación existente se dispara desde _on_melee_visual (PlayerVisual
	# intacto): cada paso del combo reproduce el mismo ataque melee.
	
	var hit_any: bool = false
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(zombie) or not zombie.has_method("take_damage"):
			continue
		var to_zombie: Vector2 = zombie.global_position - global_position
		var dist: float = to_zombie.length()
		if dist > weapon.melee_range:
			continue
		if absf(angle_difference(rotation, to_zombie.angle())) > weapon.melee_arc:
			continue
		var query := PhysicsRayQueryParameters2D.create(global_position, zombie.global_position, 3, [get_rid(), zombie.get_rid()])
		if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			continue
		var damage: float = weapon.base_damage * combo_damage
		zombie.call("take_damage", damage, self)
		CombatTelemetry.record(self, "damage", damage)
		hit_any = true
	
	# Knockback al jugador si golpeó algo: se aplica en _physics_process()
	# después de asignar velocity, para que el movimiento no lo borre.
	# El finisher (tercer golpe) empuja algo más.
	if hit_any:
		var knockback_scale: float = 0.18 if _combo_step == 2 else 0.1
		_melee_knockback = -direction * weapon.melee_knockback * knockback_scale
		_knockback_timer = KNOCKBACK_TIME

func _on_weapon_changed(weapon: Weapon) -> void:
	# Cambiar de arma rompe el combo: no se puede rematar con otra herramienta.
	_reset_combo()
	# Actualizar HUD u otros sistemas
	pass

func _on_ammo_changed(current: int, total: int, in_chamber: int) -> void:
	# HUD se actualiza via señal
	pass

## Handlers visuales
func _on_fire_visual(weapon: Weapon, from_pos: Vector2, to_pos: Vector2) -> void:
	if player_visual != null and not is_dead:
		player_visual.play_attack(int(weapon.category))

func _on_melee_visual(weapon: Weapon, direction: Vector2) -> void:
	if player_visual != null and not is_dead:
		player_visual.play_attack(int(weapon.category))

func _on_reload_visual(weapon: Weapon, duration: float) -> void:
	if player_visual != null and not is_dead:
		player_visual.play_reload(int(weapon.category))

func _on_reload_finished_visual(weapon: Weapon) -> void:
	# La animación de recarga termina sola, _is_attacking se resetea en animation_finished
	pass

## Activa o desactiva el modo pasajero. Lo llama DriveableVehicle al subir,
## bajar o cuando el jugador muere al volante.
func set_vehicle_mode(enabled: bool, vehicle: Node2D) -> void:
	is_driving = enabled
	active_vehicle = vehicle
	inventory_open = false
	if enabled and weapon_controller != null and weapon_controller.has_method("cancel_reload_for_vehicle"):
		weapon_controller.call("cancel_reload_for_vehicle")
	_reset_combo()
	collision_layer = 1
	collision_mask = 0 if enabled else 3
	velocity = Vector2.ZERO
	if player_visual != null:
		player_visual.visible = not enabled

func use_medkit() -> bool:
	if is_dead or hp >= MAX_HP:
		return false
	if not Inventory.remove_item("medkit", 1):
		EventBus.notification.emit("No tienes botiquines")
		return false
	heal(MEDKIT_HEAL)
	EventBus.notification.emit("Botiquín usado: +%d vida" % int(MEDKIT_HEAL))
	return true

func use_food() -> bool:
	if is_dead:
		return false
	if hunger >= max_hunger - FOOD_FULL_MARGIN:
		EventBus.notification.emit("No tienes hambre")
		return false
	if not Inventory.remove_item(FOOD_ITEM_ID, 1):
		EventBus.notification.emit("No tienes comida")
		return false
	var before: float = hunger
	hunger = minf(hunger + FOOD_RESTORE, max_hunger)
	_emit_hunger_if_changed(true)
	EventBus.notification.emit("Comida consumida: +%d hambre" % int(round(hunger - before)))
	return true

func _update_hunger(delta: float) -> void:
	if hunger > 0.0:
		hunger = maxf(hunger - hunger_drain_per_second * delta, 0.0)
	_emit_hunger_if_changed()

	if hunger <= 0.0:
		if not _starvation_warned:
			_starvation_warned = true
			EventBus.notification.emit("¡Inanición! Pierdes vida. Busca comida.")
		_starvation_timer += delta
		while _starvation_timer >= STARVATION_TICK:
			_starvation_timer -= STARVATION_TICK
			receive_damage(STARVATION_DAMAGE)
			if is_dead:
				return
	else:
		_starvation_timer = 0.0
		_starvation_warned = false

	_update_hunger_warning()

func _update_hunger_warning() -> void:
	var hungry: bool = hunger <= hunger_warning_threshold
	if hungry and not _hunger_warning_shown:
		_hunger_warning_shown = true
		EventBus.notification.emit("Tienes hambre. Busca comida.")
	elif not hungry:
		_hunger_warning_shown = false

func _emit_hunger_if_changed(force: bool = false) -> void:
	var current: int = int(round(hunger))
	if not force and current == _last_hunger_int:
		return
	_last_hunger_int = current
	EventBus.player_hunger_changed.emit(hunger, max_hunger, hunger_warning_threshold)

func receive_damage(amount: float) -> void:
	if is_dead:
		return
	hp = maxf(hp - amount, 0.0)
	_mark_combat()
	EventBus.player_damaged.emit(amount, self)
	EventBus.player_health_changed.emit(hp, MAX_HP)
	
	# Animación de daño
	if player_visual != null:
		player_visual.play_hurt()
	
	if hp <= 0.0:
		_die()

func heal(amount: float) -> void:
	if is_dead:
		return
	hp = minf(hp + amount, MAX_HP)
	EventBus.player_health_changed.emit(hp, MAX_HP)

func _die() -> void:
	is_dead = true
	if is_driving and active_vehicle != null and is_instance_valid(active_vehicle) \
			and active_vehicle.has_method("on_driver_dead"):
		active_vehicle.call("on_driver_dead")
	is_driving = false
	active_vehicle = null
	_reset_combo()
	remove_from_group("player")
	collision_layer = 0
	collision_mask = 0
	input_handler.set_process(false)
	set_physics_process(false)
	if player_visual != null:
		player_visual.visible = true
	modulate = Color(0.45, 0.45, 0.45, 1.0)
	
	# Animación de muerte
	if player_visual != null:
		player_visual.play_death()
	
	EventBus.game_over.emit()

func _emit_stamina_if_changed() -> void:
	var current: int = int(round(stamina))
	if current == _last_stamina_int:
		return
	_last_stamina_int = current
	EventBus.player_stamina_changed.emit(stamina, MAX_STAMINA)

## Mantiene el estado de combate activo un tiempo tras la última acción.
## Solo afecta a la velocidad de regeneración: nunca pausa ni escala el tiempo.
func _mark_combat(duration: float = COMBAT_STATE_TIME) -> void:
	_combat_timer = maxf(_combat_timer, duration)

func _combo_damage_multiplier() -> float:
	match _combo_step:
		1: return 1.15
		2: return 1.7  # finisher
		_: return 1.0

func _reset_combo() -> void:
	_combo_step = -1
	_combo_timer = 0.0

func _draw() -> void:
	if _swing_time > 0.0:
		var alpha: float = clampf(_swing_time / 0.14, 0.0, 1.0)
		draw_arc(Vector2.ZERO, MELEE_RANGE, -0.75, 0.75, 16, Color(1.0, 0.95, 0.7, alpha * 0.9), 4.0, true)
