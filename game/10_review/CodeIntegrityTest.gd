extends Node
## ============================================================================
## CODE INTEGRITY TEST (R1-hotfix) — el código del proyecto está íntegro.
## ============================================================================
## Al abrir el EDITOR de Godot apareció un error que la compuerta NO veía:
##
##   SCRIPT ERROR: Parse Error: Cannot find member "keys" in base "int".
##   SCRIPT ERROR: Parse Error: Function "keys()" not found in base int.
##   ERROR: Failed to load script "res://05_house/HouseBuilder.gd" with error
##          "Parse error".
##
## POR QUÉ SE ESCAPABA: `godot --headless --import` y las suites headless
## solo compilan los scripts que carga la escena principal o la escena del
## arnés. `HouseBuilder.gd` no lo carga nadie (es un módulo procedural
## heredado), así que su error de sintaxis era INVISIBLE para el CI.
## El editor, en cambio, escanea todo el sistema de ficheros al abrir el
## proyecto y lo detecta.
##
##Este arnés cierra el hueco en DOS frentes:
##
## A. COMPILACIÓN: recorre TODO `res://` (no una lista de carpetas, que
##    se quedó obsoleta y dejaba fuera 11 scripts) y compila cada `.gd`.
##    Una lista manual de rutas es una puerta que se pudre: la primera
##    versión de este arnés revisaba 62 de los 73 scripts del proyecto.
##    Ahora el alcance se deriva del propio sistema de ficheros.
##
## B. API DE MÓDULOS HUÉRFANOS: que el script compile no basta; un módulo
##    que NADIE carga puede compilar y estar roto por dentro. Se comprueba
##    que `HouseBuilder.get_part()` devuelve la pieza del material pedido
##    (el módulo que destapó este bug).
##
## Criterio de script roto (medido en Godot 4.7.2): `load()` de un GDScript
## con error de parseo devuelve un objeto NO NULO, pero con
## `can_instantiate() == false` y sin métodos; `reload()` devuelve
## ERR_PARSE_ERROR (43). Se usa `can_instantiate()` porque recargar todos
## los scripts en el proceso del test tiene efectos secundarios (registro
## de clases globales). Un script `@abstract` no es instanciable pero sí es
## valido: se acepta con `is_abstract()`.
## ============================================================================

## Raíz del escaneo: TODO el proyecto.
const SCAN_ROOT: String = "res://"

## Carpetas excluidas del escaneo, con motivo.
const EXCLUDED_DIRS: Array[String] = [
	".godot",       # cache de importacion de Godot (oculta: no se lista)
	"addons",       # plugins de terceros: no los gobierna este proyecto
	".import",      # cache de importacion
	"build",        # artefactos de build (ignorados por git)
	"export",       # exportaciones (ignoradas por git)
]

