extends RefCounted
## Tests unitarios de DamageSystem, DamageInfo, CriticalHit.

var passed: int = 0
var failed: int = 0


func _run_test(name: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % name)
	else:
		failed += 1
		printerr("[FAIL] %s" % name)


func test_damage_info_creation() -> void:
	var info := DamageInfo.make(50.0, DamageInfo.DamageType.BULLET, null)
	_run_test("damage_info_amount", info.amount == 50.0)
	_run_test("damage_info_type", info.damage_type == DamageInfo.DamageType.BULLET)


func test_damage_info_duplicate() -> void:
	var info := DamageInfo.make(30.0, DamageInfo.DamageType.MELEE, null)
	info.is_headshot = true
	var copy := info.duplicate_info()
	_run_test("duplicate_amount", copy.amount == 30.0)
	_run_test("duplicate_headshot", copy.is_headshot)
	copy.amount = 99.0
	_run_test("independent_copy", info.amount == 30.0)


func test_damage_calculation_headshot() -> void:
	var system := DamageSystem.new()
	system.headshot_multiplier = 2.0
	var info := DamageInfo.make(20.0, DamageInfo.DamageType.BULLET, null)
	info.is_headshot = true
	var result := system.calculate(info)
	_run_test("headshot_doubles", result.amount == 40.0)
	system.free()


func test_damage_calculation_crit() -> void:
	var system := DamageSystem.new()
	system.crit_chance = 1.0
	system.crit_multiplier = 2.0
	var info := DamageInfo.make(25.0, DamageInfo.DamageType.BULLET, null)
	var result := system.calculate(info)
	_run_test("crit_applied", result.amount == 50.0)
	_run_test("crit_flag", result.is_critical)
	system.free()


func test_damage_calculation_no_crit() -> void:
	var system := DamageSystem.new()
	system.crit_chance = 0.0
	var info := DamageInfo.make(25.0, DamageInfo.DamageType.BULLET, null)
	var result := system.calculate(info)
	_run_test("no_crit", result.amount == 25.0)
	_run_test("no_crit_flag", not result.is_critical)
	system.free()


func test_critical_hit_utility() -> void:
	CriticalHit.set_seed(12345)
	CriticalHit.chance = 1.0
	CriticalHit.multiplier = 1.5
	var result := CriticalHit.apply(100.0)
	_run_test("crit_utility_amount", result.amount == 150.0)
	_run_test("crit_utility_flag", result.is_critical)


func test_critical_hit_no_crit() -> void:
	CriticalHit.set_seed(12345)
	CriticalHit.chance = 0.0
	var result := CriticalHit.apply(100.0)
	_run_test("no_crit_utility", result.amount == 100.0)


func test_damage_falloff() -> void:
	var data := WeaponData.new()
	data.damage = 100.0
	data.damage_falloff_start = 10.0
	data.damage_falloff_end = 50.0
	data.damage_falloff_min = 0.3
	_run_test("falloff_close", data.damage_at_distance(5.0) == 100.0)
	_run_test("falloff_far", data.damage_at_distance(60.0) == 30.0)
	var mid := data.damage_at_distance(30.0)
	_run_test("falloff_mid", mid > 30.0 and mid < 100.0)


func test_knockback_system() -> void:
	var system := KnockbackSystem.new()
	var body := CharacterBody3D.new()
	body.position = Vector3.ZERO
	var applied := system.apply(body, Vector3(1, 0, 0), 10.0)
	_run_test("knockback_applied", applied)
	_run_test("knockback_velocity", body.velocity.x > 0.0)
	body.free()
	system.free()


func test_explosion_system() -> void:
	var system := ExplosionSystem.new()
	system.default_radius = 5.0
	system.default_damage = 50.0
	system.default_knockback = 10.0
	var dmg_sys := DamageSystem.new()
	system.damage_system = dmg_sys
	var kb_sys := KnockbackSystem.new()
	system.knockback_system = kb_sys
	var result := system.detonate(Vector3.ZERO, 5.0, 50.0, null)
	_run_test("explosion_result_keys", result.has("affected") and result.has("knockback"))
	system.free()
	dmg_sys.free()
	kb_sys.free()


func run() -> int:
	test_damage_info_creation()
	test_damage_info_duplicate()
	test_damage_calculation_headshot()
	test_damage_calculation_crit()
	test_damage_calculation_no_crit()
	test_critical_hit_utility()
	test_critical_hit_no_crit()
	test_damage_falloff()
	test_knockback_system()
	test_explosion_system()
	print("\n=== DAMAGE TESTS: %d passed, %d failed ===" % [passed, failed])
	return failed