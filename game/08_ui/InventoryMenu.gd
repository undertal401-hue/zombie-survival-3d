extends CanvasLayer

## Menú de inventario interactivo - se abre/cierra con Tab
## No pausa el juego, solo bloquea inputs del jugador.
## Controles: click en botones, ↑↓ para elegir, Enter para usar,
## 1-6 para equipar arma, F comer, Q botiquín, R recargar, Tab/Escape cerrar.

const AMBER := Color(1.0, 0.78, 0.28, 1)
const BONE := Color(0.94, 0.91, 0.84, 1)
const DIM := Color(0.66, 0.68, 0.64, 0.95)
const ASH := Color(0.45, 0.48, 0.45, 0.9)
const BLOOD := Color(1.0, 0.45, 0.4, 1)
const DEFAULT_HINT := "↑↓ elegir · Enter usar · F Comer · Q Botiquín · R Recargar · 1-6 Arma · Tab/Esc cerrar"
const SHORTCUTS := {"comida": "F", "medkit": "Q", "pistol_ammo": "R"}

@onready var background: ColorRect = $Background
@onready var panel: Panel = $Panel
@onready var stats_label: Label = $Panel/StatsLabel
@onready var item_count: Label = $Panel/ItemsSection/Header/ItemCount
@onready var items_list: VBoxContainer = $Panel/ItemsSection/ItemsContainer/ItemsList
@onready var empty_label: Label = $Panel/ItemsSection/ItemsContainer/ItemsList/EmptyLabel
@onready var slots_row: HBoxContainer = $Panel/WeaponSection/SlotsRow
@onready var weapon_name: Label = $Panel/WeaponSection/WeaponInfo/WeaponDetails/WeaponName
@onready var ammo_label: Label = $Panel/WeaponSection/WeaponInfo/WeaponDetails/AmmoLabel
@onready var weapon_state: Label = $Panel/WeaponSection/WeaponInfo/WeaponDetails/WeaponState
@onready var reload_bar: ProgressBar = $Panel/WeaponSection/WeaponInfo/WeaponDetails/ReloadBar
@onready var weapon_icon: TextureRect = $Panel/WeaponSection/WeaponInfo/WeaponIcon
@onready var weapon_icon_missing: Label = $Panel/WeaponSection/WeaponInfo/WeaponIconMissing
@onready var eat_hint: Label = $Panel/EatHint
# Panel de crafting superpuesto a la lista: no altera las rutas ni la geometría
# de ItemsSection/ItemsContainer que comprueba el test 39.
@onready var craft_toggle: Button = $Panel/ItemsSection/Header/CraftToggle
@onready var craft_section: Panel = $Panel/ItemsSection/CraftSection
@onready var craft_rows: VBoxContainer = $Panel/ItemsSection/CraftSection/CraftRows

var _open: bool = false
var _player: Node2D
var _item_containers: Dictionary = {}
var _action_buttons: Array[Button] = []
var _craft_containers: Array[Node] = []
var _slot_buttons: Array[Button] = []
var _selected_index: int = -1
var _message_timer: float = 0.0
var _last_hp: float = -1.0

