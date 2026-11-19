extends Node
## CAPA 0 (TDD) — contrato de mejoras 1-4: arte 32 px, animaciones canónicas y
## filtro nearest. Se escribe ANTES de la implementación: DEBE FALLAR en ea329e8.
##
## Introspección 100% dinámica (FileAccess / DirAccess / get / call / has_method).
## No se referencian símbolos que todavía no existen, así que este arnés no
## produce Parse Error aunque el contrato aún no esté implementado.
##
## CORRECCIÓN aplicada: se acepta el nodo `AnimatedSprite2D` existente (o un
## `PixelSprite` si aparece), se acepta cualquiera de las variantes attack*,
## el timer de 0.35 s es INFO no bloqueante, y texture_filter debe ser NEAREST.

const ART_BIBLE: String = "res://assets/art/ART_BIBLE.md"
const GEN_ART: String = "res://tools/gen_art.py"
const SPRITES_DIR: String = "res://assets/art/sprites/"
const PLAYER_SCENE: String = "res://02_player/Player.tscn"
const ZOMBIE_SCENE: String = "res://03_zombies/Zombie.tscn"
const PLAYER_VISUAL: String = "res://02_player/PlayerVisual.gd"
const ZOMBIE_VISUAL: String = "res://03_zombies/ZombieVisual.gd"

var _canonical: Array[String] = ["idle", "walk", "hurt", "death"]
var _attack_variants: Array[String] = [
	"attack", "attack_melee", "attack_pistol", "attack_shotgun", "attack_rifle"
]

var _failures: Array[String] = []
var _player_inst: Node
var _zombie_inst: Node

func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)

func _info(label: String) -> void:
	print("INFO " + label)

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _ready() -> void:
	await get_tree().process_frame
	_bible_checks()
	_generator_checks()
	_sprite_file_checks()
	_player_inst = _instantiate(PLAYER_SCENE)
	_zombie_inst = _instantiate(ZOMBIE_SCENE)
	if _player_inst != null or _zombie_inst != null:
		# El SpriteFrames de PlayerVisual se construye en _ready().
		await get_tree().process_frame
	var player_sprite: Object = _find_sprite(_player_inst)
	var zombie_sprite: Object = _find_sprite(_zombie_inst)
	_actor_checks("Player", player_sprite)
	_actor_checks("Zombie", zombie_sprite)
	_timer_checks(player_sprite)
	await _finish()

# --- 1. ART_BIBLE ------------------------------------------------------------

func _bible_checks() -> void:
	var text: String = _read(ART_BIBLE)
	_check(FileAccess.file_exists(ART_BIBLE),
		"existe assets/art/ART_BIBLE.md")
	_check(text.contains("32"),
		"ART_BIBLE.md documenta sprites de 32 px")
	var hex_lines: int = 0
	for line in text.split("\n"):
		if _has_hex_color(line):
			hex_lines += 1
	_check(hex_lines >= 16,
		"ART_BIBLE.md contiene paleta de 16 colores (líneas hexadecimal): %d" % hex_lines)

func _has_hex_color(line: String) -> bool:
	for i in range(line.length()):
		if line.substr(i, 1) != "#":
			continue
		var tail: String = line.substr(i + 1, 6)
		if tail.length() == 6 and _is_hex(tail):
			return true
	return false

func _is_hex(value: String) -> bool:
	var digits: String = "0123456789abcdefABCDEF"
	for i in range(value.length()):
		if not digits.contains(value.substr(i, 1)):
			return false
	return true

# --- 2. tools/gen_art.py --check --------------------------------------------

func _generator_checks() -> void:
	var exists: bool = FileAccess.file_exists(GEN_ART)
	_check(exists, "existe tools/gen_art.py")
	if not exists:
		_check(false, "python3 tools/gen_art.py --check sale 0 (generador ausente)")
		_check(false, "gen_art.py --check no crea archivos (generador ausente)")
		return
	var abs_path: String = ProjectSettings.globalize_path(GEN_ART)
	var before: Array[String] = _snapshot_outputs()
	# Godot 4.7: OS.execute(path: String, arguments: PackedStringArray,
	# output: Array = []) -> int (exit code).
	var output: Array = []
	var code: int = OS.execute("python3",
		PackedStringArray([abs_path, "--check"]), output)
	_check(code == 0,
		"python3 tools/gen_art.py --check sale 0 (exit=%d)" % code)
	var after: Array[String] = _snapshot_outputs()
	_check(before == after,
		"gen_art.py --check es solo verificación (no crea archivos)")

# --- 3. PNG ------------------------------------------------------------------

func _sprite_file_checks() -> void:
	var pngs: Array[String] = []
	_collect_files(SPRITES_DIR, pngs, ".png")
	_check(pngs.size() >= 8,
		"al menos 8 PNG bajo assets/art/sprites/ (encontrados %d)" % pngs.size())

