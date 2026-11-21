extends Sprite2D
class_name Projectile

## Proyectil VISUAL que viaja hacia un objetivo y se autodestruye al impactar
## o al alcanzar su rango máximo. El daño del arma se aplica por el hitscan de
## Player: este nodo no vuelve a aplicar daño al mundo.

## Velocidad del proyectil en pixeles por segundo
@export var speed: float = 600.0

## Payload observacional para consumidores de `impacted`. El daño real ya fue
## resuelto y aplicado por Player antes de crear este proyectil.
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

## Referencia al jugador que disparó (compatibilidad; el raycast ya se hizo)
var shooter_rid: RID = RID()

var _traveled: float = 0.0
var _invalid: bool = false


func _ready() -> void:
	# La escena trae un efecto pixel-art real (`bullet_sparks`). Si el asset no
	# existe, el nodo se libera: nunca queda un proyectil oculto permanente.
	if texture == null:
		_invalid = true
		visible = false
		queue_free()
		return
	visible = true


## Configura y arranca el vuelo en una sola transicion. `Player` la usa antes
## del primer frame para que origen, objetivo, alcance y daño sean coherentes.
func launch(to_target: Vector2, travel_range: float, shot_damage: float,
		shooter: RID = RID()) -> void:
	if texture == null:
		_invalid = true
		visible = false
		queue_free()
		return
	target = to_target
	max_range = maxf(travel_range, 1.0)
	damage = shot_damage
	shooter_rid = shooter
	start_pos = global_position
	_traveled = 0.0
	has_impacted = false
	visible = true


func _process(delta: float) -> void:
	if _invalid or has_impacted:
		return

	var to_target: Vector2 = target - global_position
	var remaining: float = to_target.length()
	if remaining <= 0.001:
		_impact()
		return

	# El desplazamiento se limita al tramo restante y al rango disponible: el
	# proyectil termina exactamente en el impacto, sin sobrepasarlo.
	var direction: Vector2 = to_target / remaining
	var available: float = maxf(max_range - _traveled, 0.0)
	if available <= 0.001:
		_impact()
		return
	var step_distance: float = minf(speed * delta, minf(remaining, available))
	global_position += direction * step_distance
	_traveled += step_distance

	var reached_target: bool = global_position.distance_to(target) <= 0.01
	var reached_range: bool = _traveled >= max_range - 0.01
	if reached_range and not reached_target:
		global_position = start_pos + direction * max_range
	if reached_target or reached_range:
		_impact()


func _impact() -> void:
	if has_impacted:
		return
	has_impacted = true

	# Señal observacional. El daño hitscan ya se aplicó exactamente una vez
	# en Player; ningún consumidor debe volver a aplicarlo desde aquí.
	impacted.emit(global_position, damage, surface_type)
	queue_free()


## Señal emitida cuando el proyectil impacta algo
signal impacted(hit_pos: Vector2, damage: float, surface_type: int)
