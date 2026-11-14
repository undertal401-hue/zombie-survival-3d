class_name ZombieStats

extends Resource
## Stats de un tipo de zombie (data-driven).
##
## Los valores base viven en `16_data/ZombieStats.tres`; el spawner aplica el
## escalado de oleada en tiempo de generacion.
## Accesible globalmente via `ZombieStats` (class_name).

enum ZombieKind {
	WALKER,
	RUNNER,
	TANK,
	SPITTER,
	CRAWLER,
	SCREAMER,
	BRUTE,
	MUTATED,
}

@export var kind: ZombieKind = ZombieKind.WALKER
@export var type_name: StringName = &"walker"
@export var display_name: String = "Walker"
@export var max_hp: float = 60.0
@export var current_hp: float = 60.0
@export var damage: float = 10.0
@export var speed: float = 2.2
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.1
@export var coin_reward: int = 5
@export var infection_on_hit: float = 8.0
@export var knockback_multiplier: float = 1.0
@export var headshot_multiplier: float = 2.0
@export var scale: Vector3 = Vector3.ONE
@export var is_boss: bool = false
@export var is_flying: bool = false
@export var can_spit: bool = false
@export var can_scream: bool = false
@export var xp_value: int = 1


## Escala las stats base por oleada.
## @param hp_mult: multiplicador de vida.
## @param dmg_mult: multiplicador de dano.
## @param speed_mult: multiplicador de velocidad.
## @return copia escalada (el original no se muta).
func scaled(hp_mult: float, dmg_mult: float, speed_mult: float) -> ZombieStats:
	var copy: ZombieStats = duplicate() as ZombieStats
	copy.max_hp = maxf(max_hp * hp_mult, 1.0)
	copy.current_hp = copy.max_hp
	copy.damage = maxf(damage * dmg_mult, 1.0)
	copy.speed = maxf(speed * speed_mult, 0.5)
	return copy


## Tabla de stats base de los 8 tipos requeridos.
static func base_table() -> Dictionary:
	var table := {}
	table[ZombieKind.WALKER] = _make(ZombieKind.WALKER, &"walker", "Caminante", 60, 10, 2.2, 8.0, 1.0)
	table[ZombieKind.RUNNER] = _make(ZombieKind.RUNNER, &"runner", "Corredor", 45, 8, 4.4, 6.0, 0.7)
	table[ZombieKind.TANK] = _make(ZombieKind.TANK, &"tank", "Tanque", 220, 18, 1.6, 14.0, 2.4)
	table[ZombieKind.SPITTER] = _make(ZombieKind.SPITTER, &"spitter", "Escupidor", 70, 12, 2.0, 10.0, 1.0)
	table[ZombieKind.CRAWLER] = _make(ZombieKind.CRAWLER, &"crawler", "Rastrero", 40, 8, 3.0, 6.0, 0.6)
	table[ZombieKind.SCREAMER] = _make(ZombieKind.SCREAMER, &"screamer", "Griton", 55, 6, 2.8, 5.0, 0.8)
	table[ZombieKind.BRUTE] = _make(ZombieKind.BRUTE, &"brute", "Bruto", 180, 22, 2.0, 16.0, 2.0)
	table[ZombieKind.MUTATED] = _make(ZombieKind.MUTATED, &"mutated", "Mutado", 600, 30, 2.6, 25.0, 3.0)
	var mutated: ZombieStats = table[ZombieKind.MUTATED]
	mutated.is_boss = true
	mutated.can_scream = true
	var spitter: ZombieStats = table[ZombieKind.SPITTER]
	spitter.can_spit = true
	var screamer: ZombieStats = table[ZombieKind.SCREAMER]
	screamer.can_scream = true
	return table


static func _make(kind: ZombieKind, type_name: StringName, display: String,
		hp: float, dmg: float, speed: float, infection: float,
		knockback: float) -> ZombieStats:
	var stats := ZombieStats.new()
	stats.kind = kind
	stats.type_name = type_name
	stats.display_name = display
	stats.max_hp = hp
	stats.damage = dmg
	stats.speed = speed
	stats.infection_on_hit = infection
	stats.knockback_multiplier = knockback
	stats.coin_reward = Config.zombie_base_coins
	return stats
