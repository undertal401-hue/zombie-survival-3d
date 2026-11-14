extends RefCounted
## Tests unitarios de Currency, Shop, PriceTable, DropCalculator.

var passed: int = 0
var failed: int = 0


func _run_test(name: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("[PASS] %s" % name)
	else:
		failed += 1
		printerr("[FAIL] %s" % name)


func _reset_currency() -> void:
	Currency.reset(100)


func test_currency_basics() -> void:
	_reset_currency()
	_run_test("initial_balance", Currency.balance == 100)
	Currency.add(50, &"test")
	_run_test("add_coins", Currency.balance == 150)
	Currency.try_spend(30, &"test")
	_run_test("spend_coins", Currency.balance == 120)
	_run_test("spend_fail", not Currency.try_spend(200, &"test"))
	_run_test("balance_unchanged", Currency.balance == 120)
	_run_test("can_afford_true", Currency.can_afford(100))
	_run_test("can_afford_false", not Currency.can_afford(150))


func test_currency_totals() -> void:
	_reset_currency()
	Currency.add(100, &"pickup")
	Currency.try_spend(30, &"shop")
	_run_test("total_earned", Currency.total_earned == 100)
	_run_test("total_spent", Currency.total_spent == 30)
	_run_test("total_picked", Currency.total_picked == 100)


func test_currency_serialization() -> void:
	_reset_currency()
	Currency.add(250, &"test")
	Currency.try_spend(50, &"test")
	var dict := Currency.to_dict()
	Currency.reset(0)
	Currency.from_dict(dict)
	_run_test("serialized_balance", Currency.balance == 300)
	_run_test("serialized_earned", Currency.total_earned == 250)
	_run_test("serialized_spent", Currency.total_spent == 50)


func test_rarity_table() -> void:
	var table := Rarity.standard_table()
	_run_test("rarity_count", table.size() == 5)
	_run_test("rarity_order", table[0].rarity_id == &"common")
	_run_test("rarity_legendary", table[4].rarity_id == &"legendary")
	_run_test("rarity_weights", table[0].drop_weight > table[4].drop_weight)


func test_price_table() -> void:
	var pt := PriceTable.new()
	pt.add_entry(&"test_weapon", 500, &"rare", &"weapon", 3)
	pt.add_entry(&"test_ammo", 50, &"common", &"ammo", 1)
	var rarities := Rarity.standard_table()
	var cost1 := pt.final_cost(&"test_weapon", 1, rarities)
	var cost2 := pt.final_cost(&"test_weapon", 10, rarities)
	_run_test("price_wave1", cost1 > 0)
	_run_test("price_inflation", cost2 > cost1)
	_run_test("price_unknown", pt.final_cost(&"unknown", 1, rarities) == -1)
	_run_test("unlocked_wave3", pt.is_unlocked(&"test_weapon", 3))
	_run_test("locked_wave2", not pt.is_unlocked(&"test_weapon", 2))


func test_shop_purchase() -> void:
	_reset_currency()
	Currency.add(1000, &"test")
	var shop := Shop.new()
	shop.price_table = PriceTable.new()
	shop.price_table.add_entry(&"test_item", 100, &"common", &"consumable", 1)
	shop.rarity_table = Rarity.standard_table()
	shop.set_wave(1)
	var success := shop.purchase(&"test_item")
	_run_test("purchase_success", success)
	_run_test("balance_after", Currency.balance == 1000)
	var fail := shop.purchase(&"unknown")
	_run_test("purchase_fail_unknown", not fail)
	shop.free()


func test_loot_table() -> void:
	var lt := LootTable.new()
	lt.table_id = &"test"
	lt.add_entry(&"item_a", 10.0, 1, 2)
	lt.add_entry(&"item_b", 5.0, 1, 1)
	lt.rolls = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var results := lt.roll(rng)
	_run_test("loot_results", results.size() == 2)
	var total_weight := lt.total_weight()
	_run_test("loot_weight", abs(total_weight - 15.0) < 0.01)


func test_drop_calculator() -> void:
	var lt := LootTable.new()
	lt.add_entry(&"ammo_light", 10.0, 1, 3)
	var calc := DropCalculator.new()
	calc.configure(lt, 123)
	var drop := calc.calculate(&"walker", 1)
	_run_test("drop_has_coins", drop.has("coins"))
	_run_test("drop_coins_positive", drop.coins > 0)
	_run_test("drop_has_items", drop.has("items"))
	_run_test("drop_has_rare", drop.has("rare_upgrade"))


func test_drop_rare_chance() -> void:
	var chance := DropCalculator.current_rare_chance()
	_run_test("rare_chance_range", chance >= 0.01 and chance <= 0.03)


func run() -> int:
	test_currency_basics()
	test_currency_totals()
	test_currency_serialization()
	test_rarity_table()
	test_price_table()
	test_shop_purchase()
	test_loot_table()
	test_drop_calculator()
	test_drop_rare_chance()
	print("\n=== ECONOMY TESTS: %d passed, %d failed ===" % [passed, failed])
	return failed