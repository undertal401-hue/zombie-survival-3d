extends Node
## ============================================================================
## OPEN SETTLEMENT TEST — pueblos transitables a pie.
## ============================================================================
## El punto 8 exige entrar caminando a los pueblos, sin barricada fisica, sin
## cartel CERRADO y sin teletransporte. Esta puerta construye el barrio real
## y comprueba que el asentamiento principal ya no conserva la barricada,
## que los pueblos secundarios siguen presentes y que ningun cartel anuncia
## un acceso cerrado.
## ============================================================================

const NEIGHBORHOOD_SCENE: PackedScene = preload("res://05_house/Neighborhood.tscn")

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	var neighborhood: Node2D = NEIGHBORHOOD_SCENE.instantiate() as Node2D
	add_child(neighborhood)
	await get_tree().process_frame

	var barricades: Array[Node] = []
	var closed_labels: Array[Label] = []
	var town_labels: Array[Label] = []
	var town_houses: Array[Node] = []
	_collect_access_nodes(neighborhood, barricades, closed_labels, town_labels, town_houses)

	_check(barricades.is_empty(),
		"El asentamiento principal no conserva ninguna barricada fisica")
	_check(closed_labels.is_empty(),
		"Ningun pueblo muestra un cartel CERRADO")
	_check(town_labels.size() >= 3,
		"Se generan al menos tres pueblos secundarios identificados")
	_check(town_houses.size() >= 9,
		"Cada pueblo secundario conserva casas transitables")

	await _finish()


func _collect_access_nodes(node: Node, barricades: Array[Node],
		closed_labels: Array[Label], town_labels: Array[Label],
		town_houses: Array[Node]) -> void:
	var normalized_name: String = String(node.name).to_upper()
	if normalized_name == "BARRICADE" or normalized_name.contains("CERRADO"):
		barricades.append(node)
	if node is Label:
		var label := node as Label
		if label.text.to_upper().contains("CERRADO"):
			closed_labels.append(label)
		if label.text.begins_with("Pueblo "):
			town_labels.append(label)
	if String(node.name).begins_with("Town_"):
		town_houses.append(node)
	for child in node.get_children():
		_collect_access_nodes(child, barricades, closed_labels, town_labels, town_houses)


func _finish() -> void:
	print("OPEN_SETTLEMENT_TEST failures=%d" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
