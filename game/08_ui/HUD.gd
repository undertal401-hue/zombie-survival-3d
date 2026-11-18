extends CanvasLayer

@onready var hp_label: Label = $Status/Margin/VBox/HPLabel
@onready var hp_bar: ProgressBar = $Status/Margin/VBox/HPBar
@onready var stamina_label: Label = $Status/Margin/VBox/StaminaLabel
@onready var stamina_bar: ProgressBar = $Status/Margin/VBox/StaminaBar
@onready var hunger_label: Label = $Status/Margin/VBox/HungerLabel
@onready var hunger_bar: ProgressBar = $Status/Margin/VBox/HungerBar
@onready var resources_label: Label = $Status/Margin/VBox/ResourcesLabel
@onready var reload_label: Label = $Status/Margin/VBox/ReloadLabel
@onready var reload_bar: ProgressBar = $Status/Margin/VBox/ReloadBar
@onready var objective_label: Label = $Objective/Margin/VBox/ObjectiveLabel
@onready var prompt: Label = $Prompt
@onready var toast: Label = $Toast
@onready var damage_flash: ColorRect = $DamageFlash
@onready var end_overlay: ColorRect = $EndOverlay
@onready var end_title: Label = $EndOverlay/EndPanel/EndTitle
@onready var end_text: Label = $EndOverlay/EndPanel/EndText
@onready var end_hint: Label = $EndOverlay/EndPanel/EndHint

var player: Node2D
var _weapon_controller: WeaponController

var _ended: bool = false
var _toast_timer: float = 0.0
var _toast_priority: int = 0
var _flash_timer: float = 0.0
var _last_hp: float = -1.0
var _pulse_timer: float = 0.0
var _pulse_color: Color = Color(1, 1, 1, 1)
var _pulse_target: CanvasItem

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D
	add_to_group("hud")

	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.player_stamina_changed.connect(_on_stamina_changed)
	EventBus.player_hunger_changed.connect(_on_hunger_changed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.interaction_prompt.connect(_on_prompt)
	EventBus.interaction_cleared.connect(_on_prompt_cleared)
	EventBus.notification.connect(_on_notification)
	if EventBus.has_signal("priority_notification"):
		EventBus.priority_notification.connect(_on_priority_notification)
	EventBus.game_over.connect(_on_game_over)
	EventBus.victory.connect(_on_victory)
	Inventory.inventory_changed.connect(_refresh_resources)

	if player != null:
		_weapon_controller = player.get_node_or_null("WeaponController") as WeaponController
		if _weapon_controller != null:
			# Las señales llevan argumentos; usar lambdas para adaptar la aridad
			# al callback sin parámetros.
			_weapon_controller.ammo_changed.connect(func(_current: int, _total: int, _chamber: int) -> void: _refresh_resources())
			_weapon_controller.weapon_changed.connect(func(_weapon: Weapon) -> void: _on_weapon_changed(_weapon))
			_weapon_controller.reloading_started.connect(_on_reload_started)
			_weapon_controller.reloading_finished.connect(_on_reload_finished)
			_weapon_controller.dry_fire.connect(_on_dry_fire)

	prompt.text = ""
	toast.text = ""
	end_overlay.visible = false
	damage_flash.color = Color(0.75, 0.0, 0.0, 0.0)
	reload_label.visible = false
	reload_bar.visible = false
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
			_toast_priority = 0

	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		damage_flash.color = Color(0.75, 0.0, 0.0, _flash_timer / 0.3 * 0.25)

	if _pulse_timer > 0.0 and _pulse_target != null and is_instance_valid(_pulse_target):
		_pulse_timer = maxf(_pulse_timer - delta, 0.0)
		var t: float = 1.0 - (_pulse_timer / 0.35)
		_pulse_target.modulate = _pulse_color.lerp(Color(1, 1, 1, 1), t)
		if _pulse_timer <= 0.0:
			_pulse_target.modulate = Color(1, 1, 1, 1)
			_pulse_target = null

	# La recarga avanza aunque el inventario esté abierto; el HUD queda detrás
	# del oscurecedor, pero el inventario muestra su propia barra en sincronía.
	if not _ended and _weapon_controller != null and _weapon_controller.current_weapon != null:
		var w: Weapon = _weapon_controller.current_weapon
		if w.is_reloading:
			var progress: float = w.get_reload_progress()
			reload_bar.value = progress
			reload_label.text = "RECARGANDO %s %d%%" % [w.weapon_name, int(progress * 100.0)]

func _unhandled_input(event: InputEvent) -> void:
	if not _ended or not event.is_action_pressed("restart") or event.echo:
		return
	get_viewport().set_input_as_handled()
	get_tree().paused = false
	Inventory.clear()
	get_tree().reload_current_scene()

func _pulse_label(target: CanvasItem, color: Color) -> void:
	if target == null or not is_instance_valid(target):
		return
	_pulse_target = target
	_pulse_color = color
	_pulse_timer = 0.35
	target.modulate = color

func _on_health_changed(hp: float, max_hp: float) -> void:
	hp_label.text = "VIDA %d / %d%s" % [
		int(hp), int(max_hp), "  ¡CRÍTICO!" if hp <= max_hp * 0.25 else ""
	]
	if hp <= max_hp * 0.25:
		hp_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5, 1.0))
	else:
		hp_label.add_theme_color_override("font_color", Color(1, 0.72, 0.72, 1))
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	if _last_hp >= 0.0 and hp > _last_hp + 0.5:
		_pulse_label(hp_bar, Color(0.6, 1.0, 0.6, 1))
	_last_hp = hp

