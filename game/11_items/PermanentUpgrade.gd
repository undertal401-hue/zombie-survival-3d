class_name PermanentUpgrade

extends Resource
## Mejora permanente (drop raro 1-3%): dano +5%, velocidad +3%, salto +10%.
##
## Persiste en SaveSystem entre partidas. Se aplica sobre PlayerStats.
## Accesible globalmente via `PermanentUpgrade` (class_name).

enum UpgradeKind {
	NONE,
	DAMAGE,
	SPEED,
	JUMP,
	VITALITY,
	STAMINA,
}

@export var kind: StringName = &"damage"
@export var amount: float = 0.05
@export var display_name: String = "Mejora"
@export var description: String = ""
@export var rarity_id: StringName = &"rare"
@export var icon_path: String = ""


## Convierte el tipo a nombre de estadistica de PlayerStats.
func to_stats_key() -> StringName:
	match kind:
		&"damage": return &"damage"
		&"speed": return &"speed"
		&"jump": return &"jump"
	return &""


## Aplica la mejora sobre unas vitals.
## @param stats: PlayerStats objetivo.
func apply_to(stats: PlayerStats) -> void:
	if stats == null:
		return
	stats.apply_permanent_upgrade(kind, amount)


## Nombre legible del tipo.
static func kind_label(kind: StringName) -> String:
	match kind:
		&"damage": return "Dano +%.0f%%" % (0.05 * 100.0)
		&"speed": return "Velocidad +%.0f%%" % (0.03 * 100.0)
		&"jump": return "Salto +%.0f%%" % (0.10 * 100.0)
	return "Mejora desconocida"


## Serializa la mejora.
func to_dict() -> Dictionary:
	return {"kind": kind, "amount": amount, "rarity": rarity_id}
