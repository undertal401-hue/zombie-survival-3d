extends Node
## CAPA 2 (TDD) — contrato del ÍTEM 11: árbol de mejoras meta, migración de
## guardado v1 -> v2, compra/selector de mejoras y aplicación al iniciar partida.
## Se escribe ANTES de la implementación sobre 00afcb0: DEBE FALLAR.
##
## Introspección 100% dinámica (FileAccess / búsqueda de texto / get). No se
## referencian símbolos que aún no existen, así que este arnés no produce
## Parse Error aunque el árbol meta todavía no esté implementado.

const META_PROGRESS: String = "res://16_meta/MetaProgress.gd"

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

func _ready() -> void:
	await get_tree().process_frame
	var src: String = _read(META_PROGRESS)
	var tree: String = _tree_block(src)
	var stats: Array = _tree_stats(tree)
	var branches: int = int(stats[0])
	var levels: int = int(stats[1])
	_check(_number_after_const(src, "SAVE_VERSION") >= 2.0, \
		"MetaProgress.gd declara SAVE_VERSION >= 2 (migración desde v1)")
	_check(_declares(src, ["UPGRADE_TREE", "BRANCHES", "upgrades"]), \
		"existe dato de árbol: UPGRADE_TREE, BRANCHES o upgrades")
	_check(branches >= 3 and levels >= 6, \
		"árbol con al menos 3 ramas y >=2 niveles cada una (ramas=%d, niveles=%d)" % [branches, levels])
	_check(_has_func_any(src, ["buy_upgrade", "select_upgrade", "purchase_upgrade", \
			"unlock_upgrade", "choose_upgrade"]), \
		"existe método de compra/selector (buy_upgrade / select_upgrade o similar)")
	_check(_has_func_any(src, ["_migrate", "migrate"]), \
		"existe _migrate() o migrate en MetaProgress.gd")
	_check(_ready_applies_upgrades(src), \
		"MetaProgress.gd aplica mejoras al iniciar partida (apply_upgrades/get_upgrade cerca de _ready)")
	await _finish()

# --- helpers de introspección ------------------------------------------------

func _declares(src: String, tokens: Array[String]) -> bool:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if not (s.begins_with("func ") or s.begins_with("var ") \
				or s.begins_with("const ") or s.begins_with("@export var ")):
			continue
		for tok in tokens:
			if s.contains(tok):
				return true
	return false

func _has_func_any(src: String, tokens: Array[String]) -> bool:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if not s.begins_with("func "):
			continue
		for tok in tokens:
			if s.contains(tok):
				return true
	return false

func _number_after_const(src: String, name: String) -> float:
	for line in src.split("\n"):
		var s: String = line.strip_edges()
		if not s.begins_with("const " + name):
			continue
		var eq: int = s.find("=")
		if eq == -1:
			continue
		var raw: String = s.substr(eq + 1).strip_edges()
		var end: int = 0
		while end < raw.length():
			var c: String = raw.substr(end, 1)
			if "0123456789.-+eE".contains(c):
				end += 1
			else:
				break
		if end > 0:
			return raw.substr(0, end).to_float()
	return -1.0

func _tree_block(src: String) -> String:
	var lines := src.split("\n")
	var start: int = -1
	for i in range(lines.size()):
		var s: String = lines[i].strip_edges()
		for tok in ["UPGRADE_TREE", "BRANCHES", "upgrades"]:
			if s.begins_with("const " + tok) or s.begins_with("var " + tok) \
					or s.begins_with("@export var " + tok):
				start = i
				break
		if start != -1:
			break
	if start == -1:
		return ""
	var out: String = ""
	for i in range(start, mini(lines.size(), start + 220)):
		out += lines[i] + "\n"
	return out

func _indent(line: String) -> int:
	var n: int = 0
	for i in range(line.length()):
		var c: String = line.substr(i, 1)
		if c == "\t" or c == " ":
			n += 1
		else:
			break
	return n

func _looks_like_entry(s: String) -> bool:
	if s.begins_with("#") or s.begins_with("}") or s.begins_with("]"):
		return false
	if s.begins_with("return") or s.begins_with("func "):
		return false
	return s.contains(":") or s.begins_with("\"")

func _count_occurrences(haystack: String, needle: String) -> int:
	if needle.is_empty():
		return 0
	var count: int = 0
	var idx: int = 0
	while true:
		var pos: int = haystack.find(needle, idx)
		if pos == -1:
			break
		count += 1
		idx = pos + needle.length()
	return count

func _tree_stats(block: String) -> Array:
	if block.is_empty():
		return [0, 0]
	var lines := block.split("\n")
	var base: int = _indent(lines[0])
	var branch_indent: int = -1
	var branches: int = 0
	var levels: int = 0
	for i in range(1, lines.size()):
		var line: String = lines[i]
		if line.strip_edges().is_empty():
			continue
		var ind: int = _indent(line)
		var s: String = line.strip_edges()
		if ind <= base:
			if s.begins_with("const ") or s.begins_with("var ") \
					or s.begins_with("func ") or s.begins_with("signal "):
				break
			continue
		if not _looks_like_entry(s):
			continue
		if branch_indent == -1:
			branch_indent = ind
			branches += 1
		elif ind == branch_indent:
			branches += 1
		elif ind > branch_indent:
			levels += 1
	# Fallback: estructuras planas con arrays de niveles usan tokens level/tier.
	var markers: int = 0
	var low: String = block.to_lower()
	for tok in ["level", "tier", "rank", "nivel"]:
		markers += _count_occurrences(low, tok)
	levels = maxi(levels, markers)
	return [branches, levels]

func _ready_applies_upgrades(src: String) -> bool:
	var lines := src.split("\n")
	var in_ready: bool = false
	for i in range(lines.size()):
		var s: String = lines[i].strip_edges()
		if s.begins_with("func "):
			if in_ready:
				break
			in_ready = s.contains("_ready")
			continue
		if not in_ready:
			continue
		var low: String = s.to_lower()
		if low.contains("apply_upgrades") or low.contains("get_upgrade") \
				or low.contains("upgrade"):
			return true
	return false

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for i in range(6):
		await get_tree().process_frame
	print("META_TREE_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón ArtAnimTest / GameFeelTest).
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Red de seguridad opcional: en fase roja se desactiva para no imprimir
	# "SCRIPT ERROR: Assertion failed". Habilitar con `-- --strict-assert`.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "META_TREE_TEST: " + f)

func _strict_assert_enabled() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--strict-assert":
			return true
	return false
