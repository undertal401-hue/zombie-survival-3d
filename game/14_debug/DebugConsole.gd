extends Control
## Consola de desarrollador: comandos, logs, inspectors.

const MAX_HISTORY: int = 200

var output: RichTextLabel = null
var input: LineEdit = null
var container: VBoxContainer = null

var _visible: bool = false
var _history: Array = []
var _history_index: int = -1
var _commands: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_ensure_ui()
	_register_commands()
	EventBus.debug_command_executed.connect(_on_command_result)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## Construye la interfaz de la consola por codigo si no existe (autoload sin escena).
func _ensure_ui() -> void:
	output = get_node_or_null("%Output") as RichTextLabel
	input = get_node_or_null("%Input") as LineEdit
	container = get_node_or_null("%Container") as VBoxContainer
	if output != null and input != null and container != null:
		if not input.text_submitted.is_connected(_on_input_submitted):
			input.text_submitted.connect(_on_input_submitted)
		return
	container = VBoxContainer.new()
	container.name = "Container"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	output = RichTextLabel.new()
	output.name = "Output"
	output.bbcode_enabled = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(output)
	input = LineEdit.new()
	input.name = "Input"
	input.placeholder_text = "comando..."
	input.text_submitted.connect(_on_input_submitted)
	container.add_child(input)


func _process(_delta: float) -> void:
	if Input.is_key_pressed(KEY_QUOTELEFT) or Input.is_key_pressed(KEY_F1):
		_toggle()


func _toggle() -> void:
	_visible = not _visible
	visible = _visible
	if _visible:
		if input != null:
			input.grab_focus()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if input != null:
			input.release_focus()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_input_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	_execute(text)
	_history.append(text)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_history_index = -1
	input.clear()


func _execute(command: String) -> void:
	var args = command.split(" ", false, true)
	var cmd = args[0].to_lower()
	args = args.slice(1, args.size())
	if _commands.has(cmd):
		var callback = _commands[cmd]
		callback.call(args)
	else:
		_log("Comando desconocido: %s. Usa 'help'." % cmd, &"error")
	EventBus.debug_command_executed.emit(cmd, args)


func _register_commands() -> void:
	_commands["help"] = _cmd_help.bind()
	_commands["god"] = _cmd_god.bind()
	_commands["killall"] = _cmd_killall.bind()
	_commands["spawn"] = _cmd_spawn.bind()
	_commands["wave"] = _cmd_wave.bind()
	_commands["coins"] = _cmd_coins.bind()
	_commands["heal"] = _cmd_heal.bind()
	_commands["infect"] = _cmd_infect.bind()
	_commands["weapon"] = _cmd_weapon.bind()
	_commands["upgrade"] = _cmd_upgrade.bind()
	_commands["teleport"] = _cmd_teleport.bind()
	_commands["timescale"] = _cmd_timescale.bind()
	_commands["stats"] = _cmd_stats.bind()
	_commands["pool"] = _cmd_pool.bind()
	_commands["clear"] = _cmd_clear.bind()


func _cmd_help(_args) -> void:
	_log("Comandos disponibles:", &"info")
	_log("  help            - Muestra esta ayuda", &"info")
	_log("  god             - Invencibilidad", &"info")
	_log("  killall         - Mata todos los zombies", &"info")
	_log("  spawn <tipo>    - Spawnea un zombie", &"info")
	_log("  wave <n>        - Salta a oleada n", &"info")
	_log("  coins <n>       - Anade monedas", &"info")
	_log("  heal <n>        - Cura vida", &"info")
	_log("  infect <n>      - Anade infeccion", &"info")
	_log("  weapon <id>     - Da arma", &"info")
	_log("  upgrade <tipo>  - Mejora permanente", &"info")
	_log("  teleport <x> <y> <z> - Teletransporta", &"info")
	_log("  timescale <n>   - Cambia velocidad juego", &"info")
	_log("  stats           - Muestra stats", &"info")
	_log("  pool            - Info de pools", &"info")
	_log("  clear           - Limpia consola", &"info")


func _cmd_god(_args) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player != null:
		player.stats.hp = player.stats.max_hp
		player.stats.infection = 0.0
		_log("Modo dios activado", &"reward")


func _cmd_killall(_args) -> void:
	var DamageInfo = load("res://05_combat/DamageInfo.gd")
	var player = get_tree().get_first_node_in_group("player")
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie = node
		if zombie != null and zombie.has_method("take_damage"):
			var info = DamageInfo.make(9999.0, DamageInfo.DamageType.EXPLOSION, player)
			zombie.take_damage(info)
	_log("Todos los zombies eliminados", &"reward")


