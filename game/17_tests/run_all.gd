extends Node
## Runner principal de la suite de tests.
##
## Se ejecuta como escena normal (TestRunner.tscn) para que los autoloads
## (Config, EventBus, ...) esten disponibles. Cada suite expone `run() -> int`
## y devuelve el numero de fallos.

var test_scripts: Array[String] = [
	"res://17_tests/test_stats.gd",
	"res://17_tests/test_damage.gd",
	"res://17_tests/test_waves.gd",
	"res://17_tests/test_economy.gd",
	"res://17_tests/test_scene_validation.gd",
]

var total_passed: int = 0
var total_failed: int = 0


func _ready() -> void:
	print("=== ZOMBIE SURVIVAL 3D - TEST SUITE ===")
	var only: String = _requested_test()
	var selected: Array[String] = []
	for path: String in test_scripts:
		if only.is_empty() or path.get_file().get_basename() == only:
			selected.append(path)
	if selected.is_empty():
		printerr("No hay tests que coincidan con: %s" % only)
		get_tree().quit(1)
		return
	print("Ejecutando %d suites de tests...\n" % selected.size())
	for path: String in selected:
		_run_suite(path)
	_finish(selected.size())


func _run_suite(path: String) -> void:
	print("--- %s ---" % path)
	var script: Script = load(path) as Script
	if script == null:
		printerr("No se pudo cargar: %s" % path)
		total_failed += 1
		return
	var suite: RefCounted = script.new() as RefCounted
	if suite == null or not suite.has_method("run"):
		printerr("Suite invalida (sin run()): %s" % path)
		total_failed += 1
		return
	var failures: int = int(suite.call("run"))
	if failures == 0:
		total_passed += 1
		print("Suite OK\n")
	else:
		total_failed += 1
		printerr("Suite FALLÓ (%d fallos)\n" % failures)


func _finish(count: int) -> void:
	print("=== RESUMEN ===")
	print("Suites pasadas: %d" % total_passed)
	print("Suites falladas: %d" % total_failed)
	print("Total: %d" % count)
	if total_failed > 0:
		printerr("TESTS FALLARON")
		get_tree().quit(1)
	else:
		print("TODOS LOS TESTS PASARON")
		get_tree().quit(0)


## Permite ejecutar una sola suite:
## godot --headless --path game 17_tests/TestRunner.tscn -- --test=test_waves
func _requested_test() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			return arg.substr("--test=".length())
	return ""
