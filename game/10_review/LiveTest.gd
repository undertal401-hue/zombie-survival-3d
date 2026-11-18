extends Node

var main: Node
var player: CharacterBody2D
var menu: CanvasLayer
var hud: CanvasLayer
var inv

func _ready() -> void:
	main = load("res://07_house/Main.tscn").instantiate()
	add_child(main)
	player = main.get_node("Player")
	menu = main.get_node("InventoryMenu")
	hud = main.get_node("HUD")
	inv = get_node("/root/Inventory")
	
	print("LIVE TEST START")
	print("Player pos: ", player.global_position)
	print("Initial HUD: ", hud.get_node("Status/Margin/VBox/ResourcesLabel").text)
	print("Has pistol via WC: ", player.get_node_or_null("WeaponController").current_weapon.weapon_name if player.get_node_or_null("WeaponController") else "no WC")
	print("Initial ammo: ", inv.count("pistol_ammo"))
	print("Initial food: ", inv.count("comida"))
	
	var t := Timer.new()
	t.wait_time = 40.0
	t.one_shot = true
	t.timeout.connect(func() -> void:
		print("LIVE TEST TIMEOUT")
		get_tree().quit(0)
	)
	add_child(t)
	t.start()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("inventory"):
		print(">>> Tab pressed, menu open: ", menu.get("_open"))
	if Input.is_action_just_pressed("use_food"):
		print(">>> F pressed, food count: ", inv.count("comida"), " hunger: ", player.hunger)
	if Input.is_action_just_pressed("shoot"):
		var wc = player.get_node_or_null("WeaponController")
		var ammo = wc.current_weapon.get_total_ammo() if wc and wc.current_weapon else 0
		print(">>> Left click (shoot), ammo: ", ammo)
	if Input.is_action_just_pressed("attack"):
		print(">>> Right click/Space (attack), stamina: ", player.stamina)
	if Input.is_action_just_pressed("reload"):
		print(">>> R pressed (reload)")
	if Input.is_action_just_pressed("weapon_slot_1"):
		print(">>> Key 1 pressed (slot 1)")
	if Input.is_action_just_pressed("weapon_slot_2"):
		print(">>> Key 2 pressed (slot 2)")