extends Sprite2D
class_name Projectile

## Proyectoil visual que viaja hacia un objetivo y se autodestruye al impactar
## o al alcanzar su rango máximo.

## Velocidad del proyectil en pixeles por segundo
@export var speed: float = 600.0

## Daño que inflige al impactar (usado para efectos visuales)
@export var damage: float = 0.0

## Tipo de superficie para efectos de impacto
@export var surface_type: int = 0

## Objetivo del proyectil (posición mundial)
var target: Vector2 = Vector2.ZERO

## Distancia máxima que puede viajar el proyectil
var max_range: float = 0.0

## Posición de origen
var start_pos: Vector2 = Vector2.ZERO

## Si el proyectil ya impactó (evita procesar dos veces)
var has_impacted: bool = false

## Referencia al jugador que disparó (para excluir del raycast)
var shooter_rid: RID = RID()

func _ready() -> void:
	# La escena trae un efecto pixel-art real (`bullet_sparks`). El proyectil
	# solo se oculta si ese asset no se pudo cargar; nunca nace invisible.
	visible = texture != null


## Configura y arranca el vuelo en una sola transicion. `Player` la usa antes
## del primer frame para que origen, objetivo, alcance y daño sean coherentes.
func launch(to_target: Vector2, travel_range: float, shot_damage: float,
		shooter: RID = RID()) -> void:
	target = to_target
	max_range = maxf(travel_range, 1.0)
	damage = shot_damage
	shooter_rid = shooter
	start_pos = global_position
	visible = texture != null


func _process(delta: float) -> void:
	if not visible:
		return

	# Mover el proyectil hacia el objetivo
	var direction: Vector2 = (target - global_position).normalized()
	if direction.length() < 0.001:
		direction = Vector2(1, 0)

	var step: Vector2 = direction * speed * delta
	global_position += step

	# Verificar si alcanzó el objetivo o el rango máximo
	var dist_to_target: float = global_position.distance_to(target)
	var dist_traveled: float = global_position.distance_to(start_pos)

	if dist_to_target < speed * delta * 2.0 or dist_traveled >= max_range:
		_impact()

func _impact() -> void:
	if has_impacted:
		return
	has_impacted = true

	# Emitir señal de impacto para que el jugador procese el daño
	impacted.emit(global_position, damage, surface_type)

	# Destruir el proyectil
	queue_free()

## Señal emitida cuando el proyectil impacta algo
signal impacted(hit_pos: Vector2, damage: float, surface_type: int)
