extends Node
## Regresión de Fase 3: dificultad unificada, perfiles tácticos por arquetipo,
## botín por riesgo y composición escalonada de hordas.

var _failures: Array[String] = []

func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)

func _ready() -> void:
	await get_tree().process_frame
	var main: Node = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for i in range(10):
		await get_tree().process_frame

	# --- Unificación de dificultad ---
	var previous: float = GameState.difficulty()
	GameState.set_difficulty(0.0)
	_check(is_equal_approx(GameState.multiplier(&"horde"), 1.0), "horda x1.0 al inicio")
	_check(is_equal_approx(GameState.multiplier(&"zombie", &"damage"), 1.0), "daño zombi x1.0 al inicio")
	GameState.set_difficulty(1.0)
	_check(is_equal_approx(GameState.multiplier(&"horde"), 1.8), "horda x1.8 al máximo")
	_check(is_equal_approx(GameState.multiplier(&"zombie", &"damage"), 1.45), "daño zombi x1.45 al máximo")
	GameState.set_difficulty(previous)

	# --- Perfiles tácticos por arquetipo ---
	var scene: PackedScene = load("res://03_zombies/Zombie.tscn") as PackedScene
	var flank: Array = []
	var separation: Array = []
	var preferred: Array = []
	for kind_index in range(5):
		var z: Node2D = scene.instantiate() as Node2D
		get_tree().root.add_child(z)
		z.set("kind", kind_index)
		z.call("_apply_kind")
		flank.append(float(z.get("flank_strength")))
		separation.append(float(z.get("separation_scale")))
		preferred.append(float(z.get("preferred_range")))
		z.queue_free()

	_check(is_equal_approx(flank[0], 0.18) and is_equal_approx(flank[1], 0.42),
		"caminante/corredor flanquean distinto")
	_check(separation[2] > 1.5, "tanque empuja más en la separación")
	_check(preferred[3] >= 200.0 and preferred[4] == 0.0,
		"escupidor mantiene distancia; gritón no")

	# --- Botín por riesgo (flujo 'loot' determinista) ---
	var tank: Node2D = scene.instantiate() as Node2D
	get_tree().root.add_child(tank)
	tank.set("kind", 2)
	tank.call("_apply_kind")
	var scrap_before: int = Inventory.count("scrap")
	tank.call("_drop_loot")
	_check(Inventory.count("scrap") >= scrap_before + 2, "tanque suelta 2-3 chatarra")
	tank.queue_free()

	# --- Composición de hordas ---
	var director: Node = main.get_node_or_null("WaveManager")
	_check(director != null, "WaveManager presente")
	if director != null:
		director.set("_horde_wave", 1)
		var early_only: bool = true
		for i in range(10):
			var k: int = int(director.call("_horde_kind_for", i))
			if k != 0 and k != 1:
				early_only = false
		_check(early_only, "oleada 1: solo caminantes/corredores")

		director.set("_horde_wave", 4)
		var seen: Dictionary = {}
		for i in range(60):
			seen[int(director.call("_horde_kind_for", i))] = true
		_check(seen.has(2) and seen.has(3) and seen.has(4),
			"oleada 4 incluye tanque, escupidor y gritón")
	_finish()

func _finish() -> void:
	print("AI_WAVE_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# La salida se programa ANTES de los assert: si uno falla en debug el
	# proceso ya tiene su codigo y el CI no puede dar verde aunque el arnes
	# se detenga. En release los asserts se compilan fuera y los _failures
	# de arriba siguen gobernando la salida.
	get_tree().quit(1 if not _failures.is_empty() else 0)
	for f in _failures:
		assert(false, "AI_WAVE_TEST: " + f)
