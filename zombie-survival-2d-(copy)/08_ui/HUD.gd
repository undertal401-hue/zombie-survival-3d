extends CanvasLayer

const DAMAGE_FLASH_SHADER: Shader = preload("res://assets/shaders/DamageFlash.gdshader")

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
# ÍTEM 10: multiplicador de combo con barra acotada a MAX_COMBO (x3.0).
@onready var combo_mult_label: Label = $Status/Margin/VBox/ComboMultLabel
@onready var combo_bar: ProgressBar = $Status/Margin/VBox/ComboBar
# Requisito del arnés de tensión: oleadas + reloj cacheados (sin escaneos/frame).
@onready var wave_clock_label: Label = $Status/Margin/VBox/WaveClockLabel

var player: Node2D
var _weapon_controller: WeaponController
var wave: int = 0
var clock: float = 0.0
var _last_clock_second: int = -1

var _ended: bool = false
var _toast_timer: float = 0.0
var _toast_priority: int = 0
var _flash_timer: float = 0.0
var _last_hp: float = -1.0
var _pulse_timer: float = 0.0
var _pulse_color: Color = Color(1, 1, 1, 1)
var _pulse_target: CanvasItem

# ---------------------------------------------------------------------------
# ÍTEM 17 — tutorial contextual, ligero y NO bloqueante.
# Solo se muestra en la primera partida: el estado se persiste en
# user://zombie_tutorial.cfg y nunca se reabre en partidas posteriores.
# Tres pistas: "E para saquear (interact)", "Tab inventario (inventory)" y
# "R para recargar (reload)". Cada una se oculta al cumplir la acción real.
# Esto no abre el menú de objetos ni detiene el árbol: es solo una etiqueta.
# ---------------------------------------------------------------------------
const TUTORIAL_SAVE_PATH: String = "user://zombie_tutorial.cfg"
const TUTORIAL_SAVE_SECTION: String = "tutorial"
const TUTORIAL_SAVE_KEY: String = "completed"

var _tutorial_hint: Label
var _tutorial_steps: Dictionary = {}
var _tutorial_enabled: bool = false

func _init_tutorial() -> void:
	var save := ConfigFile.new()
	var seen: bool = save.load(TUTORIAL_SAVE_PATH) == OK \
		and bool(save.get_value(TUTORIAL_SAVE_SECTION, TUTORIAL_SAVE_KEY, false))
	_tutorial_enabled = not seen
	_tutorial_hint = Label.new()
	_tutorial_hint.name = "TutorialHint"
	_tutorial_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_hint.anchor_left = 0.5
	_tutorial_hint.anchor_right = 0.5
	_tutorial_hint.anchor_top = 0.0
	_tutorial_hint.anchor_bottom = 0.0
	_tutorial_hint.offset_left = -360.0
	_tutorial_hint.offset_right = 360.0
	_tutorial_hint.offset_top = 92.0
	_tutorial_hint.offset_bottom = 136.0
	_tutorial_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_hint.add_theme_color_override("font_color", Color(0.937, 0.894, 0.741, 1))
	_tutorial_hint.add_theme_color_override("font_outline_color", Color(0.043, 0.051, 0.043, 1))
	_tutorial_hint.add_theme_constant_override("outline_size", 4)
	_tutorial_hint.add_theme_font_size_override("font_size", 15)
	add_child(_tutorial_hint)
	if not _tutorial_enabled:
		_tutorial_hint.visible = false
		return
	_tutorial_steps = {"loot": false, "bag": false, "reload": false}
	var interact_cb := Callable(self, "_tutorial_on_interact")
	if not EventBus.interaction_prompt.is_connected(interact_cb):
		EventBus.interaction_prompt.connect(interact_cb)
	if _weapon_controller != null and _weapon_controller.has_signal("reloading_started"):
		var reload_cb := Callable(self, "_tutorial_on_reload")
		if not _weapon_controller.reloading_started.is_connected(reload_cb):
			_weapon_controller.reloading_started.connect(reload_cb)
	_refresh_tutorial()


func _refresh_tutorial() -> void:
	if not _tutorial_enabled or _tutorial_hint == null:
		return
	var lines: Array[String] = []
	if not bool(_tutorial_steps.get("loot", false)):
		lines.append("E para saquear (interact)")
	if not bool(_tutorial_steps.get("bag", false)):
		lines.append("Tab inventario (inventory)")
	if not bool(_tutorial_steps.get("reload", false)):
		lines.append("R para recargar (reload)")
	if lines.is_empty():
		_tutorial_finish()
		return
	var text: String = "TUTORIAL  ·  "
	for i in range(lines.size()):
		if i > 0:
			text += "   |   "
		text += lines[i]
	_tutorial_hint.text = text
	_tutorial_hint.visible = true


func _tutorial_mark(step: String) -> void:
	if not _tutorial_enabled or not _tutorial_steps.has(step):
		return
	if bool(_tutorial_steps[step]):
		return
	_tutorial_steps[step] = true
	_refresh_tutorial()


func _tutorial_on_interact(_text: String) -> void:
	_tutorial_mark("loot")


func _tutorial_on_reload(_weapon: Weapon, _duration: float) -> void:
	_tutorial_mark("reload")


func _tutorial_on_input(event: InputEvent) -> void:
	if not _tutorial_enabled:
		return
	# Solo teclado/acciones: los eventos de ratón (InputEventMouseMotion,
	# InputEventMouseButton) NO tienen propiedad `echo`, y leerla lanzaba un
	# SCRIPT ERROR en cada movimiento del puntero.
	if not (event is InputEventKey or event is InputEventAction):
		return
	if event.is_echo():
		return
	if event.is_action_pressed("inventory"):
		_tutorial_mark("bag")


