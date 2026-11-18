extends Area2D
class_name AcidSpit

## Proyectil de ácido del Spitter

@export var speed: float = 200.0
@export var damage: float = 15.0
@export var max_range: float = 300.0
@export var lifetime: float = 3.0

@onready var collision: CollisionShape2D = $Collision
@onready var sprite: Sprite2D = $Sprite
@onready var particles: GPUParticles2D = $Particles

var _direction: Vector2 = Vector2.ZERO
var _traveled: float = 0.0
var _timer: float = 0.0

func _ready() -> void:
	add_to_group("projectiles")
	collision_layer = 4
	# Capa 1 = jugador y paredes. Los zombies (capa 2) no deben bloquear el ácido.
	collision_mask = 1
	# CharacterBody2D no tiene body_entered: al ser Area2D hay que conectarla.
	body_entered.connect(_on_body_entered)

func launch(direction: Vector2, dmg: float, range: float) -> void:
	_direction = direction
	damage = dmg
	max_range = range
	rotation = direction.angle()
	
	if particles != null:
		particles.emitting = true

func _physics_process(delta: float) -> void:
	if _traveled >= max_range or _timer >= lifetime:
		queue_free()
		return
	
	# Area2D no tiene move_and_slide: avance directo en coordenadas de mundo.
	global_position += _direction * speed * delta
	
	_traveled += speed * delta
	_timer += delta

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("zombies"):
		return  # el ácido no daña a otros zombis ni se queda pegado a ellos
	if body.is_in_group("player") and body.has_method("receive_damage"):
		body.call("receive_damage", damage)
	# Tanto en el jugador como en una pared: impacto, charco y desaparición.
	_create_splash()
	queue_free()

func _create_splash() -> void:
	if ParticleManager.instance != null:
		ParticleManager.instance.spawn_impact_flesh(global_position, _direction)
	
	# Crear charco de ácido que daña al pisar. Debe vivir dentro de la escena
	# para no sobrevivir a un reinicio ni ignorar la pausa del juego.
	# Se monta completo FUERA del árbol: dentro de un callback de física no se
	# puede cambiar la monitorización de un Area2D ni añadir shapes.
	var puddle: Node2D = Node2D.new()
	puddle.add_to_group("acid_puddles")
	puddle.global_position = global_position
	
	var area: Area2D = Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var col: CollisionShape2D = CollisionShape2D.new()
	var circ: CircleShape2D = CircleShape2D.new()
	circ.radius = 40.0
	col.shape = circ
	area.add_child(col)
	# Copiar el daño a una local: si la lambda leyera `damage` (miembro de
	# AcidSpit) capturaría `self`, y este proyectil se libera justo después en
	# _on_body_entered(). El charco quedaría con un callable colgado.
	var puddle_damage: float = damage * 0.3
	area.body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("player") and body.has_method("receive_damage"):
			body.call("receive_damage", puddle_damage)
	)
	puddle.add_child(area)
	
	var sprite_puddle: Sprite2D = Sprite2D.new()
	sprite_puddle.texture = _create_puddle_texture()
	sprite_puddle.scale = Vector2(1.5, 1.5)
	puddle.add_child(sprite_puddle)
	
	var t := Timer.new()
	t.wait_time = 10.0
	t.one_shot = true
	t.timeout.connect(puddle.queue_free.bind())
	puddle.add_child(t)
	
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	# El áreas se registra en el servidor físico al entrar al árbol: hacerlo
	# aplazado porque estamos dentro del flush de una consulta de colisión.
	parent.call_deferred("add_child", puddle)
	t.call_deferred("start")

func _create_puddle_texture() -> ImageTexture:
	var img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.5, 0.2, 0.0))
	var center: Vector2i = Vector2i(32, 32)
	var acid_color: Color = Color(0.3, 0.7, 0.3, 0.6)
	
	for y in range(64):
		for x in range(64):
			var dist: float = Vector2i(x, y).distance_to(center)
			if dist < 28.0:
				var alpha: float = 1.0 - (dist / 28.0)
				img.set_pixel(x, y, Color(0.3, 0.7, 0.3, 0.6 * alpha))
	
	return ImageTexture.create_from_image(img)