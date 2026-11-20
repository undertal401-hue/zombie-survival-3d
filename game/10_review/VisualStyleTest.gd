extends Node
## ============================================================================
## VISUAL STYLE TEST (R1) — contrato de la PRESENTACIÓN del juego.
## ============================================================================
## Sustituye a ArtAnimTest.gd, que codificaba una decisión RECHAZADA por el
## usuario (pixel art obligatorio en pantalla). R1 (2026-11-20):
##
##   - El personaje se queda como CUBO (Polygon2D). El usuario hará el arte.
##   - Las hojas PNG y tools/gen_art.py SE CONSERVAN como banco de trabajo
##     (pipeline determinista, `--check` en CI), pero NO se usan en runtime.
##   - No hay sombras falsas (`pixel_shadows`): la sombra es proyectada de verdad.
##   - Hay faro real (PointLight2D con cono) y capa de acabado nocturna.
##
## Introspección 100% dinámica (FileAccess / get / call). No referencia
## símbolos inexistentes: no produce Parse Error aunque el contrato no esté
## implementado.
## ============================================================================

const ART_BIBLE: String = "res://assets/art/ART_BIBLE.md"
const GEN_ART: String = "res://tools/gen_art.py"
const SPRITES_DIR: String = "res://assets/art/sprites/"
const LIGHTS_DIR: String = "res://assets/art/lights/"
const PLAYER_SCENE: String = "res://02_player/Player.tscn"
const ZOMBIE_SCENE: String = "res://03_zombies/Zombie.tscn"
const PLAYER_VISUAL: String = "res://02_player/PlayerVisual.gd"
const ZOMBIE_VISUAL: String = "res://03_zombies/ZombieVisual.gd"
const SOLAR_LIGHTING: String = "res://08_ui/SolarLighting.gd"
const SOLAR_SCENE: String = "res://08_ui/SolarLighting.tscn"

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
	_asset_checks()
	_player_inst = _instantiate(PLAYER_SCENE)
	_zombie_inst = _instantiate(ZOMBIE_SCENE)
	if _player_inst != null or _zombie_inst != null:
		# El SpriteFrames de PlayerVisual se construye en _ready().
		await get_tree().process_frame
	_cube_checks("Player", _player_inst)
	_cube_checks("Zombie", _zombie_inst)
	_sprite_api_checks("Player", _player_inst)
	_sprite_api_checks("Zombie", _zombie_inst)
	_no_fake_shadows_checks()
	_real_lighting_checks()
	await _finish()

# --- 1. El banco de arte se conserva (para el arte futuro del usuario) ---------

func _bible_checks() -> void:
	var text: String = _read(ART_BIBLE)
	_check(FileAccess.file_exists(ART_BIBLE),
		"existe assets/art/ART_BIBLE.md (banco de arte futuro)")
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

# --- 3. Assets: 9 hojas (banco) + 2 mapas de luz (runtime) -------------------

func _asset_checks() -> void:
	var pngs: Array[String] = []
	_collect_files(SPRITES_DIR, pngs, ".png")
	_check(pngs.size() >= 9,
		"al menos 9 PNG de sprites conservados como banco de arte (encontrados %d)" % pngs.size())
	var lights: Array[String] = []
	_collect_files(LIGHTS_DIR, lights, ".png")
	_check(lights.size() >= 2,
		"al menos 2 mapas de luz PNG (cono + halo) (encontrados %d)" % lights.size())
	_check(FileAccess.file_exists("res://assets/art/lights/light_cone.png"),
		"existe el mapa del cono de faro")
	_check(FileAccess.file_exists("res://assets/art/lights/light_halo.png"),
		"existe el mapa del halo del jugador")

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

# --- 4. El CUBO es lo que se ve ----------------------------------------------

func _cube_checks(actor: String, inst: Node) -> void:
	if inst == null:
		_check(false, "%s: escena instanciable" % actor)
		return
	var body: Polygon2D = inst.get_node_or_null("Body") as Polygon2D
	var nose: Polygon2D = inst.get_node_or_null("Nose") as Polygon2D
	_check(body != null, "%s: existe el cubo 'Body' (Polygon2D)" % actor)
	_check(nose != null, "%s: existe el cubo 'Nose' (Polygon2D)" % actor)
	if body != null:
		_check(body.visible, "%s: el cubo Body está VISIBLE (no se oculta)" % actor)
		_check(body.polygon.size() >= 4, "%s: el cubo Body tiene geometría" % actor)
	if nose != null:
		_check(nose.visible, "%s: el cubo Nose está VISIBLE (no se oculta)" % actor)

