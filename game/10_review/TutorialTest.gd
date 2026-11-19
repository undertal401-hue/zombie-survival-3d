extends Node
## CAPA 3 / TDD — contrato del ÍTEM 17: tutorial contextual no bloqueante que
## se oculta al cumplir la acción y persiste solo la primera partida.
## Escrito ANTES de la implementación sobre a7ceeb7: DEBE FALLAR.
## Incluye CONTRASTE VERDE del ÍTEM 18 (HUD con oleadas/reloj): esos checks
## SÍ deben pasar en la base y no se fuerzan a fallar.

const HUD: String = "res://08_ui/HUD.gd"
const MAIN: String = "res://07_house/Main.gd"

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

func _source() -> String:
	return (_read(HUD) + "\n" + _read(MAIN)).to_lower()

func _ready() -> void:
	await get_tree().process_frame
	_exists()
	_prompts()
	_hiding()
	_persistence()
	_non_blocking()
	_contrast_item18()
	await _finish()

# --- ÍTEM 17.1: existe lógica de tutorial ------------------------------------

func _exists() -> void:
	var positions: Array[int] = _positions(_source(), "tutorial")
	if positions.is_empty():
		_info("Ni HUD.gd ni Main.gd contienen el token 'tutorial'")
	_check(not positions.is_empty(),
		"ÍTEM 17.1 existe lógica de tutorial en HUD.gd o Main.gd")

# --- ÍTEM 17.2: prompts contextuales -----------------------------------------

func _prompts() -> void:
	var src: String = _source()
	var positions: Array[int] = _positions(src, "tutorial")
	var tokens: Array[String] = [
		"e para", "tab", "r para", "interact", "inventory", "reload"]
	var count: int = 0
	for token in tokens:
		var found: bool = false
		for pos in positions:
			var window: String = src.substr(maxi(0, pos - 900), 1800)
			if window.contains(token):
				found = true
				break
		if found:
			count += 1
	_check(count >= 3,
		"ÍTEM 17.2 al menos 3 prompts contextuales cerca del tutorial (%d/6)" % count)

# --- ÍTEM 17.3: se oculta al cumplir la acción -------------------------------

func _hiding() -> void:
	var src: String = _source()
	var positions: Array[int] = _positions(src, "tutorial")
	var hide_tokens: Array[String] = ["hide(", "visible = false", "queue_free("]
	var ok: bool = false
	for pos in positions:
		var window: String = src.substr(maxi(0, pos - 1100), 2200)
		for token in hide_tokens:
			if window.contains(token):
				ok = true
	_check(ok, "ÍTEM 17.3 el tutorial se oculta al cumplirse la acción (hide/visible=false)")

# --- ÍTEM 17.4: persiste solo la primera partida -----------------------------

func _persistence() -> void:
	var src: String = _source()
	var positions: Array[int] = _positions(src, "tutorial")
	var ok: bool = false
	for pos in positions:
		var window: String = src.substr(maxi(0, pos - 1100), 2200)
		if window.contains("user://") or window.contains("metaprogres"):
			ok = true
	_check(ok, "ÍTEM 17.4 tutorial persistido solo la primera partida (user:// o MetaProgress)")

# --- ÍTEM 17.5: no bloquea la entrada ----------------------------------------

func _non_blocking() -> void:
	var src: String = _source()
	var positions: Array[int] = _positions(src, "tutorial")
	# La propiedad negativa solo es verificable si existe código de tutorial.
	# Sin él no hay contrato que comprobar: se marca como incumplida (TDD rojo).
	var ok: bool = not positions.is_empty()
	if ok:
		var blockers: Array[String] = [
			"inventory_open", "get_tree().paused = true", "get_tree().paused=true"]
		for pos in positions:
			var window: String = src.substr(maxi(0, pos - 1100), 2200)
			for token in blockers:
				if window.contains(token):
					ok = false
	_check(ok, "ÍTEM 17.5 el tutorial no bloquea la entrada (sin inventory_open ni pausa)")

# --- CONTRASTE VERDE: ÍTEM 18 ------------------------------------------------

func _contrast_item18() -> void:
	var hud: String = _read(HUD)
	_check(hud.contains("wave"),
		"CONTRASTE ÍTEM 18 HUD.gd contiene 'wave' (debe estar OK en la base)")
	_check(hud.contains("clock") or hud.contains("run_clock"),
		"CONTRASTE ÍTEM 18 HUD.gd contiene 'clock'/'run_clock' (debe estar OK en la base)")
	_info("CONTRASTE ÍTEM 18 MECHANICS_READY 5/5 se verifica en QA_MODE=mechanics")

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for i in range(6):
		await get_tree().process_frame
	print("TUTORIAL_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón GameFeelTest).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Red de seguridad opcional: solo con `-- --strict-assert`.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "TUTORIAL_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
