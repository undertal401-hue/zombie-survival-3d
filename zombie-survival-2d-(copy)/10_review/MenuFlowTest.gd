extends Node
## CAPA 3 / TDD — contrato del ÍTEM 15: flujo de menú principal y pantalla de fin.
## Escrito ANTES de la implementación sobre a7ceeb7: DEBE FALLAR.
## Introspección 100% dinámica (FileAccess + búsqueda de texto). No se referencian
## símbolos que aún no existen, así que este arnés no produce Parse Error aunque
## el menú todavía no esté implementado.

const MAIN_MENU_GD: String = "res://08_ui/MainMenu.gd"
const MAIN_MENU_TSCN: String = "res://08_ui/MainMenu.tscn"
const GAME_OVER_GD: String = "res://08_ui/GameOver.gd"
const GAME_OVER_TSCN: String = "res://08_ui/GameOver.tscn"
const MAIN: String = "res://07_house/Main.gd"
const GAME_STATE: String = "res://01_core/GameState.gd"
const HUD: String = "res://08_ui/HUD.gd"

var _failures: Array[String] = []

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

func _has_any(src: String, tokens: Array[String]) -> bool:
	for token in tokens:
		if src.contains(token):
			return true
	return false

func _positions(src: String, needle: String) -> Array[int]:
	var out: Array[int] = []
	var idx: int = 0
	while true:
		var pos: int = src.find(needle, idx)
		if pos == -1:
			break
		out.append(pos)
		idx = pos + needle.length()
	return out

func _ready() -> void:
	await get_tree().process_frame
	_menu_files()
	_menu_api()
	_main_and_state()
	_death_victory_flow()
	await _paused_input_checks()
	await _finish()

# --- ÍTEM 15.1-15.2: archivos del menú y del fin ------------------------------

func _menu_files() -> void:
	var menu_exists: bool = FileAccess.file_exists(MAIN_MENU_GD) \
		or FileAccess.file_exists(MAIN_MENU_TSCN)
	_check(menu_exists, "ÍTEM 15.1 existe game/08_ui/MainMenu.gd o MainMenu.tscn")
	var over_exists: bool = FileAccess.file_exists(GAME_OVER_GD) \
		or FileAccess.file_exists(GAME_OVER_TSCN)
	_check(over_exists, "ÍTEM 15.2 existe game/08_ui/GameOver.gd o GameOver.tscn")

# --- ÍTEM 15.3-15.4: API expuesta por cada pantalla --------------------------

func _menu_api() -> void:
	var menu_src: String = _read(MAIN_MENU_GD) + "\n" + _read(MAIN_MENU_TSCN)
	_check(_has_any(menu_src, ["start_pressed", "start_game", "new_game", "continue_game"]),
		"ÍTEM 15.3 MainMenu expone start_pressed/start_game/new_game/continue_game")
	var over_src: String = _read(GAME_OVER_GD) + "\n" + _read(GAME_OVER_TSCN)
	_check(_has_any(over_src, ["retry_pressed", "return_to_menu", "restart"]),
		"ÍTEM 15.4 GameOver expone retry_pressed/return_to_menu/restart")

# --- ÍTEM 15.5-15.6: integración en Main y fase de menú ----------------------

func _main_and_state() -> void:
	var main: String = _read(MAIN)
	var menu_ref: bool = main.contains("MainMenu") or main.contains("main_menu")
	var over_ref: bool = main.contains("GameOver") or main.contains("game_over")
	if not menu_ref:
		_info("Main.gd sin referencia a MainMenu/main_menu")
	if not over_ref:
		_info("Main.gd sin referencia a GameOver/game_over")
	_check(menu_ref and over_ref,
		"ÍTEM 15.5 Main.gd referencia el menú y el fin de partida")

	# La fase de menú puede llamarse PHASE_MENU o reuse PHASE_BOOT como boot/menu;
	# en ambos casos debe aparecer el concepto 'menu' en el bloque de fases.
	var state: String = _read(GAME_STATE)
	var idx: int = state.find("const PHASE_")
	var block: String = "" if idx == -1 else state.substr(maxi(0, idx - 200), 2200)
	var blo: String = block.to_lower()
	var menu_phase: bool = blo.contains("phase_menu") or blo.contains("menu")
	_check(menu_phase,
		"ÍTEM 15.6 GameState.gd define fase de menú (PHASE_MENU o 'menu' cerca de las fases)")

