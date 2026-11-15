class_name Player
extends CharacterBody3D

const PLAYER_LAYER: int = 1
const PLAYER_MASK: int = 1 | 2 | 4 | 8

var stats
@export var start_position: Vector3 = Vector3.ZERO

var controller
var inventory
var input_handler
var camera_rig
var interaction
var audio
var config
var event_bus

var is_in_combat: bool = false
var is_dodging: bool = false
var _combat_timer: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	collision_layer = PLAYER_LAYER
	collision_mask = PLAYER_MASK
	add_to_group("player")

	var stats_script: Script = load("res://02_player/PlayerStats.gd")
	stats = stats_script.new()
	config = load("res://16_data/GameBalance.tres")
	stats.configure(config)

	_build_components()
	_build_weapons()
	global_position = start_position

	event_bus = get_tree().root.get_node_or_null("EventBus")
	if event_bus != null:
		event_bus.player_spawned.emit(self)
		event_bus.player_health_changed.emit(stats.hp, stats.max_hp)
		event_bus.player_stamina_changed.emit(stats.stamina, stats.max_stamina)
		event_bus.player_infection_changed.emit(stats.infection, stats.max_infection)

func _build_components() -> void:
	var input_script: Script = load("res://02_player/InputHandler.gd")
	input_handler = input_script.new()
	input_handler.name = "InputHandler"
	add_child(input_handler)

	var controller_script: Script = load("res://02_player/PlayerController.gd")
	controller = controller_script.new()
	controller.name = "PlayerController"
	controller.player = self
	add_child(controller)

	var camera_script: Script = load("res://02_player/PlayerCamera.gd")
	camera_rig = camera_script.new()
	camera_rig.name = "PlayerCamera"
	add_child(camera_rig)

	inventory = load("res://02_player/Inventory.gd").new()

	var interaction_script: Script = load("res://02_player/InteractionComponent.gd")
	interaction = interaction_script.new()
	interaction.name = "Interaction"
	interaction.player = self
	add_child(interaction)

	var audio_script: Script = load("res://02_player/PlayerAudio.gd")
	audio = audio_script.new()
	audio.name = "PlayerAudio"
	add_child(audio)

func _build_weapons() -> void:
	var weapon_manager := WeaponManager.new()
	weapon_manager.name = "WeaponManager"
	weapon_manager.player = self
	add_child(weapon_manager)

	var pistol_data: WeaponData = WeaponData.pistol()
	var pistol := RangedWeapon.new()
	pistol.data = pistol_data
	pistol.name = "Pistol"
	weapon_manager.register_weapon(pistol)
	inventory.add_weapon(pistol)

	var knife_data: WeaponData = WeaponData.knife()
	var knife := MeleeWeapon.new()
	knife.data = knife_data
	knife.name = "Knife"
	weapon_manager.register_weapon(knife)
	inventory.add_weapon(knife)

	weapon_manager.call_deferred("switch_to", 2)

func _physics_process(delta: float) -> void:
	stats.regenerate(delta, is_in_combat)
	_update_combat_state(delta)

func _update_combat_state(delta: float) -> void:
	if is_in_combat:
		_combat_timer -= delta
		if _combat_timer <= 0.0:
			is_in_combat = false

func receive_damage(info) -> void:
	if info == null or info.amount <= 0.0:
		return
	stats.receive_damage(info.amount)
	is_in_combat = true
	_combat_timer = config.player_hp_regen_delay

	if info.infection > 0.0:
		stats.add_infection(info.infection)

	if event_bus != null:
		event_bus.player_damaged.emit(info.amount, info.source)
		event_bus.player_health_changed.emit(stats.hp, stats.max_hp)

	if stats.hp <= 0.0:
		_die("killed")
	elif stats.infection >= config.infection_game_over_at:
		_die("infection")

func heal(amount: float) -> void:
	stats.heal(amount)
	if event_bus != null:
		event_bus.player_healed.emit(amount, self)
		event_bus.player_health_changed.emit(stats.hp, stats.max_hp)

func cure_infection(amount: float) -> void:
	var applied: float = stats.cure_infection(amount)
	if applied > 0.0 and event_bus != null:
		event_bus.infection_cured.emit(applied)
		event_bus.player_infection_changed.emit(stats.infection, stats.max_infection)

func _die(reason) -> void:
	if not is_inside_tree():
		return

	if event_bus != null:
		event_bus.player_died.emit(self)

	set_physics_process(false)
	var gm: Node = get_tree().root.get_node_or_null("GameManager")
	if gm != null:
		gm.call("game_over", reason)

func respawn(at: Vector3) -> void:
	global_position = at
	stats.hp = stats.max_hp
	is_in_combat = false
	set_physics_process(true)

	if event_bus != null:
		event_bus.player_spawned.emit(self)

func get_stats():
	return stats

func get_inventory():
	return inventory
