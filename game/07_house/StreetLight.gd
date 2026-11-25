extends PointLight2D
class_name StreetLight

## Farola de barrio: PointLight2D acotada con textura de cono.
## Se enciende/apaga según WorldDirector.night_factor().
## NO está en grupo nav_obstacles.

const MIN_NIGHT_FACTOR: float = 0.3  # Umbral para encender
const MAX_ENERGY: float = 1.8        # Energía máxima de noche
const SMOOTH_TAU: float = 2.0        # Suavizado encendido/apagado

@export var auto_control: bool = true  # Si false, control manual via set_enabled()

var _target_energy: float = 0.0
var _director: Node = null

func _ready() -> void:
	# NO añadirse a nav_obstacles
	_find_director()
	# Energía inicial según fase actual
	if _director != null and _director.has_method("night_factor"):
		_target_energy = _clamp_energy(_director.call("night_factor"))
		energy = _target_energy

func _process(delta: float) -> void:
	if not auto_control:
		return
	if _director == null or not is_instance_valid(_director):
		_find_director()
		return
	if not _director.has_method("night_factor"):
		return
	var nf: float = float(_director.call("night_factor"))
	_target_energy = _clamp_energy(nf)
	var k: float = 1.0 - exp(-delta / SMOOTH_TAU)
	energy = lerpf(energy, _target_energy, k)

func _find_director() -> void:
	var parent := get_parent()
	while parent != null:
		if parent.has_method("night_factor"):
			_director = parent
			return
		parent = parent.get_parent()
	# Fallback: buscar en árbol
	for candidate in get_tree().get_nodes_in_group("world_director"):
		if is_instance_valid(candidate) and candidate.has_method("night_factor"):
			_director = candidate
			return

func _clamp_energy(night_factor: float) -> float:
	if night_factor < MIN_NIGHT_FACTOR:
		return 0.0
	# Interpolación suave desde umbral hasta 1.0
	var t: float = clampf((night_factor - MIN_NIGHT_FACTOR) / (1.0 - MIN_NIGHT_FACTOR), 0.0, 1.0)
	# Curva suave: t^2 para encendido progresivo
	return MAX_ENERGY * t * t

## Control manual (para tests o gameplay especial)
func set_manual_enabled(enabled: bool) -> void:
	auto_control = false
	_target_energy = MAX_ENERGY if enabled else 0.0