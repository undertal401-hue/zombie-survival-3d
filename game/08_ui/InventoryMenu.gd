extends CanvasLayer

## Menú de inventario - se abre/cierra con Tab
## No pausa el juego, solo bloquea inputs del jugador

@onready var background: ColorRect = $Background
@onready var panel: Panel = $Panel
@onready var items_list: VBoxContainer = $Panel/ItemsSection/ItemsContainer/ItemsList
@onready var empty_label: Label = $Panel/ItemsSection/ItemsContainer/ItemsList/EmptyLabel
@onready var weapon_name: Label = $Panel/WeaponSection/WeaponInfo/WeaponDetails/WeaponName
@onready var ammo_label: Label = $Panel/WeaponSection/WeaponInfo/WeaponDetails/AmmoLabel
@onready var weapon_icon: TextureRect = $Panel/WeaponSection/WeaponInfo/WeaponIcon

var _open: bool = false
var _player: Node2D
var _item_containers: Dictionary = {}
var _button_normal: StyleBoxFlat
var _button_hover: StyleBoxFlat
var _button_disabled: StyleBoxFlat

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Obtener referencias
	_player = get_tree().get_first_node_in_group("player") as Node2D
	
	# Crear estilos de botones en código
	_button_normal = StyleBoxFlat.new()
	_button_normal.bg_color = Color(0.2, 0.22, 0.18, 1)
	_button_normal.border_width_left = 1
	_button_hover = StyleBoxFlat.new()
	_button_hover.bg_color = Color(0.3, 0.35, 0.28, 1)
	_button_hover.border_width_left = 1
	_button_hover.border_width_top = 1
	_button_hover.border_width_right = 1
	_button_hover.border_width_bottom = 1
	_button_hover.border_color = Color(0.5, 0.6, 0.45, 1)
	_button_disabled = StyleBoxFlat.new()
	_button_disabled.bg_color = Color(0.12, 0.12, 0.1, 1)
	_button_disabled.border_width_left = 1
	_button_disabled.border_width_top = 1
	_button_disabled.border_width_right = 1
	_button_disabled.border_width_bottom = 1
	_button_disabled.border_color = Color(0.2, 0.2, 0.18, 0.5)
	
	# Conectar señales
	Inventory.inventory_changed.connect(_refresh_ui)
	EventBus.player_hunger_changed.connect(_on_hunger_changed)
	
	# Inicialmente cerrado
	_set_visible(false)
	_refresh_ui()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("inventory"):
		if _open:
			close()
		else:
			open()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_TAB):
		if _open:
			close()
			get_viewport().set_input_as_handled()

func open() -> void:
	if _open:
		return
	_open = true
	_set_visible(true)
	_refresh_ui()
	
	# Bloquear movimiento/ataque del jugador
	if _player != null:
		_player.set("inventory_open", true)

func close() -> void:
	if not _open:
		return
	_open = false
	_set_visible(false)
	
	# Restaurar movimiento/ataque
	if _player != null:
		_player.set("inventory_open", false)

func _set_visible(visible: bool) -> void:
	background.visible = visible
	panel.visible = visible

func _refresh_ui() -> void:
	if not _open:
		return
	
	_refresh_weapon()
	_refresh_items()

func _refresh_weapon() -> void:
	var player = _player
	if player == null or not is_instance_valid(player):
		return
	
	var has_pistol: bool = player.get("has_pistol")
	var ammo: int = Inventory.count("pistol_ammo")
	
	if has_pistol:
		weapon_name.text = "Pistola 9mm"
		ammo_label.text = "Munición: %d" % ammo
	else:
		weapon_name.text = "Sin arma"
		ammo_label.text = "Munición: 0"

func _refresh_items() -> void:
	# Limpiar contenedores existentes
	for container in _item_containers.values():
		container.queue_free()
	_item_containers.clear()
	
	var items_data := {
		"comida": Inventory.count("comida"),
		"medkit": Inventory.count("medkit"),
		"pistol_ammo": Inventory.count("pistol_ammo"),
		"combustible": Inventory.count("combustible"),
	}
	
	var has_items: bool = false
	for item_id in items_data:
		var count: int = items_data[item_id]
		if count > 0:
			has_items = true
			_add_item_row(item_id, count)
	
	empty_label.visible = not has_items

func _add_item_row(item_id: String, count: int) -> void:
	var display_name: String = Inventory.display_name(item_id)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = 5  # KEEP
	
	var label := Label.new()
	label.text = "%s x%d" % [display_name, count]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.85, 1))
	
	var hbox_right := HBoxContainer.new()
	hbox_right.add_theme_constant_override("separation", 8)
	
	var eat_btn: Button = null
	if item_id == "comida":
		eat_btn = Button.new()
		eat_btn.text = "Comer"
		eat_btn.custom_minimum_size = Vector2(80, 32)
		eat_btn.add_theme_style_override("normal", _button_normal)
		eat_btn.add_theme_style_override("hover", _button_hover)
		eat_btn.add_theme_style_override("pressed", _button_hover)
		eat_btn.add_theme_style_override("disabled", _button_disabled)
		eat_btn.pressed.connect(_on_eat_pressed.bind(item_id))
		hbox_right.add_child(eat_btn)
	
	var hbox_main := HBoxContainer.new()
	hbox_main.add_child(label)
	hbox_main.add_child(hbox_right)
	
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	container.add_child(icon)
	container.add_child(hbox_main)
	
	if eat_btn:
		container.add_child(eat_btn)
	
	items_list.add_child(container)
	_item_containers[item_id] = container

func _on_eat_pressed(item_id: String) -> void:
	var player := _player
	if player == null or not is_instance_valid(player):
		return
	
	if player.get("hunger") >= player.get("max_hunger") - 5.0:
		EventBus.notification.emit("No tienes hambre")
		return
	
	if not Inventory.remove_item(item_id, 1):
		EventBus.notification.emit("No tienes %s" % Inventory.display_name(item_id))
		return
	
	player.call("use_food")
	_refresh_ui()

func _on_hunger_changed(hunger: float, max_hunger: float, warning_threshold: float) -> void:
	if _open:
		_refresh_items()