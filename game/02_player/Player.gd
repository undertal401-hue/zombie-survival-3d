extends CharacterBody2D

const SPEED := 200.0
const SPRINT_SPEED := 320.0
const MAX_HP := 100.0

@onready var input_handler: InputHandler = $InputHandler

var hp: float = MAX_HP
var _spawn_position: Vector2

func _ready() -> void:
	add_to_group("player")
	_spawn_position = global_position

func _physics_process(delta: float) -> void:
	var move: Vector2 = input_handler.get_move_vector()
	var direction: Vector2 = Vector2(move.x, -move.y)
	if direction.length() > 0.0:
		direction = direction.normalized()

	var speed: float = SPEED
	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED

	velocity = direction * speed
	move_and_slide()

	var mouse: Vector2 = get_global_mouse_position()
	if global_position.distance_to(mouse) > 0.5:
		look_at(mouse)

func receive_damage(amount: float) -> void:
	hp = max(hp - amount, 0.0)
	EventBus.player_damaged.emit(amount, self)
	if hp <= 0.0:
		hp = MAX_HP
		global_position = _spawn_position

func heal(amount: float) -> void:
	hp = min(hp + amount, MAX_HP)
