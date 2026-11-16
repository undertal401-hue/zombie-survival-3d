extends CharacterBody2D

const SPEED := 200.0
const SPRINT_SPEED := 320.0
const MAX_HP := 100.0
const MAX_STAMINA := 100.0

const ATTACK_RANGE := 46.0
const ATTACK_DAMAGE := 34.0
const ATTACK_COOLDOWN := 0.55
const ATTACK_COST := 20.0
const ATTACK_ARC := 0.8

const SPRINT_DRAIN := 22.0
const STAMINA_REGEN := 16.0
const REGEN_DELAY := 0.7
const MEDKIT_HEAL := 45.0

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

var hp: float = MAX_HP
var stamina: float = MAX_STAMINA
var hunger: float = 0.0
var is_dead: bool = false

var _attack_cooldown: float = 0.0
var _swing_time: float = 0.0
var _regen_delay: float = 0.0
var _last_stamina_int: int = int(MAX_STAMINA)
var _last_hunger_int: int = -1
var _starvation_timer: float = 0.0
var _hunger_warning_shown: bool = false
var _starvation_warned: bool = false

func _ready() -> void:
	add_to_group("player")
	hunger = max_hunger
	EventBus.player_health_changed.emit(hp, MAX_HP)
	EventBus.player_stamina_changed.emit(stamina, MAX_STAMINA)
	_emit_hunger_if_changed(true)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_update_hunger(delta)
	if is_dead:
		return

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if _swing_time > 0.0:
		_swing_time = maxf(_swing_time - delta, 0.0)
		queue_redraw()

	var move: Vector2 = input_handler.get_move_vector()
	var direction: Vector2 = Vector2(move.x, -move.y)
	if direction.length() > 0.0:
		direction = direction.normalized()

	var sprinting: bool = Input.is_action_pressed("sprint") and stamina > 0.0 and direction.length() > 0.0
	var speed: float = SPRINT_SPEED if sprinting else SPEED

	if sprinting:
		stamina = maxf(stamina - SPRINT_DRAIN * delta, 0.0)
		_regen_delay = REGEN_DELAY
	else:
		_regen_delay = maxf(_regen_delay - delta, 0.0)
		if _regen_delay <= 0.0:
			stamina = minf(stamina + STAMINA_REGEN * delta, MAX_STAMINA)
	_emit_stamina_if_changed()

	velocity = direction * speed
	move_and_slide()

	var mouse: Vector2 = get_global_mouse_position()
	if global_position.distance_to(mouse) > 0.5:
		look_at(mouse)

	if Input.is_action_just_pressed("attack"):
		attack()
	if Input.is_action_just_pressed("use_medkit"):
		use_medkit()
	if Input.is_action_just_pressed("use_food"):
		use_food()

## Golpe en cono corto. Cuesta aguante y respeta paredes (raycast de linea de vista).
func attack() -> bool:
	if is_dead or _attack_cooldown > 0.0 or stamina < ATTACK_COST:
		return false

	_attack_cooldown = ATTACK_COOLDOWN
	stamina = maxf(stamina - ATTACK_COST, 0.0)
	_regen_delay = REGEN_DELAY
	_swing_time = 0.14
	_emit_stamina_if_changed()
	queue_redraw()

	var hit_any: bool = false
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(zombie) or not zombie.has_method("take_damage"):
			continue
		var to_zombie: Vector2 = zombie.global_position - global_position
		var dist: float = to_zombie.length()
		if dist > ATTACK_RANGE + 14.0:
			continue
		if absf(angle_difference(rotation, to_zombie.angle())) > ATTACK_ARC:
			continue
		var query := PhysicsRayQueryParameters2D.create(global_position, zombie.global_position, 1, [get_rid(), zombie.get_rid()])
		if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			continue
		zombie.call("take_damage", ATTACK_DAMAGE, self)
		hit_any = true

	return hit_any

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
	EventBus.player_damaged.emit(amount, self)
	EventBus.player_health_changed.emit(hp, MAX_HP)
	if hp <= 0.0:
		_die()

func heal(amount: float) -> void:
	if is_dead:
		return
	hp = minf(hp + amount, MAX_HP)
	EventBus.player_health_changed.emit(hp, MAX_HP)

func _die() -> void:
	is_dead = true
	remove_from_group("player")
	collision_layer = 0
	collision_mask = 0
	input_handler.set_process(false)
	set_physics_process(false)
	modulate = Color(0.45, 0.45, 0.45, 1.0)
	EventBus.game_over.emit()

func _emit_stamina_if_changed() -> void:
	var current: int = int(round(stamina))
	if current == _last_stamina_int:
		return
	_last_stamina_int = current
	EventBus.player_stamina_changed.emit(stamina, MAX_STAMINA)

func _draw() -> void:
	if _swing_time <= 0.0:
		return
	var alpha: float = clampf(_swing_time / 0.14, 0.0, 1.0)
	draw_arc(Vector2.ZERO, ATTACK_RANGE, -0.75, 0.75, 16, Color(1.0, 0.95, 0.7, alpha * 0.9), 4.0, true)
