extends RefCounted
## Validacion de escenas requeridas: nodos, colisiones, scripts, autoloads.

var passed: int = 0
var failed: int = 0


func _run_test(name: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % name)
	else:
		failed += 1
		printerr("[FAIL] %s" % name)


func test_project_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load("res://project.godot")
	_run_test("project_load", err == OK)
	if err != OK:
		return
	var autoloads: Dictionary = _section_dict(config, "autoload")
	_run_test("has_eventbus", _has_autoload(autoloads, "EventBus"))
	_run_test("has_config", _has_autoload(autoloads, "Config"))
	_run_test("has_gameclock", _has_autoload(autoloads, "GameClock"))
	_run_test("has_savesystem", _has_autoload(autoloads, "SaveSystem"))
	_run_test("has_audiomanager", _has_autoload(autoloads, "AudioManager"))
	_run_test("has_wavemanager", _has_autoload(autoloads, "WaveManager"))
	_run_test("has_gamemanager", _has_autoload(autoloads, "GameManager"))
	_run_test("has_debugconsole", _has_autoload(autoloads, "DebugConsole"))


## Devuelve todas las claves/valores de una seccion como Dictionary.
func _section_dict(config: ConfigFile, section: String) -> Dictionary:
	var result: Dictionary = {}
	if not config.has_section(section):
		return result
	for key: String in config.get_section_keys(section):
		result[key] = config.get_value(section, key)
	return result


func _has_autoload(autoloads: Dictionary, name: String) -> bool:
	return autoloads.has(name) and not str(autoloads[name]).is_empty()


func test_main_scene_exists() -> void:
	var config := ConfigFile.new()
	var err := config.load("res://project.godot")
	_run_test("project_reload", err == OK)
	if err != OK:
		return
	var main_scene: String = str(config.get_value("application", "run/main_scene", ""))
	_run_test("main_scene_set", not main_scene.is_empty())
	_run_test("main_scene_exists", ResourceLoader.exists(main_scene))


func test_required_scenes() -> void:
	var scenes := [
		"res://03_zombies/WalkerZombie.tscn",
		"res://03_zombies/RunnerZombie.tscn",
		"res://03_zombies/TankZombie.tscn",
		"res://03_zombies/SpitterZombie.tscn",
		"res://03_zombies/CrawlerZombie.tscn",
		"res://03_zombies/ScreamerZombie.tscn",
		"res://03_zombies/BruteZombie.tscn",
		"res://03_zombies/MutatedZombie.tscn",
		"res://04_weapons/Pistol.tscn",
		"res://04_weapons/Shotgun.tscn",
		"res://07_house/Room.tscn",
		"res://07_house/Corridor.tscn",
		"res://07_house/Bathroom.tscn",
		"res://10_effects/BloodPool.tscn",
		"res://10_effects/MuzzleFlash.tscn",
		"res://10_effects/HitImpact.tscn",
		"res://11_items/CoinPickup.tscn",
	]
	for scene: String in scenes:
		_run_test("scene_exists: %s" % scene, ResourceLoader.exists(scene))


func test_required_scripts() -> void:
	var scripts := [
		"res://01_core/EventBus.gd",
		"res://01_core/Config.gd",
		"res://01_core/GameManager.gd",
		"res://01_core/GameClock.gd",
		"res://01_core/ObjectPool.gd",
		"res://02_player/Player.gd",
		"res://02_player/PlayerStats.gd",
		"res://02_player/Inventory.gd",
		"res://02_player/InputHandler.gd",
		"res://02_player/PlayerController.gd",
		"res://02_player/PlayerCamera.gd",
		"res://02_player/InteractionComponent.gd",
		"res://03_zombies/BaseZombie.gd",
		"res://03_zombies/ZombieAI.gd",
		"res://03_zombies/ZombieSpawner.gd",
		"res://04_weapons/BaseWeapon.gd",
		"res://04_weapons/WeaponData.gd",
		"res://04_weapons/RangedWeapon.gd",
		"res://04_weapons/MeleeWeapon.gd",
		"res://05_combat/DamageInfo.gd",
		"res://05_combat/DamageSystem.gd",
		"res://05_combat/BloodSystem.gd",
		"res://05_combat/KnockbackSystem.gd",
		"res://06_waves/WaveManager.gd",
		"res://06_waves/WaveTimer.gd",
		"res://07_house/HouseGenerator.gd",
		"res://08_ui/HUD.gd",
		"res://09_audio/AudioManager.gd",
		"res://11_items/ItemBase.gd",
		"res://12_economy/Currency.gd",
		"res://12_economy/Shop.gd",
		"res://13_save/SaveSystem.gd",
		"res://14_debug/DebugConsole.gd",
		"res://14_debug/SceneValidator.gd",
	]
	for script: String in scripts:
		_run_test("script_exists: %s" % script, ResourceLoader.exists(script))


func test_data_resources() -> void:
	var resources := [
		"res://16_data/GameBalance.tres",
		"res://16_data/WaveScaling.tres",
		"res://16_data/ZombieStats.tres",
		"res://16_data/PriceTable.tres",
		"res://16_data/RarityTable.tres",
		"res://16_data/HouseLayout.tres",
		"res://16_data/Localization.csv",
	]
	for res: String in resources:
		_run_test("resource_exists: %s" % res, ResourceLoader.exists(res))


func test_physics_layers() -> void:
	var config := ConfigFile.new()
	var err := config.load("res://project.godot")
	_run_test("physics_config_load", err == OK)
	if err != OK:
		return
	var layer_names: Dictionary = _section_dict(config, "layer_names")
	_run_test("layer_player", layer_names.has("3d_physics/layer_1"))
	_run_test("layer_zombie", layer_names.has("3d_physics/layer_2"))
	_run_test("layer_bullet", layer_names.has("3d_physics/layer_3"))
	_run_test("layer_env", layer_names.has("3d_physics/layer_4"))
	_run_test("layer_pickup", layer_names.has("3d_physics/layer_5"))


func test_input_map() -> void:
	var config := ConfigFile.new()
	var err := config.load("res://project.godot")
	_run_test("input_config_load", err == OK)
	if err != OK:
		return
	var input_map: Dictionary = _section_dict(config, "input")
	var required_actions := [
		"move_forward", "move_back", "move_left", "move_right",
		"sprint", "jump", "dodge", "fire", "aim", "reload",
		"interact", "melee", "pause", "inventory", "shop",
	]
	for action: String in required_actions:
		_run_test("input_action: %s" % action, input_map.has(action))


func run() -> int:
	test_project_settings()
	test_main_scene_exists()
	test_required_scenes()
	test_required_scripts()
	test_data_resources()
	test_physics_layers()
	test_input_map()
	print("\n=== SCENE VALIDATION: %d passed, %d failed ===" % [passed, failed])
	return failed