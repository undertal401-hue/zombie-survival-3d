class_name PlayerStats

extends Resource
## Estadisticas vitales del jugador (componente de composicion).
##
## Contiene vida, stamina e infeccion. Emite senales que el HUD y los
## sistemas escuchan; nunca se consulta directamente desde otros sistemas.
## Accesible globalmente via `PlayerStats` (class_name).

signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal infection_changed(current: float, maximum: float)
signal health_depleted
signal infection_maxed
signal stamina_depleted

var max_hp: float = 100.0:
	set(value):
		max_hp = maxf(value, 1.0)
		health_changed.emit(hp, max_hp)
var hp: float = 100.0:
	set(value):
		hp = clampf(value, 0.0, max_hp)
		health_changed.emit(hp, max_hp)
		if hp <= 0.0:
			health_depleted.emit()
var max_stamina: float = 100.0:
	set(value):
		max_stamina = maxf(value, 1.0)
		stamina_changed.emit(stamina, max_stamina)
var stamina: float = 100.0:
	set(value):
		var previous: float = stamina
		stamina = clampf(value, 0.0, max_stamina)
		stamina_changed.emit(stamina, max_stamina)
		if stamina <= 0.0 and previous > 0.0:
			stamina_depleted.emit()
var infection: float = 0.0:
	set(value):
		var previous: float = infection
		infection = clampf(value, 0.0, max_infection)
		infection_changed.emit(infection, max_infection)
		if infection >= max_infection and previous < max_infection:
			infection_maxed.emit()
var max_infection: float = 100.0
var move_speed: float = 5.0
var sprint_speed: float = 8.2
var crouch_speed: float = 2.4
var jump_velocity: float = 5.5
var dodge_speed: float = 12.0
var dodge_duration: float = 0.28
var hp_regen_rate: float = 2.0
var hp_regen_delay: float = 5.0
var stamina_regen: float = 15.0
var stamina_sprint_drain: float = 12.0
var infection_damage_ratio: float = 0.6
var infection_game_over_at: float = 100.0
var infection_cure_amount: float = 25.0
var permanent_damage_mult: float = 1.0
var permanent_speed_mult: float = 1.0
var permanent_jump_mult: float = 1.0
var coins: int = 0

var _time_since_damage: float = 0.0


## Configura las vitals desde el recurso global de configuracion.
## @param cfg: GameConfig con los valores base.
func configure(cfg: GameConfig) -> void:
	max_hp = cfg.player_max_hp
	hp = cfg.player_max_hp
	max_stamina = cfg.player_stamina_max
	stamina = cfg.player_stamina_max
	max_infection = cfg.player_infection_max
	infection = 0.0
	move_speed = cfg.player_move_speed
	sprint_speed = cfg.player_sprint_speed
	crouch_speed = cfg.player_crouch_speed
	jump_velocity = cfg.player_jump_velocity
	dodge_speed = cfg.player_dodge_speed
	dodge_duration = cfg.player_dodge_duration
	hp_regen_rate = cfg.player_hp_regen_rate
	hp_regen_delay = cfg.player_hp_regen_delay
	stamina_regen = cfg.player_stamina_regen
	stamina_sprint_drain = cfg.player_stamina_sprint_drain
	infection_damage_ratio = cfg.infection_damage_ratio
	infection_game_over_at = cfg.infection_game_over_at
	infection_cure_amount = cfg.infection_cure_amount


## Aplica dano fisico y actualiza el reloj de regeneracion.
## @param amount: dano entrante ya calculado.
## @return dano realmente aplicado.
func receive_damage(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	hp -= amount * permanent_damage_mult
	_time_since_damage = 0.0
	return amount


## Cura vida sin pasarse del maximo.
func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	hp = minf(hp + amount, max_hp)
	_time_since_damage = 0.0


## Suma infeccion. Al llegar al maximo emite `infection_maxed`.
func add_infection(amount: float) -> void:
	if amount <= 0.0:
		return
	infection += amount


## Reduce la infeccion (curacion de baño / pocion).
## @return cantidad realmente curada.
func cure_infection(amount: float) -> float:
	var applied: float = minf(amount, infection)
	infection -= applied
	return applied


## Consume stamina si hay suficiente.
## @return true si se pudo consumir.
func try_consume_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	return true


## Regeneracion por frame (vida fuera de combate, stamina siempre).
## @param delta: tiempo escalado.
## @param in_combat: si el jugador esta en combate (bloquea regen de vida).
func regenerate(delta: float, in_combat: bool) -> void:
	stamina = minf(stamina + stamina_regen * delta, max_stamina)
	if in_combat:
		_time_since_damage = 0.0
		return
	_time_since_damage += delta
	if _time_since_damage >= hp_regen_delay and hp < max_hp:
		hp = minf(hp + hp_regen_rate * delta, max_hp)


## Aplica una mejora permanente.
## @param kind: "damage" | "speed" | "jump".
## @param amount: incremento multiplicativo (0.05 = +5%).
func apply_permanent_upgrade(kind: StringName, amount: float) -> void:
	match kind:
		&"damage":
			permanent_damage_mult += amount
		&"speed":
			permanent_speed_mult += amount
			move_speed *= 1.0 + amount
			sprint_speed *= 1.0 + amount
		&"jump":
			permanent_jump_mult += amount
			jump_velocity *= 1.0 + amount


## Serializa las vitals para guardado.
func to_dict() -> Dictionary:
	return {
		"max_hp": max_hp, "hp": hp, "max_stamina": max_stamina,
		"stamina": stamina, "infection": infection, "coins": coins,
		"damage_mult": permanent_damage_mult, "speed_mult": permanent_speed_mult,
		"jump_mult": permanent_jump_mult,
	}


## Restaura vitals desde un diccionario de guardado.
func from_dict(data: Dictionary) -> void:
	var property_map: Dictionary = {
		"max_hp": "max_hp",
		"hp": "hp",
		"max_stamina": "max_stamina",
		"stamina": "stamina",
		"infection": "infection",
		"coins": "coins",
		"damage_mult": "permanent_damage_mult",
		"speed_mult": "permanent_speed_mult",
		"jump_mult": "permanent_jump_mult",
	}
	for key: String in property_map:
		if data.has(key):
			set(property_map[key], data[key])