var _button_normal: StyleBoxFlat
var _button_hover: StyleBoxFlat
var _button_pressed: StyleBoxFlat
var _button_disabled: StyleBoxFlat
var _button_focus: StyleBoxFlat
var _button_active: StyleBoxFlat
var _row_style: StyleBoxFlat
var _panel_normal: StyleBoxFlat
var _panel_critical: StyleBoxFlat

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_player = get_tree().get_first_node_in_group("player") as Node2D

	_button_normal = _make_style(Color(0.1, 0.11, 0.1, 1), Color(0.3, 0.26, 0.2, 0.85), 1)
	_button_hover = _make_style(Color(0.2, 0.18, 0.13, 1), Color(1.0, 0.78, 0.28, 0.75), 1)
	_button_pressed = _make_style(Color(1, 0.78, 0.28, 0.2), AMBER, 2)
	_button_disabled = _make_style(Color(0.05, 0.055, 0.05, 0.9), Color(0.3, 0.26, 0.2, 0.35), 1)
	_button_focus = _make_style(Color(0.26, 0.21, 0.1, 1), AMBER, 2)
	_button_active = _make_style(Color(0.3, 0.24, 0.1, 1), AMBER, 2)
	_row_style = _make_style(Color(0.085, 0.095, 0.09, 0.92), Color(0.3, 0.26, 0.2, 0.9), 1, 10, 6, 10, 6)
	_row_style.border_width_left = 3

	var shell := panel.get_theme_stylebox("panel")
	if shell is StyleBoxFlat:
		_panel_normal = shell as StyleBoxFlat
		_panel_critical = _panel_normal.duplicate() as StyleBoxFlat
		_panel_critical.bg_color = Color(0.055, 0.03, 0.03, 0.97)
		_panel_critical.border_color = Color(0.72, 0.18, 0.18, 0.95)

	_build_slot_buttons()
	Inventory.inventory_changed.connect(_refresh_ui)
	Inventory.crafting_completed.connect(_on_craft_completed)
	if craft_toggle != null:
		craft_toggle.pressed.connect(toggle_crafting)
	EventBus.player_hunger_changed.connect(_on_hunger_changed)
	# El inventario no debe quedarse abierto sobre la pantalla de fin.
	EventBus.game_over.connect(close)
	EventBus.victory.connect(close)

	if _player != null and is_instance_valid(_player):
		var wc: WeaponController = _player.get_node_or_null("WeaponController") as WeaponController
		if wc != null:
			wc.weapon_changed.connect(func(_w: Weapon): _refresh_weapon())
			wc.ammo_changed.connect(func(_c: int, _t: int, _ch: int): _refresh_weapon())
			wc.reloading_started.connect(func(_w: Weapon, _d: float): _refresh_weapon())
			wc.reloading_finished.connect(func(_w: Weapon): _on_reload_finished())
			wc.dry_fire.connect(func(_w: Weapon): _show_message("¡Cargador vacío! Pulsa R para recargar"))

	_set_visible(false)

func _category_color(category: int) -> Color:
	match category:
		Weapon.Category.PISTOL: return Color(1.0, 0.85, 0.45, 1)
		Weapon.Category.SHOTGUN: return Color(1.0, 0.6, 0.35, 1)
		Weapon.Category.RIFLE: return Color(0.6, 0.9, 0.6, 1)
		Weapon.Category.HEAVY: return Color(1.0, 0.45, 0.4, 1)
		Weapon.Category.MELEE: return Color(0.8, 0.8, 0.86, 1)
		Weapon.Category.TOOL: return Color(0.86, 0.72, 0.48, 1)
		_: return Color(0.8, 0.8, 0.8, 1)

