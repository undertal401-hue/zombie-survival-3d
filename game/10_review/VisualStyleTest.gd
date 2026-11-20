extends Node
## ============================================================================
## VISUAL STYLE TEST (R3 / ADR-006) — contrato de la PRESENTACIÓN del juego.
## ============================================================================
## ADR-005 sustituyó el contrato R1 «todos los personajes son cubos» por una
## presentación híbrida. ADR-006 (R3) la simplifica: el juego tiene UN SOLO
## arquetipo de zombi.
##
##   - El Player conserva el CUBO visible y su sprite oculta. No carga PNG.
##   - El zombi WALKER usa el skin pixel-art de 64x64: la AnimatedSprite2D
##     queda visible, Body/Nose quedan ocultos y las ocho animaciones
##     canónicas tienen frames reales.
##   - El perfil de jefe "Tanque Alfa" usa la MISMA skin (es el mismo zombi,
##     más grande): no hay una segunda familia de presentación.
##   - El CUBO es el FALLBACK (pack de skin ausente o incompleto), no la
##     presentación de otro arquetipo.
##   - No hay sombras falsas (`pixel_shadows`): la sombra nocturna es
##     proyectada de verdad (faro real) y la diurna son manchas ACOTADAS
##     (`SunShadowController`), porque la sombra direccional 2D de Godot llega
##     hasta el borde de pantalla.
##
## El banco de arte y el pipeline determinista se conservan como fuente del
## skin y como puertas de CI. La introspección es 100% dinámica (FileAccess /
## get / call): no referencia símbolos inexistentes y no produce Parse Error
## aunque el runtime no cumpla todavía el contrato.
## ============================================================================

const ART_BIBLE: String = "res://assets/art/ART_BIBLE.md"
const GEN_ART: String = "res://tools/gen_art.py"
const GEN_ZOMBIE_SKIN: String = "res://tools/gen_zombie_skin.py"
const SKIN_PACK_TOOL: String = "res://tools/skin_pack.py"
const SPRITES_DIR: String = "res://assets/art/sprites/"
const LIGHTS_DIR: String = "res://assets/art/lights/"
const SHADOWS_DIR: String = "res://assets/art/shadows/"
const ZOMBIE_SKIN_ROOT: String = "res://assets/enemies/zombie/"
const PLAYER_SCENE: String = "res://02_player/Player.tscn"
const ZOMBIE_SCENE: String = "res://03_zombies/Zombie.tscn"
const PLAYER_VISUAL: String = "res://02_player/PlayerVisual.gd"
const ZOMBIE_VISUAL: String = "res://03_zombies/ZombieVisual.gd"
const SOLAR_LIGHTING: String = "res://08_ui/SolarLighting.gd"
const SOLAR_SCENE: String = "res://08_ui/SolarLighting.tscn"

## Hojas del banco de arte tras R3: el jugador, el caminante, el jefe, los
## efectos y los tiles. Los sheets de los arquetipos eliminados se retiraron.
const EXPECTED_BANK_SHEETS: Array[String] = [
	"player_sheet.png", "zombie_walker.png", "boss_sheet.png",
	"effects.png", "tiles.png",
]

