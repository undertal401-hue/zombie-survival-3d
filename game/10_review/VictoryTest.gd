extends Node
## ============================================================================
## VICTORY TEST (R1) — contrato del FLUJO DE VICTORIA por extracción.
## ============================================================================
## Este arnés estaba OBSOLETO desde la Capa 2/3 y salía "RESULT: FAIL" sin
## romper nada (nunca estuvo en el CI y terminaba con quit(0) pase lo que
## pasase). Las dos razones del FAIL eran reales:
##
##   1. Miraba el `EndOverlay` del HUD y exigía el título "EXITOSA", pero la
##      Capa 3 movió la victoria a una pantalla DEDICADA (GameOver.tscn,
##      CanvasLayer 30) y el HUD solo conserva el overlay histórico.
##   2. La extracción ya no es instantánea: ExtractionZone tiene una cuenta
##      atrás de EXTRACTION_COUNTDOWN = 12 s (ÍTEM 14). El arnés solo esperaba
##      6 frames físicos (~0,1 s), así que la victoria NUNCA llegaba a dispararse.
##
## R1 lo reescribe como compuerta real: comprueba el flujo completo con el
## countdown acelerado, las dos superficies de victoria (HUD + GameOver) y que
## los botones de la pantalla de fin siguen procesando input con el árbol
## pausado.
## ============================================================================

const MAIN_SCENE: String = "res://07_house/Main.tscn"
const EXTRACTION_SCENE: String = "res://04_items/ExtractionZone.gd"

var _failures: Array[String] = []
var _victory_fired: bool = false
var _game_over_fired: bool = false

func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)

func _info(label: String) -> void:
	print("INFO " + label)

func _read(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	return ""

func _ready() -> void:
	await get_tree().process_frame
	EventBus.victory.connect(func() -> void: _victory_fired = true)
	EventBus.game_over.connect(func() -> void: _game_over_fired = true)

	var main: Node = load(MAIN_SCENE).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for i in range(20):
		await get_tree().process_frame
	if main.has_method("skip_menu"):
		main.call("skip_menu")
	for i in range(20):
		await get_tree().process_frame

	var player: Node2D = main.get_node_or_null("Player") as Node2D
	var extraction: Node2D = main.get_node_or_null("Extraction") as Node2D
	var hud: Node = main.get_node_or_null("HUD") as Node
	_check(player != null, "Main tiene al jugador")
	_check(extraction != null, "Main tiene la zona de extracción")
	_check(hud != null, "Main tiene el HUD")
	if player == null or extraction == null or hud == null:
		await _finish()
		return

	# --- 1. El objetivo de extracción exige 3 bidones ------------------------
	var inv: Node = get_node_or_null("/root/Inventory")
	_check(inv != null, "Inventory es un autoload")
	if inv == null:
		await _finish()
		return
	inv.call("clear")
	inv.call("add_item", "combustible", 3)
	await get_tree().process_frame
	_check(int(inv.call("count", "combustible")) == 3,
		"el jugador lleva 3 bidones de combustible")

	# --- 2. Entrar en la zona arranca la cuenta atrás (no victoria directa) ---
	player.global_position = extraction.global_position
	var countdown_started: bool = false
	for i in range(20):
		await get_tree().physics_frame
		await get_tree().process_frame
		var current: Variant = extraction.get("_countdown")
		if current is float or current is int:
			if float(current) >= 0.0:
				countdown_started = true
				break
	_check(countdown_started,
		"entrar en la zona con 3 bidones arranca la cuenta atrás de extracción")
	_check(not _victory_fired,
		"entrar en la zona NO da la victoria al instante (ÍTEM 14)")

	# --- 3. Acelerar la cuenta atrás para que el arnés no tarde 12 s ---------
	extraction.set("_countdown", 0.0)
	for i in range(20):
		await get_tree().physics_frame
		await get_tree().process_frame
		if _victory_fired:
			break
	_check(_victory_fired, "al terminar la cuenta atrás se emite EventBus.victory")
	_check(not _game_over_fired, "la extracción no dispara game_over")

	# --- 4. Superficie 1: el overlay histórico del HUD -----------------------
	var end_overlay: CanvasItem = hud.get_node_or_null("EndOverlay") as CanvasItem
	var end_title: Label = hud.get_node_or_null("EndOverlay/EndPanel/EndTitle") as Label
	_check(end_overlay != null, "el HUD conserva el EndOverlay histórico")
	_check(end_title != null, "el EndOverlay tiene EndTitle")
	if end_overlay != null:
		_check(end_overlay.visible, "el EndOverlay del HUD se muestra al ganar")
	if end_title != null:
		_info("título de victoria: %s" % end_title.text)
		_check(end_title.text.contains("EXTRACCIÓN"),
			"el título de victoria usa la grafía 'EXTRACCIÓN'")

	# --- 5. Superficie 2: la pantalla de fin dedicada ------------------------
	var game_over: CanvasLayer = null
	for child in main.get_children():
		if child is CanvasLayer and (child as CanvasLayer).layer == 30:
			game_over = child as CanvasLayer
	_check(game_over != null, "Main crea la pantalla de fin dedicada (GameOver)")
	if game_over != null:
		_check(game_over.visible, "la pantalla de fin se muestra al ganar")
		var title_label: Label = game_over.get_node_or_null(
			"Root/Panel/VBox/TitleLabel") as Label
		_check(title_label != null, "la pantalla de fin tiene TitleLabel")
		if title_label != null:
			_info("título de la pantalla de fin: %s" % title_label.text)
			_check(title_label.text.contains("EXTRACCIÓN"),
				"la pantalla de fin anuncia EXTRACCIÓN")
		# Los botones deben procesar input con el árbol pausado (bug de R1).
		for node_path in ["Root/Panel/VBox/RetryButton", "Root/Panel/VBox/MenuButton"]:
			var button: Button = game_over.get_node_or_null(node_path) as Button
			_check(button != null, "la pantalla de fin tiene %s" % node_path.get_file())
			if button != null:
				_check(button.can_process(),
					"%s procesa input con el árbol pausado" % node_path.get_file())

	# --- 6. El árbol queda pausado -------------------------------------------
	_check(get_tree().paused, "la victoria pausa el árbol")

	await _finish()

func _finish() -> void:
	print("VICTORY_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los asserts (patrón de las demás suites).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "VICTORY_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