# --- ÍTEM 15.7: muerte/victoria muestran pantalla de fin ---------------------

func _death_victory_flow() -> void:
	var ui: String = (_read(HUD) + "\n" + _read(MAIN)).to_lower()
	var signals_ok: bool = ui.contains("game_over") and ui.contains("victory")
	var display_tokens: Array[String] = [
		"show(", "visible = true", "end_overlay", "end_panel", "end_screen"]
	var near: bool = false
	for sig in ["game_over", "victory"]:
		for pos in _positions(ui, sig):
			var window: String = ui.substr(maxi(0, pos - 1400), 2800)
			for token in display_tokens:
				if window.contains(token):
					near = true
	_check(signals_ok and near,
		"ÍTEM 15.7 game_over/victory conectados a mostrar pantalla de fin (show/visible)")

# --- R1: los botones DEBEN funcionar con el árbol pausado --------------------
#
# El bug que ve el usuario: al morir, HUD.gd pausa el árbol (`get_tree().paused
# = true`). Las pantallas de fin heredaban `process_mode = 0` (PAUSABLE), así
# que sus botones NO procesaban input y el clic no hacía nada.
#
# Este check es el que lo ata: sin PROCESS_MODE_ALWAYS, el CI falla.

func _paused_input_checks() -> void:
	for path in [MAIN_MENU_TSCN, GAME_OVER_TSCN]:
		var src: String = _read(path)
		_check(src.contains("process_mode = 3"),
			"R1: %s declara process_mode = 3 (PROCESS_MODE_ALWAYS)" % path.get_file())
	for path in [MAIN_MENU_GD, GAME_OVER_GD]:
		var src: String = _read(path)
		_check(src.contains("PROCESS_MODE_ALWAYS"),
			"R1: %s fuerza PROCESS_MODE_ALWAYS en _ready()" % path.get_file())

	# Comprobación en runtime: con el árbol pausado, el botón sigue procesando
	# input. Es la prueba que reproduce exactamente el clic que fallaba.
	#
	# Mecanismo verificado en el juego real (sonda /tmp/opencode/repro_zs):
	# con el CanvasLayer en PROCESS_MODE_PAUSABLE, `retry.can_process()` es
	# false, el clic real NO llega al botón, el árbol sigue pausado y la
	# pantalla de derrota no se cierra. Con PROCESS_MODE_ALWAYS, el botón
	# procesa el clic, `Main._on_game_over_retry()` despausa y recarga.
	var game_over: Node = _instantiate(GAME_OVER_TSCN)
	if game_over == null:
		_check(false, "R1: GameOver.tscn se puede instanciar")
		return
	get_tree().root.add_child(game_over)
	await get_tree().process_frame
	game_over.visible = true
	var retry: Button = game_over.get_node_or_null("Root/Panel/VBox/RetryButton") as Button
	var menu_button: Button = game_over.get_node_or_null("Root/Panel/VBox/MenuButton") as Button
	_check(retry != null, "R1: GameOver tiene un botón de reintento")
	_check(menu_button != null, "R1: GameOver tiene un botón de volver al menú")
	var was_paused: bool = get_tree().paused
	get_tree().paused = true
	await get_tree().process_frame
	_check(game_over.process_mode == Node.PROCESS_MODE_ALWAYS,
		"R1: la pantalla de fin está en PROCESS_MODE_ALWAYS")
	if retry != null:
		# El botón hereda el modo del CanvasLayer: `process_mode` sale INHERIT,
		# pero `can_process()` es la pregunta real ("¿procesa input ahora?").
		_check(retry.can_process(),
			"R1: el botón de reintento SIGUE procesando input con el árbol pausado")
	if menu_button != null:
		_check(menu_button.can_process(),
			"R1: el botón de volver al menú SIGUE procesando input con el árbol pausado")
	get_tree().paused = was_paused
	game_over.queue_free()
	await get_tree().process_frame

func _instantiate(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate()

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for i in range(6):
		await get_tree().process_frame
	print("MENU_FLOW_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón GameFeelTest).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Red de seguridad opcional: solo con `-- --strict-assert`.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "MENU_FLOW_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