var _player_canonical: Array[String] = ["idle", "walk", "hurt", "death"]
var _player_attack_variants: Array[String] = [
	"attack", "attack_melee", "attack_pistol", "attack_shotgun", "attack_rifle"
]
var _zombie_canonical: Array[String] = [
	"idle", "walk", "run", "attack", "hit", "hurt", "death", "crawl"
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
		# El SpriteFrames de PlayerVisual se construye en _ready(); el skin del
		# WALKER se instala en el set_type() que hace Zombie.gd tras el _ready().
		await get_tree().process_frame
	_presentation_checks("Player", _player_inst, false)
	_presentation_checks("Zombie", _zombie_inst, true)
	_sprite_api_checks("Player", _player_inst, false, _player_canonical,
		_player_attack_variants, false)
	_sprite_api_checks("Zombie", _zombie_inst, true, _zombie_canonical,
		[] as Array[String], true)
	_runtime_asset_loading_checks()
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


# --- 2. Pipelines deterministas: tres puertas de solo verificación ----------

func _generator_checks() -> void:
	_run_generator_check(GEN_ART, PackedStringArray(["--check"]),
		"python3 tools/gen_art.py --check sale 0")
	_run_generator_check(GEN_ZOMBIE_SKIN, PackedStringArray(["--check"]),
		"python3 tools/gen_zombie_skin.py --check sale 0")
	_run_generator_check(SKIN_PACK_TOOL, PackedStringArray(["check"]),
		"python3 tools/skin_pack.py check sale 0")


func _run_generator_check(script_path: String, arguments: PackedStringArray,
		label: String) -> void:
	var exists: bool = FileAccess.file_exists(script_path)
	_check(exists, "existe %s" % script_path.get_file())
	if not exists:
		_check(false, label + " (script ausente)")
		_check(false, label.replace(" sale 0", " no escribe archivos") \
			+ " (script ausente)")
		return
	var before: Array[String] = _snapshot_outputs()
	# Godot 4.7: OS.execute(path, arguments, output) -> int (exit code).
	var command: PackedStringArray = PackedStringArray()
	command.append(ProjectSettings.globalize_path(script_path))
	for argument in arguments:
		command.append(argument)
	var output: Array = []
	var code: int = OS.execute("python3", command, output)
	_check(code == 0, "%s (exit=%d)" % [label, code])
	var after: Array[String] = _snapshot_outputs()
	_check(before == after,
		"%s no escribe archivos" % label.replace(" sale 0", ""))


# --- 3. Assets: 5 hojas (banco) + 2 mapas de luz + 1 mascara de sombra -----

func _asset_checks() -> void:
	var pngs: Array[String] = []
	_collect_files(SPRITES_DIR, pngs, ".png")
	_check(pngs.size() == EXPECTED_BANK_SHEETS.size(),
		"el banco de arte tiene exactamente %d hojas (encontradas %d)" % [
			EXPECTED_BANK_SHEETS.size(), pngs.size()])
	for sheet in EXPECTED_BANK_SHEETS:
		_check(FileAccess.file_exists(SPRITES_DIR.path_join(sheet)),
			"el banco de arte conserva %s" % sheet)
	# R3: el repo ya no fabrica ni distribuye arte de arquetipos que no
	# existen en el juego.
	for dead_sheet in ["zombie_runner.png", "zombie_tank.png",
			"zombie_spitter.png", "zombie_screamer.png"]:
		_check(not FileAccess.file_exists(SPRITES_DIR.path_join(dead_sheet)),
			"el banco de arte ya no tiene %s (arquetipo eliminado)" % dead_sheet)
	var lights: Array[String] = []
	_collect_files(LIGHTS_DIR, lights, ".png")
	_check(lights.size() >= 2,
		"al menos 2 mapas de luz PNG (cono + halo) (encontrados %d)" % lights.size())
	_check(FileAccess.file_exists("res://assets/art/lights/light_cone.png"),
		"existe el mapa del cono de faro")
	_check(FileAccess.file_exists("res://assets/art/lights/light_halo.png"),
		"existe el mapa del halo del jugador")
	# R3: la mascara de la sombra diurna acotada.
	var shadows: Array[String] = []
	_collect_files(SHADOWS_DIR, shadows, ".png")
	_check(shadows.size() >= 1,
		"existe la mascara de la sombra solar acotada (encontradas %d)" % shadows.size())
	_check(FileAccess.file_exists("res://assets/art/shadows/sun_shadow.png"),
		"existe assets/art/shadows/sun_shadow.png")


func _snapshot_outputs() -> Array[String]:
	# Solo las superficies que los generadores pueden escribir; se evita
	# snapshottear res:// completa porque el propio importador toca .godot/.
	#
	# Se comparan RUTA + TAMANO + mtime: comparar solo la lista de rutas no
	# detectaria una reescritura con bytes identicos. Se excluyen
	# `__pycache__/` y los `.pyc`: son artefactos de Python, NO salidas del
	# pipeline, y el propio test los crea al ejecutar `python3` (en un
	# checkout limpio la comparacion fallaria sin motivo).
	var files: Array[String] = []
	_collect_files("res://assets/art/", files, "")
	_collect_files("res://assets/enemies/", files, "")
	_collect_files("res://tools/", files, "")
	files.sort()
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
				if entry != "__pycache__":
					_collect_files(child, out, filter)
			elif not entry.ends_with(".pyc") and \
					(filter.is_empty() or entry.ends_with(filter)):
				out.append("%s|%d|%d" % [
					child,
					FileAccess.get_size(child),
					FileAccess.get_modified_time(child),
				])
		entry = dir.get_next()
	dir.list_dir_end()


# --- 4. Presentación: Player=cubo; el zombi (y su perfil de jefe)=skin ------

func _presentation_checks(actor: String, inst: Node, expect_skin: bool) -> void:
	if inst == null:
		_check(false, "%s: escena instanciable" % actor)
		return
	var body: Polygon2D = inst.get_node_or_null("Body") as Polygon2D
	var nose: Polygon2D = inst.get_node_or_null("Nose") as Polygon2D
	var sprite: AnimatedSprite2D = _find_sprite(inst)
	_check(body != null, "%s: existe el cubo 'Body' (Polygon2D)" % actor)
	_check(nose != null, "%s: existe el cubo 'Nose' (Polygon2D)" % actor)
	if body != null:
		_check(body.polygon.size() >= 4, "%s: el cubo Body tiene geometría" % actor)
	if expect_skin:
		var visual: Node = inst.get_node_or_null("ZombieVisual")
		var uses_skin: bool = visual != null and visual.has_method("uses_skin") \
			and bool(visual.call("uses_skin"))
		_check(uses_skin, "Zombie: el WALKER declara uses_skin() == true")
		_check(sprite != null and sprite.visible,
			"Zombie: la sprite del WALKER está VISIBLE")
		_check(body == null or not body.visible,
			"Zombie: el cubo Body del WALKER está oculto")
		_check(nose == null or not nose.visible,
			"Zombie: el cubo Nose del WALKER está oculto")
		_check(not (sprite != null and sprite.visible \
			and (body != null and body.visible or nose != null and nose.visible)),
			"Zombie: skin y cubo nunca son visibles a la vez")
	else:
		_check(body != null and body.visible,
			"Player: el cubo Body está VISIBLE (no se oculta)")
		_check(nose != null and nose.visible,
			"Player: el cubo Nose está VISIBLE (no se oculta)")
		_check(sprite != null and not sprite.visible,
			"Player: la sprite de frames está oculta (se ve el cubo)")


# --- 5. API de sprites: el Player queda preparado; el WALKER ya tiene frames --

func _sprite_api_checks(actor: String, inst: Node, expected_visible: bool,
		canonical: Array[String], attack_variants: Array[String],
		require_frames: bool) -> void:
	if inst == null:
		return
	var sprite: AnimatedSprite2D = _find_sprite(inst)
	_check(sprite != null, "%s: nodo AnimatedSprite2D presente" % actor)
	if sprite == null:
		return
	_check(sprite.visible == expected_visible,
		"%s: la visibilidad de la sprite coincide con el contrato híbrido" % actor)
	var frames: Object = sprite.get("sprite_frames") as Object
	var names: Array[String] = _animation_names(frames, canonical + attack_variants)
	for needed in canonical:
		_check(names.has(needed),
			"%s: sprite_frames conserva la animación '%s'" % [actor, needed])
		if require_frames and frames != null:
			var count: int = int(frames.call("get_frame_count", StringName(needed)))
			_check(count > 0,
				"%s: la animación '%s' tiene frames reales" % [actor, needed])
	if not attack_variants.is_empty():
		var has_attack: bool = false
		for candidate in attack_variants:
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


func _animation_names(frames: Object, candidates: Array[String]) -> Array[String]:
	var out: Array[String] = []
	if frames == null or not frames.has_method("has_animation"):
		return out
	for candidate in candidates:
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


# --- 6. Carga de assets en runtime: solo el skin canónico del zombi ---------

func _runtime_asset_loading_checks() -> void:
	var pv: String = _read(PLAYER_VISUAL)
	var zv: String = _read(ZOMBIE_VISUAL)
	_check(not pv.contains("player_sheet.png"),
		"PlayerVisual.gd: no carga la hoja PNG en runtime")
	_check(zv.contains(ZOMBIE_SKIN_ROOT),
		"ZombieVisual.gd: carga la raíz canónica del skin %s" % ZOMBIE_SKIN_ROOT)
	_check(not zv.contains("~/zombie_sprites"),
		"ZombieVisual.gd: no referencia el pack externo ~/zombie_sprites")
	_check(not zv.contains("zombie_walker.png") and not zv.contains("zombie_sheet"),
		"ZombieVisual.gd: no carga zombie_walker.png ni zombie_sheet")
	var asset_paths: Array[String] = _asset_paths(zv)
	for path in asset_paths:
		_check(path.begins_with(ZOMBIE_SKIN_ROOT),
			"ZombieVisual.gd: la ruta de asset '%s' está bajo la raíz canónica" % path)
	_check(not _has_absolute_path(zv),
		"ZombieVisual.gd: no contiene rutas absolutas")
	_check(pv.contains("USE_SPRITE_ART") and zv.contains("USE_SPRITE_ART"),
		"PlayerVisual/ZombieVisual: interruptor USE_SPRITE_ART")


func _asset_paths(source: String) -> Array[String]:
	var expression: RegEx = RegEx.new()
	expression.compile("res://assets/[A-Za-z0-9_./-]+")
	var paths: Array[String] = []
	for result in expression.search_all(source):
		paths.append(result.get_string())
	return paths


func _has_absolute_path(source: String) -> bool:
	var unix_absolute: RegEx = RegEx.new()
	unix_absolute.compile("[\"']\\s*/[^/\\s]")
	if unix_absolute.search(source) != null:
		return true
	var windows_absolute: RegEx = RegEx.new()
	windows_absolute.compile("[\"'][A-Za-z]:[\\\\/]")
	return windows_absolute.search(source) != null


# --- 7. Sin sombras falsas --------------------------------------------------

func _no_fake_shadows_checks() -> void:
	for path in [PLAYER_SCENE, ZOMBIE_SCENE]:
		var src: String = _read(path)
		_check(not src.contains("pixel_shadows"),
			"%s: sin grupo 'pixel_shadows' (sombras falsas eliminadas)" % path.get_file())
	var solar_src: String = _read(SOLAR_LIGHTING)
	_check(not solar_src.contains("PixelShadowController"),
		"SolarLighting.gd: fuera del PixelShadowController (sombras proyectadas reales)")
	# R3: la sombra DIURNA es acotada (manchas) y la NOCTURNA es real (faro).
	_check(FileAccess.file_exists("res://08_ui/SunShadowController.gd"),
		"existe el controlador de sombras solares acotadas")
	var solar_scene: String = _read(SOLAR_SCENE)
	_check(solar_scene.contains("[node name=\"SunShadows\" type=\"Node2D\""),
		"SolarLighting.tscn: monta el controlador de sombras acotadas")
	_check(solar_scene.contains("shadow_enabled = false"),
		"SolarLighting.tscn: el sol no proyecta la sombra direccional ilimitada")


# --- 8. Faro real y acabado nocturno ----------------------------------------

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
	for failure in _failures:
		print("  - " + failure)
	# Salida programada ANTES de los asserts (patrón NightGlareTest): si un
	# assert detiene el proceso en debug, el código de salida ya está fijado.
	get_tree().quit(1 if not _failures.is_empty() else 0)
	# Los asserts quedan como red de seguridad opcional. En la fase roja del
	# TDD se desactivan para que el log no contenga "SCRIPT ERROR: Assertion
	# failed": el código de salida ya lo gobierna _failures. Habilitar con
	# `-- --strict-assert` tras la ruta de la escena.
	if _strict_assert_enabled():
		for failure in _failures:
			assert(false, "VISUAL_STYLE_TEST: " + failure)


func _strict_assert_enabled() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--strict-assert":
			return true
	return false
