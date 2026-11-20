extends Node
## ============================================================================
## SCRIPT PARSE TEST (R1-hotfix) — todos los scripts del proyecto compilan.
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
## Este arnés cierra el hueco: compila TODOS los `.gd` del proyecto y falla
## si alguno no se puede cargar. Es una puerta de uso general: cualquier
## script roto en el futuro, esté o no conectado, cae aquí.
##
## Nota sobre `load()`: un GDScript con error de parseo devuelve un objeto NO
## NULO (con `can_instantiate() == false` y sin métodos) y el motor escribe el
## error en el log, así que el arnés falla por partida doble (el check y el
## grep del CI).
## ============================================================================

const SCAN_ROOTS: Array[String] = [
	"res://01_core",
	"res://02_player",
	"res://03_zombies",
	"res://05_house",
	"res://07_house",
	"res://08_ui",
	"res://09_tests",
	"res://10_review",
	"res://11_forest",
	"res://12_vehicles",
	"res://13_audio",
	"res://14_quests",
]

var _failures: Array[String] = []
var _checked: int = 0


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_parse_all_scripts()
	print("SCRIPT_PARSE_TEST failures=%d checked=%d" % [_failures.size(), _checked])
	for f in _failures:
		print("  - " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
	_asserts()


func _parse_all_scripts() -> void:
	var broken: Array[String] = []
	for root in SCAN_ROOTS:
		_scan_dir(root, broken)
	_check(broken.is_empty(),
		"Todos los scripts del proyecto compilan (%d revisados)" % _checked)
	if not broken.is_empty():
		for path in broken:
			print("FAIL script roto: " + path)


func _scan_dir(path: String, broken: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(path.path_join(entry), broken)
		elif entry.ends_with(".gd"):
			_check_script(path.path_join(entry), broken)
		entry = dir.get_next()
	dir.list_dir_end()


func _check_script(path: String, broken: Array[String]) -> void:
	_checked += 1
	var script: Variant = load(path)
	if script == null:
		broken.append(path)
		return
	if not (script is Script):
		broken.append(path)
		return
	# Un GDScript con error de parseo se carga como objeto NO NULO pero sin
	# métodos y con `can_instantiate() == false` (medido en Godot 4.7.2:
	# `reload()` devuelve ERR_PARSE_ERROR = 43). Ningún script del proyecto
	# usa `@abstract`, así que `can_instantiate()` es un criterio seguro.
	if not (script as Script).can_instantiate():
		broken.append(path)


func _asserts() -> void:
	if not ("--strict-assert" in OS.get_cmdline_user_args()):
		return
	assert(_failures.is_empty(), "SCRIPT_PARSE_TEST: hay fallos")
