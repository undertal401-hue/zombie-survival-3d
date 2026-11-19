extends Node
## Regresión conductual del Area2D de separación de zombis.
## Verifica detección local, descarte al alejarse y limpieza al morir,
## sin depender del estado "OK" de los arneses de presencia de API.

var _failures: Array[String] = []
var _main: Node

func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_main = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	for i in range(10):
		await get_tree().process_frame

	var zombies: Array = get_tree().get_nodes_in_group("zombies")
	_check(zombies.size() >= 2, "hay al menos 2 zombis vivos")
	if zombies.size() < 2:
		await _finish()
		return

	var a: Node2D = zombies[0] as Node2D
	var b: Node2D = zombies[1] as Node2D
	var spot: Vector2 = a.global_position
	a.global_position = spot
	b.global_position = spot + Vector2(12.0, 0.0)
	for i in range(6):
		await get_tree().physics_frame

	var na: Array = a.get("_separation_neighbors") as Array
	var nb: Array = b.get("_separation_neighbors") as Array
	_check(na != null and na.has(b), "A detecta a B como vecino cercano")
	_check(nb != null and nb.has(a), "B detecta a A como vecino cercano")

	b.global_position = spot + Vector2(400.0, 0.0)
	for i in range(6):
		await get_tree().physics_frame
	na = a.get("_separation_neighbors") as Array
	_check(na != null and not na.has(b), "A descarta a B al alejarse (> radio)")

	var area: Area2D = a.get("separation_area") as Area2D
	_check(area != null, "Zombie expone su SeparationArea")
	a.call("_die")
	_check((a.get("_separation_neighbors") as Array).is_empty(), "muerte limpia el conjunto de vecinos")
	_check(area != null and not area.monitoring, "muerte desactiva la monitorización")

	await _finish()


func _finish() -> void:
	if is_instance_valid(_main):
		if get_tree().current_scene == _main:
			get_tree().current_scene = null
		_main.queue_free()
		_main = null
	# Dar tiempo al árbol a liberar el mundo instanciado antes de salir,
	# evitando "ObjectDB instances were leaked at exit" en headless.
	for i in range(6):
		await get_tree().process_frame
	print("SEPARATION_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# La salida se programa ANTES de los assert: si uno falla en debug el
	# proceso ya tiene su codigo y el CI no puede dar verde aunque el arnes
	# se detenga. En release los asserts se compilan fuera y los _failures
	# de arriba siguen gobernando la salida.
	get_tree().quit(1 if not _failures.is_empty() else 0)
	for f in _failures:
		assert(false, "SEPARATION_TEST: " + f)
