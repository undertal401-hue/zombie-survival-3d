extends Node
## Wrapper autoload para PermanentUpgrade.

func new_upgrade(kind: StringName, amount: float) -> Object:
	var PermanentUpgrade = load("res://11_items/PermanentUpgrade.gd")
	var upg = PermanentUpgrade.new()
	upg.kind = kind
	upg.amount = amount
	return upg

func kind_label(kind: StringName) -> String:
	match kind:
		&"damage": return "Dano +%.0f%%" % (0.05 * 100.0)
		&"speed": return "Velocidad +%.0f%%" % (0.03 * 100.0)
		&"jump": return "Salto +%.0f%%" % (0.10 * 100.0)
	return "Mejora desconocida"
