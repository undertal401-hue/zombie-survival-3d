class_name ExplosionSystem


extends Node
## Servicio de explosiones: dano radial, knockback, VFX y shake de camara.
##
## Configurado por datos (radio, dano, infeccion opcional). Todas las
## explosiones del juego pasan por aqui.
## Accesible globalmente via \`ExplosionSystem\` (class_name).

@export var default_radius: float = 4.0
@export var default_damage: float = 80.0
@export var default_knockback: float = 12.0
@export var friendly_fire: bool = false

var damage_system: DamageSystem
var knockback_system: KnockbackSystem


func _ready() -> void:
	add_to_group("explosion_system")
	damage_system = get_node_or_null("DamageSystem") as DamageSystem
	if damage_system == null:
		damage_system = DamageSystem.new()
		damage_system.name = "DamageSystem"
		add_child(damage_system)
	knockback_system = get_node_or_null("KnockbackSystem") as KnockbackSystem
	if knockback_system == null:
		knockback_system = KnockbackSystem.new()
		knockback_system.name = "KnockbackSystem"
		add_child(knockback_system)


## Detona una explosion completa.
## @param origin: centro de la explosion.
## @param radius: radio de dano.
## @param damage: dano en el centro.
## @param source: nodo que la provoca.
## @return diccionario con afectados y dano total.
func detonate(origin: Vector3, radius: float, damage: float, source: Node3D) -> Dictionary:
	var result := {"affected": 0, "total_damage": 0.0, "knockback": 0}
	if damage_system != null:
		result["affected"] = damage_system.apply_radial(origin, radius, damage, source)
	if knockback_system != null:
		result["knockback"] = knockback_system.apply_radial(origin, radius, default_knockback)
	EventBus.explosion_triggered.emit(origin, radius, damage)
	EventBus.sfx_requested.emit(&"explosion_large", origin)
	if GameManager.is_playing():
		_spawn_vfx(origin, radius)
	return result


## VFX de explosion: particula + luz rapida.
func _spawn_vfx(origin: Vector3, radius: float) -> void:
	var scene: PackedScene = load("res://10_effects/ExplosionVFX.tscn") as PackedScene
	if scene == null:
		return
	var fx: Node3D = scene.instantiate() as Node3D
	get_tree().current_scene.add_child(fx)
	fx.global_position = origin
	if fx.has_method("configure"):
		fx.configure(radius)
		if fx.has_method("play"):
			fx.play()
