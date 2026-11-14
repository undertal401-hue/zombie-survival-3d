class_name HUD


extends CanvasLayer
## HUD principal: barras de vida, stamina, infeccion, ammo, oleada, monedas.
##
## Se actualiza via EventBus; no consulta directamente al jugador.
## Accesible globalmente via `HUD` (class_name).

signal crosshair_visibility_changed(visible: bool)

@onready var health_bar: HealthBar = %HealthBar
@onready var stamina_bar: StaminaBar = %StaminaBar
@onready var infection_bar: InfectionBar = %InfectionBar
@onready var ammo_label: Label = %AmmoLabel
@onready var wave_label: Label = %WaveLabel
@onready var coin_label: Label = %CoinLabel
@onready var notification_panel: VBoxContainer = %NotificationPanel
@onready var crosshair: TextureRect = %Crosshair
@onready var interaction_prompt: Label = %InteractionPrompt

var _notifications: Array[Dictionary] = []
var _player: Player = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_signals()


func _connect_signals() -> void:
	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.player_stamina_changed.connect(_on_stamina_changed)
	EventBus.player_infection_changed.connect(_on_infection_changed)
	EventBus.ammo_changed.connect(_on_ammo_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.ui_notification.connect(_on_notification)
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.safe_zone_entered.connect(_on_safe_zone_entered)
	EventBus.safe_zone_exited.connect(_on_safe_zone_exited)


## Obtiene el jugador del arbol (diferido hasta que exista).
func _on_player_ready() -> void:
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player != null:
		_player = player
		health_bar.set_max(player.stats.max_hp)
		health_bar.set_value(player.stats.hp)
		stamina_bar.set_max(player.stats.max_stamina)
		stamina_bar.set_value(player.stats.stamina)
		infection_bar.set_max(player.stats.max_infection)
		infection_bar.set_value(player.stats.infection)


func _process(delta: float) -> void:
	_update_notifications(delta)
	_update_crosshair_spread()


func _update_notifications(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for notif: Dictionary in _notifications:
		notif["time"] -= delta
		if notif["time"] > 0.0:
			keep.append(notif)
		else:
			if notif["label"].is_inside_tree():
				notif["label"].queue_free()
	_notifications = keep


func _update_crosshair_spread() -> void:
	if _player == null or _player.weapon_manager == null:
		return
	var weapon: BaseWeapon = _player.weapon_manager.active_weapon
	if weapon is RangedWeapon:
		var spread: float = (weapon as RangedWeapon).recoil.current_spread((weapon as RangedWeapon).is_ads_active)
		crosshair.scale = Vector2.ONE * (1.0 + spread * 0.1)


func _on_player_spawned(player: Node3D) -> void:
	if player is Player:
		_player = player as Player


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.set_max(maximum)
	health_bar.set_value(current)


func _on_stamina_changed(current: float, maximum: float) -> void:
	stamina_bar.set_max(maximum)
	stamina_bar.set_value(current)


func _on_infection_changed(current: float, maximum: float) -> void:
	infection_bar.set_max(maximum)
	infection_bar.set_value(current)


func _on_ammo_changed(weapon: BaseWeapon, magazine: int, reserve: int) -> void:
	if _player != null and weapon == _player.weapon_manager.active_weapon:
		ammo_label.text = "%d / %d" % [magazine, reserve]


func _on_currency_changed(balance: int, delta: int) -> void:
	coin_label.text = "%d" % balance


func _on_wave_started(wave_number: int) -> void:
	wave_label.text = "Oleada %d" % wave_number


func _on_notification(text: String, tone: StringName) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", _color_for_tone(tone))
	notification_panel.add_child(label)
	_notifications.append({"label": label, "time": Config.ui_notification_duration})


func _on_safe_zone_entered(_zone: Node3D) -> void:
	interaction_prompt.text = "[E] Baño - Zona Segura"
	interaction_prompt.visible = true


func _on_safe_zone_exited(_zone: Node3D) -> void:
	interaction_prompt.visible = false


func _color_for_tone(tone: StringName) -> Color:
	match tone:
		&"warning": return Color(1.0, 0.6, 0.1)
		&"error": return Color(1.0, 0.3, 0.3)
		&"reward": return Color(0.3, 1.0, 0.5)
	return Color(1.0, 1.0, 1.0)