var _failures: Array[String] = []
var _checked: int = 0
## Rutas realmente revisadas (res://...), para contrastar con el manifiesto.
var _scanned: Array[String] = []
## Carpetas que no se pudieron abrir: un error de lectura NO puede reducir
## el alcance en silencio (seria un falso verde de la puerta).
var _scan_errors: Array[String] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_parse_all_scripts()
	await _orphan_module_api()
	_manifest_coverage()
	print("CODE_INTEGRITY_TEST failures=%d checked=%d" % [_failures.size(), _checked])
	for f in _failures:
		print("  - " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
	_asserts()


## ---------------------------------------------------------------------------
## A. Todos los scripts del proyecto compilan.
## ---------------------------------------------------------------------------
func _parse_all_scripts() -> void:
	var broken: Array[String] = []
	_scan_dir(SCAN_ROOT, broken)
	_check(broken.is_empty(),
		"Todos los scripts del proyecto compilan (%d revisados)" % _checked)
	if not broken.is_empty():
		for path in broken:
			print("FAIL script roto: " + path)
	_check(_scan_errors.is_empty(),
		"Se pudo leer todo el arbol de directorios (%d errores)" % _scan_errors.size())
	for path in _scan_errors:
		print("FAIL directorio ilegible: " + path)


func _scan_dir(path: String, broken: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		_scan_errors.append(path)
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var child: String = path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with(".") and not EXCLUDED_DIRS.has(entry):
				_scan_dir(child, broken)
		elif entry.ends_with(".gd"):
			_check_script(child, broken)
		entry = dir.get_next()
	dir.list_dir_end()


func _check_script(path: String, broken: Array[String]) -> void:
	_checked += 1
	_scanned.append(path)
	var script: Variant = load(path)
	if script == null or not (script is Script):
		broken.append(path)
		return
	var as_script: Script = script as Script
	# Un script roto no se puede instanciar y no expone metodos.
	if not as_script.can_instantiate():
		# Un `@abstract` es valido aunque no sea instanciable.
		if as_script.has_method("is_abstract") and as_script.is_abstract():
			return
		broken.append(path)


## ---------------------------------------------------------------------------
## C. La cobertura coincide con el MANIFIESTO de git.
## ---------------------------------------------------------------------------
## El escaneo deriva del sistema de ficheros, asi que una exclusion
## accidental, un renombrado de carpeta o un error de lectura podria reducir
## el alcance SIN romper la puerta (el problema que reviewing detecto en la
## primera version: 62 de 73 scripts). Aqui se contrasta el conjunto
## escaneado con los scripts VERSIONADOS: si algun script de git no fue
## revisado, la puerta falla.
##
## El CI hace la comprobacion complementaria: calcula el numero esperado
## con `git ls-files` y exige `checked=N` en el log, de modo que anadir un
## script nuevo sin actualizar la puerta tampoco pase en silencio.
## ---------------------------------------------------------------------------
func _manifest_coverage() -> void:
	var game_dir: String = ProjectSettings.globalize_path("res://")
	var output: Array = []
	var status: int = OS.execute(
		"git", PackedStringArray(["-C", game_dir, "ls-files", "--", "*.gd"]), output, true)
	if status != 0:
		# Sin git (o sin checkout) el manifiesto no existe: la invariancia
		# la cubre entonces el CI, que siempre tiene el repositorio.
		print("NOTE  manifiesto de git no disponible (status=%d)" % status)
		return
	var tracked: Array[String] = []
	for line in str(output[0]).split("\n", false):
		var clean: String = line.strip_edges()
		if clean.ends_with(".gd"):
			tracked.append("res://" + clean)
	tracked.sort()
	var scanned: Array[String] = _scanned.duplicate()
	scanned.sort()
	var missing: Array[String] = []
	for path in tracked:
		if not scanned.has(path):
			missing.append(path)
	_check(missing.is_empty(),
		"El escaneo cubre los %d scripts versionados (%d revisados)" % [tracked.size(), scanned.size()])
	for path in missing:
		print("FAIL script versionado NO revisado: " + path)
	# Scripts en disco que no estan versionados: no son cobertura perdida,
	# pero se listan para que el dato sea transparente.
	var extra: Array[String] = []
	for path in scanned:
		if not tracked.has(path):
			extra.append(path)
	if not extra.is_empty():
		print("NOTE  scripts en disco sin versionar: %s" % str(extra))


## ---------------------------------------------------------------------------
## B. Los modulos que NADIE carga responden (el caso real que motivo la puerta).
## ---------------------------------------------------------------------------
func _orphan_module_api() -> void:
	var builder_script: Variant = load("res://05_house/HouseBuilder.gd")
	if builder_script == null:
		_check(false, "HouseBuilder: el script se puede cargar")
		return
	var builder: Node = (builder_script as Script).new()
	add_child(builder)
	await get_tree().process_frame

	if not builder.has_method("get_part"):
		_check(false, "HouseBuilder: expone get_part(tipo, material)")
		builder.free()
		await get_tree().process_frame
		return
	# HousePart.WallMaterial.WOOD == 0 y HousePart.PartType.WALL == 0.
	var part: Variant = builder.call("get_part", 0, 0)
	_check(part != null, "HouseBuilder.get_part(WALL, WOOD) devuelve una pieza")
	if part != null:
		var material_value: int = int(part.get("material"))
		var part_type: int = int(part.get("part_type"))
		_check(material_value == 0,
			"HouseBuilder.get_part(WALL, WOOD) devuelve la pieza del material pedido (%d)" % material_value)
		_check(part_type == 0,
			"HouseBuilder.get_part(WALL, WOOD) devuelve la pieza del tipo pedido (%d)" % part_type)
	# Un material inexistente debe devolver null, no reventar.
	var missing: Variant = builder.call("get_part", 0, 99)
	_check(missing == null, "HouseBuilder.get_part() con material inexistente devuelve null")
	# Liberacion INMEDIATA: `queue_free()` no llega a procesarse antes del
	# `quit()` del arnés y los RectangleShape2D del builder quedan vivos
	# ("40 RID allocations of type 'P12GodotShape2D' were leaked at exit").
	builder.free()
	await get_tree().process_frame


func _asserts() -> void:
	if not ("--strict-assert" in OS.get_cmdline_user_args()):
		return
	assert(_failures.is_empty(), "CODE_INTEGRITY_TEST: hay fallos")
