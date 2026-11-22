extends Node
## Regresión del arsenal: los .tres base se cargan como Weapon, el loadout
## conserva una ranura para la mejora meta, la munición se consume de verdad
## y el save/load round-tripa.

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

	var player: Node = _main.get_node("Player")
	var wc: WeaponController = player.get_node("WeaponController") as WeaponController
	_check(wc != null, "WeaponController presente")
	if wc == null:
		await _finish()
		return

	_check(wc.weapons.size() == 5, "loadout de 5 ranuras")
	_check(wc.get_weapon_in_slot(0) != null and wc.get_weapon_in_slot(0).category == Weapon.Category.TOOL,
		"slot 0 = hacha (TOOL)")
	_check(wc.get_weapon_in_slot(1) != null and wc.get_weapon_in_slot(1).ammo_type == "pistol_ammo",
		"slot 1 = pistola 9mm")
	var shotgun: Weapon = wc.get_weapon_in_slot(2)
	var rifle: Weapon = wc.get_weapon_in_slot(3)
	_check(shotgun != null and shotgun.ammo_type == "shotgun_ammo" and shotgun.pellets_per_shot == 8,
		"slot 2 = escopeta con 8 perdigones")
	_check(rifle != null and rifle.ammo_type == "rifle_ammo" and rifle.burst_count == 3,
		"slot 3 = fusil con ráfaga de 3")
	var axe: Weapon = wc.get_weapon_in_slot(0)
	_check(axe != null and axe.weapon_name == "Hacha" and int(axe.category) == 7,
		"slot 0 = hacha (TOOL)")
	_check(wc.get_weapon_in_slot(4) == null, "slot 4 libre para la mejora meta")

	wc.call("_equip_slot", 2)
	_check(wc.current_weapon == shotgun, "equipar escopeta por ranura")
	wc.call("_equip_slot", 3)
	_check(wc.current_weapon == rifle, "equipar fusil por ranura")

	# Recarga real del fusil: consume del inventario y llena el cargador.
	# El contrato se deriva de magazine_size para seguir la capacidad vigente
	# (60 cartuchos desde FASE1-P1) sin volver a codificarla en el test.
	Inventory.add_item("rifle_ammo", rifle.magazine_size)
	var before: int = Inventory.count("rifle_ammo")
	rifle.current_ammo = 2
	rifle.ammo_in_chamber = 0
	wc.call("_start_reload")
	_check(rifle.is_reloading, "recarga de fusil iniciada")
	for i in range(10):
		rifle.update_reload(0.5)
	_check(not rifle.is_reloading and rifle.get_total_ammo() == rifle.magazine_size,
		"fusil recargado a capacidad completa")
	var expected_consumed: int = rifle.magazine_size - 2
	_check(Inventory.count("rifle_ammo") == before - expected_consumed,
		"recarga consumió %d cartuchos del inventario" % expected_consumed)

	# Escopeta cartucho a cartucho: cada actualizacióninserta uno.
	Inventory.add_item("shotgun_ammo", 3)
	var shells_before: int = Inventory.count("shotgun_ammo")
	shotgun.current_ammo = 0
	shotgun.ammo_in_chamber = 0
	wc.call("_equip_slot", 2)
	wc.call("_start_reload")
	for i in range(4):
		shotgun.update_reload(0.5)
	_check(shotgun.get_total_ammo() == 3, "escopeta: 3 cartuchos insertados uno a uno")
	_check(Inventory.count("shotgun_ammo") == shells_before - 3,
		"escopeta: 3 cartuchos descontados del inventario")

	# Save/load con resource_path real (antes load("") devolvía null).
	var data: Dictionary = wc.get_save_data()
	wc.load_save_data(data)
	_check(wc.get_weapon_in_slot(2) != null and wc.get_weapon_in_slot(2).weapon_name == "Escopeta 12ga",
		"save/load restaura armas por resource_path")
	_check(wc.get_weapon_in_slot(0) != null and wc.get_weapon_in_slot(0).weapon_name == "Hacha",
		"save/load conserva el hacha")
	await _finish()

func _finish() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
		_main = null
	# Dar tiempo al árbol a liberar el mundo instanciado antes de salir,
	# evitando "ObjectDB instances were leaked at exit" en headless.
	for i in range(3):
		await get_tree().process_frame
	print("ARSENAL_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# La salida se programa ANTES de los assert: si uno falla en debug el
	# proceso ya tiene su codigo y el CI no puede dar verde aunque el arnes
	# se detenga. En release los asserts se compilan fuera y los _failures
	# de arriba siguen gobernando la salida.
	get_tree().quit(1 if not _failures.is_empty() else 0)
	for f in _failures:
		assert(false, "ARSENAL_TEST: " + f)
