class_name CriticalHit

extends RefCounted
## Utilidad de critico: probabilidad y multiplicador configurables.
##
## Clase estatica ligera para no arrastrar estado entre golpes.
## Accesible globalmente via `CriticalHit` (class_name).

static var chance: float = 0.05
## Multiplicador aplicado al dano critico.
static var multiplier: float = 1.75
## Semilla propia para tests deterministas.
static var rng_seed: int = 0
static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Inicializa la utilidad desde la configuracion global.
static func configure(cfg: GameConfig) -> void:
	chance = cfg.combat_crit_chance
	multiplier = cfg.combat_crit_multiplier


## Lanza el dado de critico.
## @return true si el golpe es critico.
static func roll() -> bool:
	return _rng.randf() < chance


## Precarga la semilla (tests y determinismo por partida).
## @param seed_value: semilla.
static func set_seed(seed_value: int) -> void:
	rng_seed = seed_value
	_rng.seed = seed_value


## Calcula el dano final tras critico.
## @param base_amount: dano base.
## @param force_critical: fuerza el critico (tests/cheats).
static func apply(base_amount: float, force_critical: bool = false) -> Dictionary:
	var is_crit: bool = force_critical or roll()
	return {
		"amount": base_amount * (multiplier if is_crit else 1.0),
		"is_critical": is_crit,
	}
