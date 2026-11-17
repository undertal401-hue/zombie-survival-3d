extends CanvasLayer

@onready var hp_label: Label = $Status/Margin/VBox/HPLabel
@onready var hp_bar: ProgressBar = $Status/Margin/VBox/HPBar
@onready var stamina_label: Label = $Status/Margin/VBox/StaminaLabel
@onready var stamina_bar: ProgressBar = $Status/Margin/VBox/StaminaBar
@onready var hunger_label: Label = $Status/Margin/VBox/HungerLabel
@onready var hunger_bar: ProgressBar = $Status/Margin/VBox/HungerBar
@onready var resources_label: Label = $Status/Margin/VBox/ResourcesLabel
@onready var objective_label: Label = $Objective/Margin/VBox/ObjectiveLabel
@onready var prompt: Label = $Prompt
@onready var toast: Label = $Toast
@onready var damage_flash: ColorRect = $DamageFlash
@onready var end_overlay: ColorRect = $EndOverlay
@onready var end_title: Label = $EndOverlay/EndPanel/EndTitle
@onready var end_text: Label = $EndOverlay/EndPanel/EndText
@onready var end_hint: Label = $EndOverlay/EndPanel/EndHint

var player: Node2D

var _ended: bool = false
var _toast_timer: float = 0.0
var _flash_timer: float = 0.0
var _last_ammo: int = -1

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D

	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.player_stamina_changed.connect(_on_stamina_changed)
	EventBus.player_hunger_changed.connect(_on_hunger_changed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.interaction_prompt.connect(_on_prompt)
	EventBus.interaction_cleared.connect(_on_prompt_cleared)
	EventBus.notification.connect(_on_notification)
	EventBus.game_over.connect(_on_game_over)
	Inventory.inventory_changed.connect(_refresh_resources)

	prompt.text = ""
	toast.text = ""
	end_overlay.visible = false
	damage_flash.color = Color(0.75, 0.0, 0.0, 0.0)
	_refresh_resources()
	if player != null:
		_on_health_changed(float(player.get("hp")), 100.0)
		_on_stamina_changed(float(player.get("stamina")), 100.0)
		_on_hunger_changed(
			float(player.get("hunger")),
			float(player.get("max_hunger")),
			float(player.get("hunger_warning_threshold"))
		)

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer = maxf(_toast_timer - delta, 0.0)
		if _toast_timer <= 0.0:
			toast.text = ""

	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		damage_flash.color = Color(0.75, 0.0, 0.0, _flash_timer / 0.3 * 0.25)

	if _ended:
		return

func _unhandled_input(event: InputEvent) -> void:
	if not _ended or not event.is_action_pressed("restart"):
		return
	get_viewport().set_input_as_handled()
	get_tree().paused = false
	Inventory.clear()
	get_tree().reload_current_scene()

func _on_health_changed(hp: float, max_hp: float) -> void:
	hp_label.text = "VIDA %d / %d" % [int(hp), int(max_hp)]
	hp_bar.max_value = max_hp
	hp_bar.value = hp

func _on_stamina_changed(stamina: float, max_stamina: float) -> void:
	stamina_label.text = "AGUANTE %d / %d" % [int(stamina), int(max_stamina)]
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina

func _on_hunger_changed(hunger: float, max_hunger: float, warning_threshold: float) -> void:
	hunger_bar.max_value = max_hunger
	hunger_bar.value = hunger
	if hunger <= 0.0:
		hunger_label.text = "HAMBRE 0 / %d  ¡INANICIÓN!" % int(max_hunger)
		hunger_label.add_theme_color_override("font_color", Color(1.0, 0.38, 0.28, 1.0))
	elif hunger <= warning_threshold:
		hunger_label.text = "HAMBRE %d / %d  ¡TENGO HAMBRE!" % [int(hunger), int(max_hunger)]
		hunger_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.3, 1.0))
	else:
		hunger_label.text = "HAMBRE %d / %d" % [int(hunger), int(max_hunger)]
		hunger_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.55, 1.0))

func _on_player_damaged(_amount: float, _source: Node) -> void:
	_flash_timer = 0.3

func _on_prompt(text: String) -> void:
	if _ended:
		return
	prompt.text = text

func _on_prompt_cleared() -> void:
	prompt.text = ""

func _on_notification(text: String) -> void:
	if _ended:
		return
	toast.text = text
	_toast_timer = 2.2

func _refresh_resources() -> void:
	var fuel: int = Inventory.count("combustible")
	var medkits: int = Inventory.count("medkit")
	var food: int = Inventory.count("comida")
	var ammo: int = Inventory.count("pistol_ammo")
	
	var player := get_tree().get_first_node_in_group("player")
	var has_pistol: bool = false
	if player != null:
		has_pistol = player.get("has_pistol")
	
	if has_pistol:
		resources_label.text = "Bidones: %d   Botiquines: %d   Comida: %d   Munición: %d" % [fuel, medkits, food, ammo]
	else:
		resources_label.text = "Bidones: %d   Botiquines: %d   Comida: %d" % [fuel, medkits, food]
	
	objective_label.text = "Explora, saquea y sobrevive."
	objective_label.modulate = Color(0.8, 0.9, 1.0)

func _on_game_over() -> void:
	_end_game("HAS CAÍDO", "No sobreviviste. Reintenta y prepara mejor tu próxima salida.", Color(1.0, 0.4, 0.4))

func _end_game(title: String, text: String, color: Color) -> void:
	if _ended:
		return
	_ended = true
	prompt.text = ""
	toast.text = ""
	end_overlay.visible = true
	end_title.text = title
	end_title.modulate = color
	end_text.text = text
	end_hint.text = "R para reintentar"
	get_tree().paused = true