# --- 5. La API de sprites queda lista para el arte futuro --------------------

func _sprite_api_checks(actor: String, inst: Node) -> void:
	if inst == null:
		return
	var sprite: AnimatedSprite2D = _find_sprite(inst)
	_check(sprite != null, "%s: nodo AnimatedSprite2D presente (API para el arte futuro)" % actor)
	if sprite == null:
		return
	_check(not sprite.visible,
		"%s: la sprite de frames está oculta (se ve el cubo)" % actor)
	var frames: Object = sprite.get("sprite_frames") as Object
	var names: Array[String] = _animation_names(frames)
	for needed in _canonical:
		_check(names.has(needed),
			"%s: sprite_frames conserva la animación '%s' para el arte futuro" % [actor, needed])
	var has_attack: bool = false
	for candidate in _attack_variants:
		if names.has(candidate):
			has_attack = true
			break
	_check(has_attack,
		"%s: sprite_frames conserva una animación attack* para el arte futuro" % actor)
	_check(_nearest_filter(sprite),
		"%s: texture_filter NEAREST (o material equivalente)" % actor)

func _instantiate(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	get_tree().root.add_child(inst)
	return inst

func _find_sprite(inst: Node) -> AnimatedSprite2D:
	if inst == null:
		return null
	var all: Array = inst.find_children("*", "AnimatedSprite2D", true, false)
	if all.is_empty():
		return null
	return all[0] as AnimatedSprite2D

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

# --- 6. Ningún PNG de sprites se carga en runtime ---------------------------

func _no_fake_shadows_checks() -> void:
	for path in [PLAYER_SCENE, ZOMBIE_SCENE]:
		var src: String = _read(path)
		_check(not src.contains("pixel_shadows"),
			"%s: sin grupo 'pixel_shadows' (sombras falsas eliminadas)" % path.get_file())
	var solar_src: String = _read(SOLAR_LIGHTING)
	_check(not solar_src.contains("PixelShadowController"),
		"SolarLighting.gd: fuera el PixelShadowController (sombras proyectadas reales)")
	var pv: String = _read(PLAYER_VISUAL)
	var zv: String = _read(ZOMBIE_VISUAL)
	_check(not pv.contains("player_sheet.png"),
		"PlayerVisual.gd: no carga la hoja PNG en runtime")
	_check(not zv.contains("zombie_walker.png") and not zv.contains("zombie_sheet"),
		"ZombieVisual.gd: no carga la hoja PNG en runtime")
	_check(pv.contains("USE_SPRITE_ART") and zv.contains("USE_SPRITE_ART"),
		"PlayerVisual/ZombieVisual: interruptor USE_SPRITE_ART para el arte futuro")

# --- 7. Faro real y acabado nocturna ----------------------------------------

func _real_lighting_checks() -> void:
	var player_src: String = _read(PLAYER_SCENE)
	_check(player_src.contains("Flashlight"), "Player.tscn: nodo Flashlight (PointLight2D)")
	_check(player_src.contains("MuzzleLight"), "Player.tscn: nodo MuzzleLight (fogonazo)")
	_check(player_src.contains("shadow_enabled = true"),
		"Player.tscn: el faro proyecta sombras reales")
	_check(FileAccess.file_exists("res://assets/shaders/NightGrade.gdshader"),
		"existe el shader NightGrade.gdshader")
	_check(FileAccess.file_exists("res://08_ui/NightGradeMaterial.tres"),
		"existe el material NightGradeMaterial.tres")
	var solar_scene: String = _read(SOLAR_SCENE)
	_check(solar_scene.contains("NightGradeRect"),
		"SolarLighting.tscn: la capa NightGradeRect está montada")

# --- Cierre ------------------------------------------------------------------

func _finish() -> void:
	for inst in [_player_inst, _zombie_inst]:
		if is_instance_valid(inst):
			inst.queue_free()
	for i in range(6):
		await get_tree().process_frame
	print("VISUAL_STYLE_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	# Salida programada ANTES de los asserts (patrón NightGlareTest): si un
	# assert detiene el proceso en debug, el código de salida ya está fijado.
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Los asserts quedan como red de seguridad opcional. En la fase roja del
	# TDD se desactivan para que el log no contenga "SCRIPT ERROR: Assertion
	# failed": el código de salida ya lo gobierna _failures. Habilitar con
	# `-- --strict-assert` tras la ruta de la escena.
	if _strict_assert_enabled():
		for f in _failures:
			assert(false, "VISUAL_STYLE_TEST: " + f)

func _strict_assert_enabled() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--strict-assert":
			return true
	return false
