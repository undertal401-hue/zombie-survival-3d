extends Node
## CAPA 0 (TDD) — contrato de mejoras 1-4: decals poolados con tope de 64.
## Se escribe ANTES de la implementación: DEBE FALLAR en ea329e8.
##
## Introspección 100% dinámica (has_method / get / callv / find_children /
## FileAccess). No se referencian métodos que aún no existen, así que este
## arnés no produce Parse Error aunque `spawn_decal` todavía no esté escrito.

const PM_SOURCE: String = "res://01_core/ParticleManager.gd"
const ART_BIBLE: String = "res://assets/art/ART_BIBLE.md"
const MAX_DECALS: int = 64

var _failures: Array[String] = []
var _pm: Node
var _decals: Node
var _color_arg_node: Control

func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _ready() -> void:
	await get_tree().process_frame
	_pm = get_node_or_null("/root/ParticleManager")
	_check(_pm != null, "ParticleManager autoload disponible")
	if _pm == null:
		await _finish()
		return
	_api_checks()
	_pool_checks()
	await _overflow_checks()
	_palette_checks()
	await _finish()

# --- 1. API ------------------------------------------------------------------

func _api_checks() -> void:
	_check(_pm.has_method("spawn_decal"),
		"ParticleManager expone spawn_decal(kind: StringName, pos: Vector2, color)")

# --- 2. Pool con tope 64 -----------------------------------------------------

func _pool_checks() -> void:
	var src: String = _read(PM_SOURCE)
	var in_source: bool = src.contains("MAX_DECALS") or src.contains("decal_pool")
	var in_runtime: bool = _pm.get("decal_pool") != null or _pm.has_method("get_decal_pool")
	_check(in_source or in_runtime,
		"existe pool de decals con capacidad máxima 64 (MAX_DECALS/decal_pool)")

# --- 3. Tope real tras 70 llamadas ------------------------------------------

func _overflow_checks() -> void:
	_decals = _pm.get_node_or_null("Decals")
	if _decals == null:
		_decals = get_tree().root.get_node_or_null("Decals")
	if _decals == null:
		var candidates: Array = get_tree().root.find_children("Decals", "Node", true, false)
		if not candidates.is_empty():
			_decals = candidates[0] as Node
	_check(_decals != null, "existe contenedor 'Decals' donde medir el pool")
	if _decals == null:
		return
	if not _pm.has_method("spawn_decal"):
		_check(false,
			"70 llamadas a spawn_decal no crean más de 64 nodos (método ausente)")
		return
	var arg: Variant = _decal_color_arg(_read(PM_SOURCE))
	for i in range(70):
		var args: Array = [&"blood", Vector2(float(i * 4), 0.0), arg]
		_pm.callv("spawn_decal", args)
	await get_tree().process_frame
	var count: int = _decals.get_child_count()
	_check(count <= MAX_DECALS,
		"70 spawn_decal crean como máximo 64 nodos (encontrados %d)" % count)

# El contrato escribe `color: Control`; si la firma efectiva usa Control se
# pasa un ColorRect rojo, si usa Color se pasa Color.RED. Así nunca hay error
# de tipo al invocarlo dinámicamente.
func _decal_color_arg(src: String) -> Variant:
	var idx: int = src.find("func spawn_decal")
	if idx == -1:
		return Color.RED
	var end: int = src.find("\n", idx)
	var signature: String = src.substr(idx, maxi(end - idx, 0))
	if signature.contains("Control"):
		var rect: ColorRect = ColorRect.new()
		rect.color = Color.RED
		_color_arg_node = rect
		return rect
	return Color.RED

# --- 4. Colores desde la paleta ---------------------------------------------

func _palette_checks() -> void:
	var bible: String = _read(ART_BIBLE)
	var src: String = _read(PM_SOURCE)
	# No se fija un hex concreto: se deriva de la propia paleta del ART_BIBLE
	# para que el contrato no dependa de qué rojo elija la implementación.
	var palette: Array[String] = _hex_colors(bible)
	var blood_reds: Array[String] = []
	for h in palette:
		var c: Color = Color.html(h)
		if c.r >= 0.35 and c.r > c.g * 1.4 and c.r > c.b * 1.4:
			blood_reds.append(h)
	_check(not blood_reds.is_empty(),
		"ART_BIBLE.md incluye un rojo sangre en la paleta")
	var from_palette: bool = false
	for h in palette:
		if src.contains(h) or src.contains(h.to_lower()):
			from_palette = true
			break
	_check(from_palette,
		"ParticleManager.gd toma los colores de decal de la paleta de ART_BIBLE.md")

func _hex_colors(text: String) -> Array[String]:
	var out: Array[String] = []
	for line in text.split("\n"):
		for i in range(line.length()):
			if line.substr(i, 1) != "#":
				continue
			var hex: String = line.substr(i + 1, 6)
			if hex.length() == 6 and _is_hex(hex):
				out.append("#" + hex)
	return out

func _is_hex(value: String) -> bool:
	var digits: String = "0123456789abcdefABCDEF"
	for i in range(value.length()):
		if not digits.contains(value.substr(i, 1)):
			return false
	return true

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	if is_instance_valid(_color_arg_node):
		_color_arg_node.queue_free()
	for i in range(6):
		await get_tree().process_frame
	print("FX_DECAL_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón NightGlareTest).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Red de seguridad opcional: en fase roja se desactiva para no imprimir
	# "SCRIPT ERROR: Assertion failed" en el log. Habilitar con
	# `-- --strict-assert` tras la ruta de la escena.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "FX_DECAL_TEST: " + f)

func _strict_assert_enabled() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--strict-assert":
			return true
	return false