func _cmd_spawn(args) -> void:
	if args.is_empty():
		_log("Uso: spawn <tipo>", &"warning")
		return
	var type_name = args[0]
	var spawner = get_tree().get_first_node_in_group("zombie_spawner")
	if spawner != null:
		var player = get_tree().get_first_node_in_group("player")
		if player != null:
			var pos = player.global_position + Vector3(5.0, 0.0, 0.0)
			var zombie = spawner.pool.acquire(type_name, 1.0, 1.0, 1.0)
			if zombie != null:
				get_tree().current_scene.add_child(zombie)
				zombie.global_position = pos
				spawner.alive.append(zombie)
				_log("Spawneado: %s" % type_name, &"reward")


func _cmd_wave(args) -> void:
	if args.is_empty():
		_log("Uso: wave <numero>", &"warning")
		return
	var wave = args[0].to_int()
	var wm: Node = get_tree().root.get_node_or_null("WaveManager")
	if wm == null:
		_log("WaveManager no disponible", &"error")
		return
	wm.call("start_wave", wave)
	_log("Saltando a oleada %d" % wave, &"reward")


func _cmd_coins(args) -> void:
	var amount = args[0].to_int() if not args.is_empty() else 1000
	Currency.add(amount, &"cheat")
	_log("Anadidas %d monedas" % amount, &"reward")


func _cmd_heal(args) -> void:
	var amount = args[0].to_float() if not args.is_empty() else 100.0
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("heal"):
		player.heal(amount)
		_log("Curado %.0f HP" % amount, &"reward")


func _cmd_infect(args) -> void:
	var amount = args[0].to_float() if not args.is_empty() else 50.0
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("get_stats"):
		player.get_stats().add_infection(amount)
		_log("Infeccion +%.0f%%" % amount, &"warning")


func _cmd_weapon(args) -> void:
	if args.is_empty():
		_log("Uso: weapon <id>", &"warning")
		return
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.inventory != null:
		var WeaponData = load("res://04_weapons/WeaponData.gd")
		var weapon_data = WeaponData.catalog().find(func(w): return w.weapon_id == args[0])
		if weapon_data != null:
			var weapon_class = load("res://04_weapons/%s.gd" % ("MeleeWeapon" if weapon_data.slot_type == 2 else "RangedWeapon"))
			var weapon = weapon_class.new()
			weapon.data = weapon_data
			player.inventory.add_weapon(weapon)
			_log("Arma dada: %s" % args[0], &"reward")
		else:
			_log("Arma no encontrada", &"error")


func _cmd_upgrade(args) -> void:
	if args.is_empty():
		_log("Uso: upgrade <damage|speed|jump>", &"warning")
		return
	var player = get_tree().get_first_node_in_group("player")
	if player != null:
		var kind := StringName(args[0])
		var amount: float = 0.05 if kind == &"damage" else 0.03 if kind == &"speed" else 0.10
		player.get_stats().apply_permanent_upgrade(kind, amount)
		var PermanentUpgrade = load("res://11_items/PermanentUpgrade.gd")
		var upgrade = PermanentUpgrade.new()
		upgrade.kind = kind
		upgrade.amount = amount
		var save_system: Node = get_tree().root.get_node_or_null("SaveSystem")
		if save_system != null:
			save_system.call("record_permanent_upgrade", upgrade)
		_log("Mejora aplicada: %s" % kind, &"reward")


func _cmd_teleport(args) -> void:
	if args.size() < 3:
		_log("Uso: teleport <x> <y> <z>", &"warning")
		return
	var player = get_tree().get_first_node_in_group("player")
	if player != null:
		player.global_position = Vector3(args[0].to_float(), args[1].to_float(), args[2].to_float())
		_log("Teletransportado", &"reward")


func _cmd_timescale(args) -> void:
	if args.is_empty():
		_log("Uso: timescale <0.1-4.0>", &"warning")
		return
	var scale = args[0].to_float()
	GameClock.set_time_scale(scale)
	_log("Time scale: %.2f" % scale, &"info")


func _cmd_stats(_args) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("get_stats"):
		var s = player.get_stats()
		_log("HP: %.0f/%.0f | Stam: %.0f/%.0f | Inf: %.0f%% | Coins: %d" % [s.hp, s.max_hp, s.stamina, s.max_stamina, s.infection, s.coins], &"info")


func _cmd_pool(_args) -> void:
	var spawner = get_tree().get_first_node_in_group("zombie_spawner")
	if spawner != null and spawner.has_method("pool_report"):
		var report = spawner.pool_report()
		for type_name in report:
			var r = report[type_name]
			_log("Pool %s: total=%d active=%d avail=%d" % [type_name, r.total, r.active, r.available], &"info")


func _cmd_clear(_args) -> void:
	if output != null:
		output.clear()


func _log(text: String, tone: StringName) -> void:
	if output == null:
		return
	var color = "#FFFFFF"
	match tone:
		&"warning": color = "#FFA500"
		&"error": color = "#FF4444"
		&"reward": color = "#44FF88"
	output.append_text("[%s] %s\n" % [tone, text])
	output.scroll_to_end()


func _on_command_result(command: String, args: Array) -> void:
	_log("> %s %s" % [command, " ".join(args)], &"info")