func _on_stamina_changed(stamina: float, max_stamina: float) -> void:
	stamina_label.text = "AGUANTE %d / %d%s" % [
		int(stamina), int(max_stamina), "  · SIN AGUANTE" if stamina < 20.0 else ""
	]
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
	# Evita que un "Sin objetivo" / "Impacto!" borre un aviso urgente en <1 s.
	var priority: int = 1
	if text.contains("Inanición") or text.begins_with("¡"):
		priority = 3
	elif text.begins_with("Equipado") or text.contains("recargad") or text.contains("+"):
		priority = 2
	if priority < _toast_priority and _toast_timer > 0.0:
		return
	_toast_priority = priority
	toast.text = text
	_toast_timer = 3.5 if priority == 3 else 2.2

## Avisos urgentes del director de mundo: fuerzan prioridad máxima para que
## una horda o una tormenta no quede oculta tras un mensaje de loot.
func _on_priority_notification(text: String) -> void:
	if _ended:
		return
	_toast_priority = 3
	toast.text = text
	_toast_timer = 4.5

func _on_weapon_changed(w: Weapon) -> void:
	_refresh_resources()
	if w != null:
		var color: Color = Color(1.0, 0.85, 0.45, 1)
		if w.category == Weapon.Category.MELEE:
			color = Color(0.8, 0.8, 0.86, 1)
		_pulse_label(resources_label, color)

func _on_reload_started(weapon: Weapon, _duration: float) -> void:
	reload_label.text = "RECARGANDO %s 0%%" % weapon.weapon_name
	reload_bar.value = 0.0
	reload_label.visible = true
	reload_bar.visible = true

func _on_reload_finished(_weapon: Weapon) -> void:
	reload_label.visible = false
	reload_bar.visible = false
	_pulse_label(resources_label, Color(0.6, 1.0, 0.6, 1))
	_refresh_resources()

func _on_dry_fire(_weapon: Weapon) -> void:
	_on_notification("¡Cargador vacío! Pulsa R para recargar")

func _refresh_resources() -> void:
	var fuel: int = Inventory.count("combustible")
	var medkits: int = Inventory.count("medkit")
	var food: int = Inventory.count("comida")
	var base_text: String = "Bidones: %d   Botiquines: %d   Comida: %d" % [fuel, medkits, food]

	# Tras _die() el jugador sale del grupo: conservar la referencia evita que
	# el HUD congele la munición en la pantalla final.
	var wc: WeaponController = _weapon_controller
	if wc == null or not is_instance_valid(wc):
		var p := get_tree().get_first_node_in_group("player")
		if p != null:
			wc = p.get_node_or_null("WeaponController") as WeaponController
			_weapon_controller = wc

	# magazine_size ya es la capacidad total (cargador + recámara): el HUD
	# muestra balas cargadas / capacidad, y oculta el bloque si es melee.
	if wc != null and wc.current_weapon != null and wc.current_weapon.category != Weapon.Category.MELEE:
		var weapon: Weapon = wc.current_weapon
		var ammo_key: String = weapon.ammo_type if weapon.ammo_type != "" else "pistol_ammo"
		resources_label.text = "%s   Munición: %d/%d  Reserva: %d" % [
			base_text, weapon.get_total_ammo(), weapon.get_max_ammo(), Inventory.count(ammo_key)]
	else:
		resources_label.text = base_text

	# Objetivo dinámico según progreso
	if fuel >= 3:
		objective_label.text = "¡Consigue 3 bidones! Ve a la zona de extracción."
		objective_label.modulate = Color(0.6, 1.0, 0.6)
	else:
		objective_label.text = "Consigue %d/3 bidones de combustible y extrae." % fuel
		objective_label.modulate = Color(1.0, 0.85, 0.5)

func _on_game_over() -> void:
	_end_game("HAS CAÍDO", "No sobreviviste. Reintenta y prepara mejor tu próxima salida.", Color(1.0, 0.4, 0.4))

func _on_victory() -> void:
	_end_game("¡EXTRACTION EXITOSA!", "Has conseguido el combustible y escapado con vida.\n\n¡SOBREVIVISTE!", Color(0.6, 1.0, 0.6))

func _end_game(title: String, text: String, color: Color) -> void:
	if _ended:
		return
	_ended = true
	prompt.text = ""
	toast.text = ""
	reload_label.visible = false
	reload_bar.visible = false
	end_overlay.visible = true
	end_title.text = title
	end_title.modulate = color
	end_text.text = text
	end_hint.text = "R para reintentar"
	get_tree().paused = true