func _snapshot_outputs() -> Array[String]:
	# Solo las superficies que el generador puede escribir; se evita snapshottear
	# res:// completa porque el propio importador de Godot toca .godot/.
	var files: Array[String] = []
	_collect_files("res://assets/art/", files, "")
	_collect_files("res://tools/", files, "")
	return files

func _collect_files(path: String, out: Array[String], filter: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = path.path_join(entry)
			if dir.current_is_dir():
				_collect_files(child, out, filter)
			elif filter.is_empty() or entry.ends_with(filter):
				out.append(child)
		entry = dir.get_next()
	dir.list_dir_end()

# --- 4-6. Nodo sprite, animaciones y filtro ----------------------------------

func _instantiate(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	get_tree().root.add_child(inst)
	return inst

func _find_sprite(inst: Node) -> Object:
	if inst == null:
		return null
	# Se conserva el nombre actual `AnimatedSprite2D`; `PixelSprite` también
	# se acepta si la implementación decide renombrar el nodo.
	var preferred: Array[String] = [
		"PixelSprite", "AnimatedSprite2D",
		"PlayerVisual/PixelSprite", "PlayerVisual/AnimatedSprite2D",
		"ZombieVisual/PixelSprite", "ZombieVisual/AnimatedSprite2D",
	]
	for node_path in preferred:
		var node: Node = inst.get_node_or_null(NodePath(node_path))
		if node != null and node.is_class("AnimatedSprite2D"):
			return node
	var all: Array = inst.find_children("*", "AnimatedSprite2D", true, false)
	if all.is_empty():
		return null
	return all[0] as Object

func _actor_checks(actor: String, sprite: Object) -> void:
	var present: bool = sprite != null and sprite.is_class("AnimatedSprite2D")
	_check(present,
		"%s: nodo AnimatedSprite2D (o PixelSprite) presente" % actor)
	if not present:
		return
	var frames: Object = sprite.get("sprite_frames") as Object
	var names: Array[String] = _animation_names(frames)
	for needed in _canonical:
		_check(names.has(needed),
			"%s: sprite_frames contiene '%s'" % [actor, needed])
	var has_attack: bool = false
	for candidate in _attack_variants:
		if names.has(candidate):
			has_attack = true
			break
	_check(has_attack,
		"%s: sprite_frames contiene animación attack* (5 canónicas)" % actor)
	_check(_nearest_filter(sprite),
		"%s: texture_filter NEAREST (o material equivalente)" % actor)

func _animation_names(frames: Object) -> Array[String]:
	var out: Array[String] = []
	if frames == null or not frames.has_method("has_animation"):
		return out
	for candidate in _canonical + _attack_variants:
		if bool(frames.call("has_animation", StringName(candidate))):
			out.append(candidate)
	return out

func _nearest_filter(sprite: Object) -> bool:
	var filt: Variant = sprite.get("texture_filter")
	if filt != null and int(filt) == CanvasItem.TEXTURE_FILTER_NEAREST:
		return true
	var mat: Object = sprite.get("material") as Object
	if mat != null:
		var mf: Variant = mat.get("texture_filter")
		if mf != null and int(mf) == CanvasItem.TEXTURE_FILTER_NEAREST:
			return true
	return false

# --- 7. Fallback temporal (INFO, no bloqueante) -----------------------------

func _timer_checks(player_sprite: Object) -> void:
	var src: String = _read(PLAYER_VISUAL)
	var has_035: bool = src.contains("0.35")
	var frames: Object = null
	if player_sprite != null:
		frames = player_sprite.get("sprite_frames") as Object
	var attacks: Array[String] = []
	if frames != null and frames.has_method("has_animation"):
		for candidate in _attack_variants:
			if bool(frames.call("has_animation", StringName(candidate))):
				attacks.append(candidate)
	# El timer de 0.35 s se reporta como INFO mientras exista una animación
	# attack*: solo es FAIL si además NO existe ninguna animación de ataque.
	_check(not attacks.is_empty(),
		"PlayerVisual: existe animación attack* aunque persista el fallback temporal")
	if has_035:
		_info("PlayerVisual.play_attack mantiene timer de 0.35 s (INFO no bloqueante)")
	var zombie_src: String = _read(ZOMBIE_VISUAL)
	if zombie_src.contains("ATTACK_FALLBACK") or zombie_src.contains("0.5"):
		_info("ZombieVisual mantiene ATTACK_FALLBACK temporal (INFO no bloqueante)")

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for inst in [_player_inst, _zombie_inst]:
		if is_instance_valid(inst):
			inst.queue_free()
	for i in range(6):
		await get_tree().process_frame
	print("ART_ANIM_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los assert (patrón NightGlareTest): si un
	# assert detiene el proceso en debug, el código de salida ya está fijado.
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Los asserts quedan como red de seguridad opcional. En la fase roja del
	# TDD se desactivan para que el log no contenga "SCRIPT ERROR: Assertion
	# failed": el código de salida ya lo gobierna _failures. Habilitar con
	# `-- --strict-assert` tras la ruta de la escena.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "ART_ANIM_TEST: " + f)

func _strict_assert_enabled() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--strict-assert":
			return true
	return false