func _tutorial_finish() -> void:
	if _tutorial_hint != null:
		_tutorial_hint.hide()
		_tutorial_hint.visible = false
	var save := ConfigFile.new()
	save.set_value(TUTORIAL_SAVE_SECTION, TUTORIAL_SAVE_KEY, true)
	save.save(TUTORIAL_SAVE_PATH)
	_tutorial_enabled = false

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

	# ÍTEM 10 + tensión: el HUD solo consume cachés del estado central.
	if GameState.has_signal("combo_changed"):
		GameState.combo_changed.connect(_on_combo_changed)
	if GameState.has_signal("wave_changed"):
		GameState.wave_changed.connect(_on_wave_changed)
	wave = GameState.get_wave()
	clock = GameState.run_clock
	_refresh_wave_clock()
	_on_combo_changed(GameState.combo_multiplier, GameState.combo_count)

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

	# ÍTEM 17: el tutorial se configura tras tener el control de arma.
	_init_tutorial()

	prompt.text = ""
	toast.text = ""
	end_overlay.visible = false
	# El flash usa el shader real en vez de animar el alpha del ColorRect.
	var flash_material := ShaderMaterial.new()
	flash_material.shader = DAMAGE_FLASH_SHADER
	damage_flash.material = flash_material
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
	# Reloj cacheado del GameState: sin find_children/get_nodes por frame.
	clock = GameState.run_clock
	var whole_second: int = int(clock)
	if whole_second != _last_clock_second:
		_last_clock_second = whole_second
		_refresh_wave_clock()
	if _toast_timer > 0.0:
		_toast_timer = maxf(_toast_timer - delta, 0.0)
		if _toast_timer <= 0.0:
			toast.text = ""
			_toast_priority = 0

	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		var intensity: float = _flash_timer / 0.3 * 0.25
		if damage_flash.material is ShaderMaterial:
			(damage_flash.material as ShaderMaterial).set_shader_parameter("damage_flash", intensity)
		else:
			damage_flash.color = Color(0.75, 0.0, 0.0, intensity)

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
	# El tutorial solo observa la entrada: no la consume ni pausa el árbol.
	_tutorial_on_input(event)
	if not _ended or not event.is_action_pressed("restart") or event.is_echo():
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

	# Aviso de munición baja por color de fuente (no por modulate: _pulse_label
	# ya anima modulate al recargar y se pisaría). Los tests comparan el texto.
	if wc != null and wc.current_weapon != null and wc.current_weapon.category != Weapon.Category.MELEE:
		var weapon: Weapon = wc.current_weapon
		var capacity: int = maxi(weapon.get_max_ammo(), 1)
		var reserve: int = Inventory.count(weapon.ammo_type)
		if weapon.get_total_ammo() * 4 <= capacity and reserve == 0:
			resources_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.34))
		elif weapon.get_total_ammo() * 4 <= capacity:
			resources_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
		else:
			resources_label.add_theme_color_override("font_color", Color.WHITE)
	else:
		resources_label.add_theme_color_override("font_color", Color.WHITE)

	# Objetivo dinámico según progreso
	if fuel >= 3:
		objective_label.text = "¡Consigue 3 bidones! Ve a la zona de extracción."
		objective_label.modulate = Color(0.6, 1.0, 0.6)
	else:
		objective_label.text = "Consigue %d/3 bidones de combustible y extrae." % fuel
		objective_label.modulate = Color(1.0, 0.85, 0.5)

## ÍTEM 10: pinta el multiplicador de combo y su barra con la paleta canónica
## (AMBER/BONE/BLOOD_BRIGHT de ART_BIBLE.md). Estilo pixel: sin esquinas redondeadas.
func _on_combo_changed(value: float, count: int) -> void:
	var multiplier: float = clampf(value, 1.0, 3.0)
	combo_mult_label.text = "COMBO x%.1f" % multiplier
	combo_bar.max_value = 3.0
	combo_bar.value = multiplier
	var color: Color = Color(0.937, 0.894, 0.741, 1)  # BONE #efe4bd
	if multiplier >= 2.5:
		color = Color(0.910, 0.337, 0.235, 1)  # BLOOD_BRIGHT #e8563c
	elif multiplier >= 1.5:
		color = Color(0.824, 0.659, 0.404, 1)  # AMBER #d2a867
	combo_mult_label.add_theme_color_override("font_color", color)
	combo_mult_label.visible = multiplier > 1.0 or count > 0
	combo_bar.visible = combo_mult_label.visible


func _on_wave_changed(value: int) -> void:
	wave = maxi(0, value)
	_refresh_wave_clock()


func _refresh_wave_clock() -> void:
	var total: int = maxi(0, int(clock))
	wave_clock_label.text = "OLEADA %d  ·  RELOJ %02d:%02d" % [
		wave, (total / 60) % 100, total % 60
	]

func _on_game_over() -> void:
	_end_game("HAS CAÍDO", "No sobreviviste. Reintenta y prepara mejor tu próxima salida.", Color(1.0, 0.4, 0.4))

func _on_victory() -> void:
	# R1: se normaliza la grafía con la de GameOver.gd ("¡EXTRACCIÓN LOGARADA!")
	# y con la de ExtractionZone.gd. Antes esta línea decía "¡EXTRACTION
	# EXITOSA!" (sin tilde) mientras QA.gd:632 buscaba "EXTRACCIÓN", así que el
	# check de extracción del QA salía false aunque la victoria fuera real.
	_end_game("¡EXTRACCIÓN EXITOSA!", "Has conseguido el combustible y escapado con vida.\n\n¡SOBREVIVISTE!", Color(0.6, 1.0, 0.6))

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
