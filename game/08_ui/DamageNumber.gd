extends Node2D
class_name DamageNumber

## Número de daño flotante (game feel, ÍTEM 8). Sube y se desvanece en ~0,7 s
## y se libera solo. No crea assets: usa la fuente por defecto de Godot.
## Máximo 8 simultáneos para no llenar la escena en ráfagas/escopeta.

const LIFETIME: float = 0.7
const RISE_PIXELS: float = 26.0
const MAX_SIMULTANEOUS: int = 8
const GROUP: StringName = &"damage_numbers"

@onready var label: Label = $Label

var _start_position: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	# Si hay una horda de números, retira los más antiguos (los primeros del
	# grupo) para mantener el límite de 8 sin necesidad de pool externo.
	var others: Array[Node] = get_tree().get_nodes_in_group(GROUP)
	var excess: int = others.size() - MAX_SIMULTANEOUS
	for i in range(maxi(excess, 0)):
		var oldest: Node = others[i]
		if oldest != self and is_instance_valid(oldest):
			oldest.queue_free()


## Llamar DESPUÉS de add_child() para que @onready esté resuelto.
func setup(amount: float, headshot: bool, world_position: Vector2) -> void:
	_start_position = world_position
	global_position = world_position
	if label == null:
		return
	label.text = str(int(round(amount))) + ("!" if headshot else "")
	label.modulate = Color(1.0, 0.82, 0.18, 1.0) if headshot \
		else Color(1.0, 0.96, 0.92, 1.0)


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / LIFETIME, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - t, 2.0)
	global_position = _start_position + Vector2.UP * RISE_PIXELS * eased
	if label != null:
		var tint: Color = label.modulate
		tint.a = 1.0 - t
		label.modulate = tint
	if t >= 1.0:
		queue_free()