func _make_style(bg: Color, border: Color, width: int,
		ml: float = 8.0, mt: float = 4.0, mr: float = 8.0, mb: float = 4.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.border_color = border
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	style.content_margin_left = ml
	style.content_margin_top = mt
	style.content_margin_right = mr
	style.content_margin_bottom = mb
	return style

func _style_button(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(78, 30)
	btn.add_theme_stylebox_override("normal", _button_normal)
	btn.add_theme_stylebox_override("hover", _button_hover)
	btn.add_theme_stylebox_override("pressed", _button_pressed)
	btn.add_theme_stylebox_override("disabled", _button_disabled)
	btn.add_theme_stylebox_override("focus", _button_focus)
	btn.add_theme_color_override("font_color", Color(0.86, 0.86, 0.81, 1))
	btn.add_theme_color_override("font_hover_color", AMBER)
	btn.add_theme_color_override("font_focus_color", AMBER)
	btn.add_theme_color_override("font_pressed_color", Color(1, 0.95, 0.8, 1))
	btn.add_theme_color_override("font_disabled_color", Color(0.38, 0.4, 0.37, 1))
	btn.add_theme_font_size_override("font_size", 13)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

func _build_slot_buttons() -> void:
	for slot in range(WeaponController.LOADOUT_SLOT_COUNT):
		var btn := Button.new()
		btn.text = "—"
		_style_button(btn)
		btn.pressed.connect(_on_slot_pressed.bind(slot))
		slots_row.add_child(btn)
		_slot_buttons.append(btn)

## Tras game over/victoria el árbol está pausado, pero este menú usa
## PROCESS_MODE_ALWAYS y seguiría abriendo el inventario sobre la pantalla final.
func _game_ended() -> bool:
	if get_tree().paused:
		return true
	return _player != null and is_instance_valid(_player) and bool(_player.get("is_dead"))

func _input(event: InputEvent) -> void:
	if _game_ended():
		return  # no marcar handled: HUD necesita R para reiniciar
	# Toda la entrada se intercepta en _input (antes del GUI del viewport):
	# si un botón tiene foco, el viewport consumiría ui_up/ui_down/ui_accept y
	# _unhandled_input nunca vería las flechas ni Enter.
	if not _open:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_TAB or event.keycode == KEY_ESCAPE:
				open()
				get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_up"):
		_move_selection(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		_activate_selection()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB, KEY_ESCAPE:
				close()
			KEY_F:
				_on_use_pressed("comida")
			KEY_Q:
				_on_use_pressed("medkit")
			KEY_R:
				_on_reload_pressed()
			KEY_C:
				toggle_crafting()
			_:
				if event.keycode < KEY_1 or event.keycode > KEY_6:
					return
				_on_slot_pressed(event.keycode - KEY_1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var scroll: ScrollContainer = $Panel/ItemsSection/ItemsContainer
		# get_vertical_scroll_length() ya no existe en Godot 4.7: el rango real
		# está en la barra vertical (max_value = contenido - viewport).
		var max_scroll: float = scroll.get_v_scroll_bar().max_value
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll.scroll_vertical = clampf(scroll.scroll_vertical - 32.0, 0.0, max_scroll)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll.scroll_vertical = clampf(scroll.scroll_vertical + 32.0, 0.0, max_scroll)
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _open:
		return
	_refresh_stats()

	if _message_timer > 0.0:
		_message_timer = maxf(_message_timer - delta, 0.0)
		if _message_timer == 0.0:
			eat_hint.text = DEFAULT_HINT
			eat_hint.add_theme_color_override("font_color", DIM)

	var wc: WeaponController = _get_controller()
	if wc != null and wc.current_weapon != null and wc.current_weapon.is_reloading:
		reload_bar.value = wc.current_weapon.get_reload_progress()
		weapon_state.text = "RECARGANDO %d%%" % int(reload_bar.value * 100.0)
		weapon_state.add_theme_color_override("font_color", AMBER)

func _get_controller() -> WeaponController:
	if _player == null or not is_instance_valid(_player):
		return null
	return _player.get_node_or_null("WeaponController") as WeaponController

func open() -> void:
	if _open or _game_ended():
		return
	_open = true
	_set_visible(true)
	_refresh_ui()

	if _player != null and is_instance_valid(_player):
		_player.inventory_open = true
	_highlight_selection()

func close() -> void:
	if not _open:
		return
	_open = false
	_set_visible(false)
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null:
		owner.release_focus()

	if _player != null and is_instance_valid(_player):
		_player.inventory_open = false

func _set_visible(value: bool) -> void:
	background.visible = value
	panel.visible = value

func _refresh_ui() -> void:
	_refresh_stats()
	_refresh_weapon()
	_refresh_items()
	_refresh_crafting()

func _refresh_stats() -> void:
	if stats_label == null or _player == null or not is_instance_valid(_player):
		return
	var hp: int = int(round(_player.hp))
	var hunger: int = int(round(_player.hunger))
	var critical: bool = _player.hp <= 100.0 * 0.25
	var critical_tag: String = "  ¡CRÍTICO!" if critical else ""
	stats_label.text = "VIDA %d%s   ·   AGUANTE %d   ·   HAMBRE %d   ·   CARGA %.1f/%.0f kg" % [
		hp, critical_tag, int(round(_player.stamina)), hunger,
		Inventory.current_weight(), Inventory.max_weight()
	]
	if _panel_normal != null and _panel_critical != null:
		panel.add_theme_stylebox_override("panel", _panel_critical if critical else _panel_normal)
	if _last_hp >= 0.0 and _player.hp > _last_hp + 0.5:
		var tween := create_tween()
		tween.tween_property(stats_label, "modulate", Color(0.65, 1.0, 0.65, 1), 0.12)
		tween.tween_property(stats_label, "modulate", Color(1, 1, 1, 1), 0.28)
	_last_hp = _player.hp

func _refresh_weapon() -> void:
	var wc: WeaponController = _get_controller()
	var w: Weapon = wc.current_weapon if wc != null else null

	if w == null:
		weapon_name.text = "Sin arma equipada"
		weapon_icon.texture = null
		weapon_icon.visible = false
		if weapon_icon_missing != null:
			weapon_icon_missing.visible = false
		ammo_label.text = "Pulsa 1-6 para equipar un arma"
		weapon_state.text = "SIN ARMA"
		weapon_state.add_theme_color_override("font_color", ASH)
		reload_bar.visible = false
	else:
		weapon_name.text = w.weapon_name
		# Solo se presenta un Texture2D oficial. Si falta, el inventario declara
		# el asset pendiente; nunca fabrica un icono procedural de relleno.
		var resolved_icon: Texture2D = w.icon
		if resolved_icon == null:
			resolved_icon = Inventory.get_item_texture(w.weapon_name)
		weapon_icon.texture = resolved_icon
		weapon_icon.modulate = _category_color(w.category)
		weapon_icon.visible = resolved_icon != null
		if weapon_icon_missing != null:
			weapon_icon_missing.visible = resolved_icon == null
			weapon_icon_missing.text = "FALTA ASSET - NO INVENTAR"

		if w.category == Weapon.Category.MELEE or w.category == Weapon.Category.TOOL:
			if w.category == Weapon.Category.TOOL:
				ammo_label.text = "Sin munición · herramienta de tala"
				weapon_state.text = "DAÑO %d · TALAR ÁRBOLES · COSTE 20 AGUANTE" % int(w.base_damage)
				weapon_state.add_theme_color_override("font_color", Color(0.86, 0.72, 0.48, 1))
			else:
				ammo_label.text = "Sin munición · cuerpo a cuerpo"
				weapon_state.text = "DAÑO %d · COSTE 20 AGUANTE · SILENCIOSA" % int(w.base_damage)
				weapon_state.add_theme_color_override("font_color", Color(0.8, 0.8, 0.86, 1))
			reload_bar.visible = false
		else:
			var ammo_key: String = w.ammo_type if w.ammo_type != "" else "pistol_ammo"
			var reserve: int = Inventory.count(ammo_key)
			ammo_label.text = "Recámara %d · Cargador %d · Reserva %d" % [
				w.ammo_in_chamber, w.current_ammo, reserve
			]
			if w.is_reloading:
				weapon_state.text = "RECARGANDO %d%%" % int(w.get_reload_progress() * 100.0)
				weapon_state.add_theme_color_override("font_color", AMBER)
			elif w.get_total_ammo() <= 0:
				weapon_state.text = "¡VACÍA! PULSA R · RESERVA %d" % reserve
				weapon_state.add_theme_color_override("font_color", BLOOD)
			elif w.get_total_ammo() <= maxi(1, int(ceil(w.get_max_ammo() * 0.25))):
				weapon_state.text = "POCA MUNICIÓN · %d/%d" % [w.get_total_ammo(), w.get_max_ammo()]
				weapon_state.add_theme_color_override("font_color", Color(1, 0.72, 0.4, 1))
			else:
				weapon_state.text = "LISTA · %d/%d" % [w.get_total_ammo(), w.get_max_ammo()]
				weapon_state.add_theme_color_override("font_color", Color(0.72, 0.9, 0.72, 1))
			reload_bar.visible = w.is_reloading
			reload_bar.value = w.get_reload_progress() if w.is_reloading else 0.0

	for slot in range(_slot_buttons.size()):
		var btn: Button = _slot_buttons[slot]
		var slot_weapon: Weapon = wc.get_weapon_in_slot(slot) if wc != null else null
		btn.text = slot_weapon.weapon_name.substr(0, 10) if slot_weapon != null else "—"
		btn.disabled = slot_weapon == null
		if slot_weapon != null:
			btn.tooltip_text = "%d · %s" % [slot + 1, slot_weapon.weapon_name]
		else:
			btn.tooltip_text = "%d · vacío" % (slot + 1)
		btn.add_theme_stylebox_override("normal", _button_active if slot == current_slot(wc) else _button_normal)

func current_slot(wc: WeaponController) -> int:
	return wc.current_slot if wc != null else -1

func _item_availability(item_id: String) -> Dictionary:
	if _player == null or not is_instance_valid(_player):
		return {"ok": false, "reason": ""}
	match item_id:
		"comida":
			if _player.hunger >= _player.max_hunger - 5.0:
				return {"ok": false, "reason": "Hambre llena"}
		"medkit":
			if _player.hp >= 100.0:
				return {"ok": false, "reason": "Vida llena"}
		"pistol_ammo":
			var wc: WeaponController = _get_controller()
			if wc == null or wc.get_weapon_in_slot(1) == null:
				return {"ok": false, "reason": "Sin pistola"}
			if wc.current_weapon != null and wc.current_weapon.is_reloading:
				return {"ok": false, "reason": "Recargando"}
	return {"ok": true, "reason": ""}

func _refresh_items() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and _action_buttons.has(focus_owner):
		focus_owner.release_focus()

	# queue_free(): free() inmediato puede destruir un botón mientras emite
	# `pressed`. Las filas stale venían del rebuild por hambre (ya corregido).
	for container in _item_containers.values():
		if is_instance_valid(container):
			container.queue_free()
	_item_containers.clear()
	_action_buttons.clear()

	var items_data := {
		"comida": Inventory.count("comida"),
		"medkit": Inventory.count("medkit"),
		"pistol_ammo": Inventory.count("pistol_ammo"),
		"combustible": Inventory.count("combustible"),
		"vehicle_fuel": Inventory.count("vehicle_fuel"),
		"scrap": Inventory.count("scrap"),
		"cloth": Inventory.count("cloth"),
		"wood": Inventory.count("wood"),
	}
	var has_items: bool = false
	for item_id in items_data:
		var count: int = items_data[item_id]
		if count > 0:
			has_items = true
			_add_item_row(item_id, count)

	empty_label.visible = not has_items
	item_count.text = "%d TIPOS" % _visible_item_types(items_data)
	_selected_index = clampi(_selected_index, -1, _action_buttons.size() - 1)
	_highlight_selection()

func _visible_item_types(items_data: Dictionary) -> int:
	var n: int = 0
	for v in items_data.values():
		if int(v) > 0:
			n += 1
	return n

func _add_item_row(item_id: String, count: int) -> void:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", _row_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	container.add_child(hbox)

	var label := Label.new()
	label.text = "%s ×%d" % [Inventory.display_name(item_id), count]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", BONE)
	hbox.add_child(label)

	var action_text: String = {"comida": "Comer", "medkit": "Usar", "pistol_ammo": "Recargar"}.get(item_id, "")
	if action_text == "":
		# Materiales y bidones son información de progreso: no botones vacíos.
		var badge := Label.new()
		if item_id == "combustible":
			badge.text = "OBJETIVO %d/3" % count
		else:
			badge.text = Inventory.get_category(item_id).to_upper()
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_color_override("font_color", AMBER)
		hbox.add_child(badge)
	else:
		var shortcut: String = SHORTCUTS.get(item_id, "")
		if shortcut != "":
			var keycap := Label.new()
			keycap.text = "[%s]" % shortcut
			keycap.add_theme_font_size_override("font_size", 13)
			keycap.add_theme_color_override("font_color", AMBER)
			hbox.add_child(keycap)

		# `btn.text` se mantiene EXACTO: los tests lo comparan por igualdad.
		var btn := Button.new()
		btn.text = action_text
		_style_button(btn)
		var avail: Dictionary = _item_availability(item_id)
		btn.disabled = not bool(avail.get("ok", false))
		btn.tooltip_text = String(avail.get("reason", "")) if btn.disabled else "Pulsa %s o click" % shortcut
		match item_id:
			"comida", "medkit": btn.pressed.connect(_on_use_pressed.bind(item_id))
			"pistol_ammo": btn.pressed.connect(_on_reload_pressed)
		hbox.add_child(btn)
		if not btn.disabled:
			_action_buttons.append(btn)

	items_list.add_child(container)
	_item_containers[item_id] = container

func _move_selection(direction: int) -> void:
	if _action_buttons.is_empty():
		return
	if _selected_index < 0:
		_selected_index = 0 if direction > 0 else _action_buttons.size() - 1
	else:
		_selected_index = wrapi(_selected_index + direction, 0, _action_buttons.size())
	_highlight_selection()

func _highlight_selection() -> void:
	if _selected_index < 0 or _selected_index >= _action_buttons.size():
		return
	var btn: Button = _action_buttons[_selected_index]
	if is_instance_valid(btn) and btn.is_inside_tree() and not btn.disabled:
		btn.grab_focus()

func _activate_selection() -> void:
	if _selected_index < 0 or _selected_index >= _action_buttons.size():
		return
	var btn: Button = _action_buttons[_selected_index]
	if is_instance_valid(btn) and not btn.disabled:
		btn.pressed.emit()

func _on_slot_pressed(slot: int) -> void:
	var wc: WeaponController = _get_controller()
	if wc == null or slot < 0 or slot >= wc.weapons.size() or wc.weapons[slot] == null:
		return
	wc._equip_slot(slot)
	_refresh_ui()
	_show_message("Equipado: %s [%d]" % [wc.weapons[slot].weapon_name, slot + 1])
	var btn: Button = _slot_buttons[slot] if slot < _slot_buttons.size() else null
	if btn != null:
		btn.modulate = Color(1.4, 1.2, 0.7, 1)
		var tween := create_tween()
		tween.tween_property(btn, "modulate", Color(1, 1, 1, 1), 0.24)

func _on_use_pressed(item_id: String) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var used: bool = false
	match item_id:
		"comida": used = _player.use_food()
		"medkit": used = _player.use_medkit()
	if used:
		_refresh_ui()
		var label: String = "Comida" if item_id == "comida" else "Botiquín"
		_show_message("Usado: %s" % label)
	else:
		_show_message("No se puede usar ahora")

func _on_eat_pressed(item_id: String) -> void:
	_on_use_pressed(item_id)

func _on_reload_pressed() -> void:
	var wc: WeaponController = _get_controller()
	if wc == null:
		return
	if wc.current_weapon == null or wc.current_weapon.ammo_type != "pistol_ammo":
		if wc.get_weapon_in_slot(1) == null:
			_show_message("Sin pistola para recargar")
			return
		wc._equip_slot(1)
	if wc.current_weapon == null or wc.current_weapon.ammo_type != "pistol_ammo":
		return
	if wc.current_weapon.is_reloading:
		_show_message("Ya se está recargando")
		return
	if wc.current_weapon.get_total_ammo() >= wc.current_weapon.get_max_ammo():
		_show_message("Cargador lleno")
		return
	wc._start_reload()
	_refresh_ui()
	_show_message("Recargando %s..." % wc.current_weapon.weapon_name)

func _on_reload_finished() -> void:
	_refresh_weapon()
	_show_message("Recarga completada")

func _show_message(text: String) -> void:
	if not _open:
		return
	eat_hint.text = text
	eat_hint.add_theme_color_override("font_color", AMBER)
	_message_timer = 2.2

func _on_hunger_changed(_hunger: float, _max_hunger: float, _warning_threshold: float) -> void:
	# La hambre cambia cada frame: reconstruir las filas aquí duplicaba botones
	# (queue_free es diferido) y robaba el foco. Solo se actualizan las cifras.
	if _open:
		_refresh_stats()

# ---------------------------------------------------------------------------
# Crafting (panel superpuesto, sin tocar ItemsContainer ni SlotsRow)
# ---------------------------------------------------------------------------

func toggle_crafting() -> void:
	if craft_section == null:
		return
	craft_section.visible = not craft_section.visible
	if craft_toggle != null:
		craft_toggle.text = "Cerrar" if craft_section.visible else "Crafteo"
		craft_toggle.tooltip_text = "Cerrar panel de crafting [C]" if craft_section.visible else "Abrir panel de crafting [C]"
	_refresh_crafting()

func _refresh_crafting() -> void:
	if craft_rows == null or craft_section == null or not craft_section.visible:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		for btn in _craft_containers:
			if is_instance_valid(btn) and btn == focus_owner:
				focus_owner.release_focus()
				break
	for container in _craft_containers:
		if is_instance_valid(container):
			container.queue_free()
	_craft_containers.clear()

	var recipes: Dictionary = Inventory.get_recipes()
	for recipe_id in recipes:
		var recipe: Dictionary = recipes[recipe_id]
		var container := PanelContainer.new()
		container.add_theme_stylebox_override("panel", _row_style)
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		container.add_child(hbox)

		var label := Label.new()
		var output: String = String(recipe.get("output", recipe_id))
		var amount: int = int(recipe.get("amount", 1))
		label.text = "%s ×%d  ·  %s" % [
			Inventory.display_name(output), amount, Inventory.recipe_cost_text(recipe_id)
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", BONE)
		hbox.add_child(label)

		var btn := Button.new()
		# Texto estable y distinto de Comer/Usar/Recargar (tests lo buscan).
		btn.text = "Fabricar"
		_style_button(btn)
		btn.custom_minimum_size = Vector2(74, 26)
		var check: Dictionary = Inventory.can_craft(recipe_id)
		btn.disabled = not bool(check.get("ok", false))
		btn.tooltip_text = String(check.get("reason", "")) if btn.disabled else "Fabricar %s (atajo C para abrir)" % Inventory.display_name(output)
		btn.pressed.connect(_on_craft_pressed.bind(recipe_id))
		hbox.add_child(btn)

		craft_rows.add_child(container)
		_craft_containers.append(container)

func _on_craft_pressed(recipe_id: String) -> void:
	if not Inventory.craft(recipe_id):
		var check: Dictionary = Inventory.can_craft(recipe_id)
		_show_message(String(check.get("reason", "No se puede fabricar")))
	_refresh_ui()

func _on_craft_completed(item_id: String, amount: int) -> void:
	_show_message("Fabricado: %s ×%d" % [Inventory.display_name(item_id), amount])
	_refresh_ui()
