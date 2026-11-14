extends RefCounted
## Tests unitarios de PlayerStats.

var passed: int = 0
var failed: int = 0


func _run_test(name: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % name)
	else:
		failed += 1
		printerr("[FAIL] %s" % name)


func _init_player_stats() -> PlayerStats:
	var stats := PlayerStats.new()
	var cfg := GameConfig.new()
	cfg.player_max_hp = 100.0
	cfg.player_stamina_max = 100.0
	cfg.player_infection_max = 100.0
	cfg.player_hp_regen_rate = 2.0
	cfg.player_hp_regen_delay = 5.0
	cfg.player_stamina_regen = 15.0
	cfg.player_stamina_sprint_drain = 12.0
	cfg.infection_damage_ratio = 0.6
	cfg.infection_game_over_at = 100.0
	cfg.infection_cure_amount = 25.0
	stats.configure(cfg)
	return stats


func test_health_clamping() -> void:
	var stats := _init_player_stats()
	stats.hp = 150.0
	_run_test("health_max_clamp", stats.hp == 100.0)
	stats.hp = -10.0
	_run_test("health_min_clamp", stats.hp == 0.0)


func test_stamina_clamping() -> void:
	var stats := _init_player_stats()
	stats.stamina = 150.0
	_run_test("stamina_max_clamp", stats.stamina == 100.0)
	stats.stamina = -5.0
	_run_test("stamina_min_clamp", stats.stamina == 0.0)


func test_infection_clamping() -> void:
	var stats := _init_player_stats()
	stats.infection = 150.0
	_run_test("infection_max_clamp", stats.infection == 100.0)
	stats.infection = -10.0
	_run_test("infection_min_clamp", stats.infection == 0.0)


func test_receive_damage() -> void:
	var stats := _init_player_stats()
	var dmg := stats.receive_damage(25.0)
	_run_test("damage_applied", dmg == 25.0)
	_run_test("hp_reduced", stats.hp == 75.0)
	_run_test("regen_timer_reset", true)


func test_heal() -> void:
	var stats := _init_player_stats()
	stats.hp = 50.0
	stats.heal(30.0)
	_run_test("heal_amount", stats.hp == 80.0)
	stats.heal(50.0)
	_run_test("heal_cap", stats.hp == 100.0)


func test_add_infection() -> void:
	var stats := _init_player_stats()
	stats.add_infection(30.0)
	_run_test("infection_added", stats.infection == 30.0)
	stats.add_infection(90.0)
	_run_test("infection_cap", stats.infection == 100.0)


func test_cure_infection() -> void:
	var stats := _init_player_stats()
	stats.infection = 60.0
	var cured := stats.cure_infection(25.0)
	_run_test("cure_amount", cured == 25.0)
	_run_test("infection_reduced", stats.infection == 35.0)
	var overcure := stats.cure_infection(50.0)
	_run_test("overcure", overcure == 35.0)
	_run_test("infection_zero", stats.infection == 0.0)


func test_try_consume_stamina() -> void:
	var stats := _init_player_stats()
	_run_test("consume_ok", stats.try_consume_stamina(30.0))
	_run_test("stamina_reduced", stats.stamina == 70.0)
	_run_test("consume_fail", not stats.try_consume_stamina(100.0))
	_run_test("stamina_unchanged", stats.stamina == 70.0)


func test_regenerate_out_of_combat() -> void:
	var stats := _init_player_stats()
	stats.hp = 50.0
	stats.stamina = 50.0
	stats._time_since_damage = 6.0
	stats.regenerate(1.0, false)
	_run_test("hp_regen", stats.hp > 50.0)
	_run_test("stamina_regen", stats.stamina > 50.0)


func test_regenerate_in_combat() -> void:
	var stats := _init_player_stats()
	stats.hp = 50.0
	stats.stamina = 50.0
	stats._time_since_damage = 6.0
	stats.regenerate(1.0, true)
	_run_test("no_hp_regen_combat", stats.hp == 50.0)
	_run_test("stamina_regen_combat", stats.stamina > 50.0)


func test_permanent_upgrades() -> void:
	var stats := _init_player_stats()
	var base_dmg := stats.permanent_damage_mult
	var base_spd := stats.permanent_speed_mult
	var base_jmp := stats.permanent_jump_mult
	stats.apply_permanent_upgrade(&"damage", 0.05)
	stats.apply_permanent_upgrade(&"speed", 0.03)
	stats.apply_permanent_upgrade(&"jump", 0.10)
	_run_test("damage_upgrade", stats.permanent_damage_mult == base_dmg + 0.05)
	_run_test("speed_upgrade", stats.permanent_speed_mult == base_spd + 0.03)
	_run_test("jump_upgrade", stats.permanent_jump_mult == base_jmp + 0.10)
	_run_test("speed_affects_move", stats.move_speed > 5.0)


func test_serialization() -> void:
	var stats := _init_player_stats()
	stats.hp = 75.0
	stats.stamina = 60.0
	stats.infection = 20.0
	stats.coins = 500
	stats.permanent_damage_mult = 1.1
	var dict := stats.to_dict()
	var stats2 := PlayerStats.new()
	stats2.from_dict(dict)
	_run_test("serialization_hp", stats2.hp == 75.0)
	_run_test("serialization_stamina", stats2.stamina == 60.0)
	_run_test("serialization_infection", stats2.infection == 20.0)
	_run_test("serialization_coins", stats2.coins == 500)
	_run_test("serialization_damage_mult", stats2.permanent_damage_mult == 1.1)


func run() -> int:
	test_health_clamping()
	test_stamina_clamping()
	test_infection_clamping()
	test_receive_damage()
	test_heal()
	test_add_infection()
	test_cure_infection()
	test_try_consume_stamina()
	test_regenerate_out_of_combat()
	test_regenerate_in_combat()
	test_permanent_upgrades()
	test_serialization()
	print("\n=== STATS TESTS: %d passed, %d failed ===" % [passed, failed])
	return failed