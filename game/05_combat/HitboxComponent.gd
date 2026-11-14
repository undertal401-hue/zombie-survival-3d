class_name HitboxComponent


extends Area3D
## Hitbox ofensivo: detecta overlaps con hurtboxes y emite dano.
##
## Se adjunta a armas cuerpo a cuerpo o a puntos de impacto. Usa cooldown por
## objetivo para no aplicar dano multiple veces por frame.
## Accesible globalmente via `HitboxComponent` (class_name).

const HITBOX_LAYER: int = 6

@export var damage_info: DamageInfo = null
@export var team: int = 0
@export var hit_cooldown: float = 0.2

var _last_hit: Dictionary = {}
var _damage_system: DamageSystem


func _ready() -> void:
	collision_layer = 1 << (HITBOX_LAYER - 1)
	collision_mask = 1 << 0  # capa player (hurtbox)
	_damage_system = get_tree().get_first_node_in_group("damage_system") as DamageSystem
	if _damage_system == null:
		_damage_system = DamageSystem.new()
		_damage_system.name = "DamageSystem"
		add_child(_damage_system)
	_build_shape()
	area_entered.connect(_on_area_entered)

func _build_shape() -> void:
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.5, 1.5, 1.5)
	shape_node.shape = box
	shape_node.position = Vector3(0.0, 1.0, -0.5)
	add_child(shape_node)


## Establece el paquete de dano que aplicara este hitbox.
func set_damage_info(info: DamageInfo) -> void:
	damage_info = info


## Registra un golpe contra un area (hurtbox).
func _on_area_entered(area: Area3D) -> void:
	if damage_info == null:
		return
	var body: Node3D = area.get_parent() as Node3D
	if body == null or (not body.has_method("take_damage") and not body.has_method("receive_damage")):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var last: float = float(_last_hit.get(body, 0.0))
	if now - last < hit_cooldown:
		return
	_last_hit[body] = now
	var info: DamageInfo = damage_info.duplicate_info()
	info.hit_point = body.global_position
	if body.has_method("take_damage"):
		body.take_damage(info)
	elif body.has_method("receive_damage"):
		body.receive_damage(info)
