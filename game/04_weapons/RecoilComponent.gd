class_name RecoilComponent


extends Node
## Componente de retroceso: pitch/kick y dispersion Bloom.
##
## Se acumula al disparar y decae con el tiempo. La camara lee `kick_pitch`.
## Accesible globalmente via `RecoilComponent` (class_name).

const RECOIL_DECAY: float = 8.0
const MAX_PITCH: float = 0.35

var kick_pitch: float = 0.0
var bloom: float = 0.0
var base_spread: float = 1.0
var recoil_amount: float = 0.6


## Configura el componente.
## @param p_base_spread: dispersion base del arma.
## @param p_recoil: fuerza de retroceso.
func configure(p_base_spread: float, p_recoil: float) -> void:
	base_spread = p_base_spread
	recoil_amount = p_recoil


func _process(delta: float) -> void:
	kick_pitch = move_toward(kick_pitch, 0.0, RECOIL_DECAY * delta)
	bloom = move_toward(bloom, 0.0, RECOIL_DECAY * 1.5 * delta)


## Aplica un golpe de retroceso.
func add_shot() -> void:
	kick_pitch = clampf(kick_pitch + recoil_amount * 0.12, 0.0, MAX_PITCH)
	bloom = clampf(bloom + recoil_amount * 0.5, 0.0, 1.0)


## Dispersion actual incluyendo bloom.
func current_spread(ads: bool) -> float:
	var spread: float = base_spread * (1.0 + bloom * 2.0)
	return spread * (0.4 if ads else 1.0)
