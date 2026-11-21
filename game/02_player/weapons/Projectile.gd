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
	# Ocultar inicialmente hasta que se configure
	visible = false

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
