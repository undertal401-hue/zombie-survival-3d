extends RefCounted
## Tests unitarios de WaveScaling, WaveData, WaveComposition.

var passed: int = 0
var failed: int = 0


func _run_test(name: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % name)
	else:
		failed += 1
		printerr("[FAIL] %s" % name)


func test_wave_scaling_hp() -> void:
	var scaling := WaveScaling.new()
	scaling.base_hp = 60.0
	scaling.hp_scale_per_wave = 0.15
	var mult1 := scaling.hp_multiplier(1)
	var mult10 := scaling.hp_multiplier(10)
	_run_test("hp_mult_wave1", mult1 == 1.0)
	_run_test("hp_mult_wave10", abs(mult10 - 2.35) < 0.01)
	var hp10 := scaling.hp_for_wave(10, 60.0)
	_run_test("hp_wave10", abs(hp10 - 141.0) < 0.1)


func test_wave_scaling_damage() -> void:
	var scaling := WaveScaling.new()
	scaling.base_damage = 10.0
	scaling.damage_scale_per_wave = 0.10
	var mult1 := scaling.damage_multiplier(1)
	var mult10 := scaling.damage_multiplier(10)
	_run_test("dmg_mult_wave1", mult1 == 1.0)
	_run_test("dmg_mult_wave10", abs(mult10 - 1.9) < 0.01)


func test_wave_scaling_speed() -> void:
	var scaling := WaveScaling.new()
	scaling.base_speed = 2.2
	scaling.speed_scale_per_wave = 0.05
	scaling.max_speed_multiplier = 2.5
	var mult1 := scaling.speed_multiplier(1)
	var mult10 := scaling.speed_multiplier(10)
	var mult50 := scaling.speed_multiplier(50)
	_run_test("spd_mult_wave1", mult1 == 1.0)
	_run_test("spd_mult_wave10", abs(mult10 - 1.45) < 0.01)
	_run_test("spd_mult_capped", mult50 == 2.5)


func test_wave_scaling_reward() -> void:
	var scaling := WaveScaling.new()
	scaling.base_reward = 50
	scaling.coin_scale_per_wave = 0.10
	_run_test("reward_wave1", scaling.reward_for_wave(1) == 50)
	_run_test("reward_wave10", scaling.reward_for_wave(10) == 95)


func test_wave_scaling_count() -> void:
	var scaling := WaveScaling.new()
	scaling.base_count = 8
	scaling.count_growth = 1.35
	_run_test("count_wave1", scaling.count_for_wave(1) == 8)
	_run_test("count_wave2", scaling.count_for_wave(2) == 10)
	_run_test("count_wave10", scaling.count_for_wave(10) == 119)


func test_wave_data_generate() -> void:
	var scaling := WaveScaling.new()
	scaling.base_count = 8
	scaling.count_growth = 1.35
	scaling.base_interval = 0.9
	scaling.base_reward = 50
	scaling.coin_scale_per_wave = 0.10
	scaling.boss_every = 10
	var data := WaveData.generate(5, scaling)
	_run_test("data_wave_number", data.wave_number == 5)
	_run_test("data_spawn_count", data.spawn_count > 0)
	_run_test("data_not_boss", not data.is_boss)
	var boss_data := WaveData.generate(10, scaling)
	_run_test("data_boss_wave", boss_data.is_boss)


func test_wave_composition() -> void:
	var data := WaveData.new()
	data.wave_number = 3
	data.spawn_count = 10
	data.add_type(&"walker", 10.0)
	data.add_type(&"runner", 5.0)
	var comp := WaveComposition.new()
	comp.set_seed(42)
	var list := comp.build(data)
	_run_test("comp_size", list.size() == 10)
	var walker_count := 0
	for t: StringName in list:
		if t == &"walker":
			walker_count += 1
	_run_test("comp_has_walker", walker_count > 0)


func test_weighted_picker() -> void:
	var picker := WeightedPicker.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	picker.add(&"a", 10.0)
	picker.add(&"b", 0.0)
	var result := picker.pick(rng)
	_run_test("picker_zero_weight", result == &"a")
	picker.clear()
	picker.add(&"x", 1.0)
	picker.add(&"y", 1.0)
	var counts := {"x": 0, "y": 0}
	for i in 1000:
		counts[str(picker.pick(rng))] += 1
	_run_test("picker_distribution", counts["x"] > 400 and counts["x"] < 600)


func run() -> int:
	test_wave_scaling_hp()
	test_wave_scaling_damage()
	test_wave_scaling_speed()
	test_wave_scaling_reward()
	test_wave_scaling_count()
	test_wave_data_generate()
	test_wave_composition()
	test_weighted_picker()
	print("\n=== WAVES TESTS: %d passed, %d failed ===" % [passed, failed])
	return failed