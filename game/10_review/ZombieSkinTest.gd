extends Node
## ============================================================================
## ZOMBIE SKIN TEST (ADR-005) — contrato integral del skin de zombi.
## ============================================================================
## Cubre dos capas que no pueden separarse:
##
##   1. INTEGRIDAD DEL PACK en disco: 33 frames sueltos, 8 strips, celdas de
##      64x64, recuento exacto, paletas/centrado/anclaje y las dos puertas
##      deterministas (`gen_zombie_skin.py --check` y `skin_pack.py check`).
##   2. RUNTIME HÍBRIDO: el WALKER muestra la skin y aplica los FX a la
##      sprite; los rangos altos conservan el cubo; el fallback al cubo es
##      seguro y reversible.
##
## El arnés imprime el recuento antes de salir y solo usa asserts si se pasa
## `-- --strict-assert`. Un fallo se convierte en `FAIL <etiqueta>` y en un
## código de salida 1, sin detener Godot en debug.
## ============================================================================

const ZOMBIE_SCENE: String = "res://03_zombies/Zombie.tscn"
const ART_BIBLE: String = "res://assets/art/ART_BIBLE.md"
const SKIN_DIR: String = "res://assets/enemies/zombie/"
const GEN_ZOMBIE_SKIN: String = "res://tools/gen_zombie_skin.py"
const SKIN_PACK_TOOL: String = "res://tools/skin_pack.py"
const CELL: int = 64

## Pack de regresion: los ocho strips del contrato, pero con `idle_strip.png`
## de 64x64 en vez de 128x64 (una celda en vez de dos). El runtime construye
## una region `Rect2(i*64, 0, 64, 64)` por frame, asi que con este strip el
## segundo frame caeria FUERA del atlas. Un pack estructuralmente invalido
## debe producir el fallback al cubo, no una animacion rota.
const BAD_STRIP_PACK: String = "res://10_review/fixtures/bad_strip_pack/"

## Recuento del pack, independiente del mapa canónico del runtime.
const PACK_COUNTS: Dictionary = {
	"idle": 2,
	"walk": 5,
	"walk_alt": 3,
	"attack": 6,
	"attack_alt": 2,
	"rise": 5,
	"death": 6,
	"special": 4,
}

## Las ocho animaciones canónicas que siempre presenta el runtime.
const CANONICAL_COUNTS: Dictionary = {
	"idle": 2,
	"walk": 5,
	"run": 3,
	"attack": 6,
	"hit": 2,
	"hurt": 4,
	"death": 6,
	"crawl": 5,
}

## Fps y bucle de cada animación canónica CON skin. Son el contrato del pack
## (ADR-005 §3.1): el runtime y el generador son dos fuentes de verdad
## independientes, así que esta tabla es la que detecta una desincronización
## entre ellos (cambiar el fps de un lado y no del otro).
const CANONICAL_FPS: Dictionary = {
	"idle": 4.0,
	"walk": 8.0,
	"run": 12.0,
	"attack": 12.0,
	"hit": 10.0,
	"hurt": 10.0,
	"death": 7.0,
	"crawl": 8.0,
}

const CANONICAL_LOOP: Dictionary = {
	"idle": true,
	"walk": true,
	"run": true,
	"attack": false,
	"hit": false,
	"hurt": false,
	"death": false,
	"crawl": true,
}

var _failures: Array[String] = []
var _instances: Array[Node] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_pack_integrity_checks()
	_generator_checks()
	await _runtime_checks()
	await _cleanup()
	print("ZOMBIE_SKIN_TEST failures=%d" % _failures.size())
	for failure in _failures:
		print("  - " + failure)
	# La salida queda fijada ANTES de los asserts opcionales.
	get_tree().quit(1 if not _failures.is_empty() else 0)
	_asserts()


## ---------------------------------------------------------------------------
## A. Integridad del pack en disco.
## ---------------------------------------------------------------------------
func _pack_integrity_checks() -> void:
	_check(DirAccess.dir_exists_absolute(SKIN_DIR),
		"pack: existe la raíz %s" % SKIN_DIR)
	if not DirAccess.dir_exists_absolute(SKIN_DIR):
		return

	var union_bbox: Rect2i = Rect2i()
	var has_union: bool = false
	var palette: Dictionary = _canonical_palette()
	_check(palette.size() == 16,
		"pack: ART_BIBLE.md expone la paleta canónica de 16 colores")
	for pack_anim in PACK_COUNTS.keys():
		var anim: String = String(pack_anim)
		var expected_count: int = int(PACK_COUNTS[pack_anim])
		var anim_dir: String = SKIN_DIR.path_join(anim)
		_check(DirAccess.dir_exists_absolute(anim_dir),
			"pack: existe la carpeta de frames '%s'" % anim)

		var strip_path: String = SKIN_DIR.path_join(anim + "_strip.png")
		_check(ResourceLoader.exists(strip_path),
			"pack: existe el strip %s_strip.png" % anim)
		if ResourceLoader.exists(strip_path):
			var strip: Texture2D = load(strip_path) as Texture2D
			_check(strip != null, "pack: %s_strip.png se puede cargar" % anim)
			if strip != null:
				_check(strip.get_height() == CELL,
					"pack: %s_strip.png alto 64 (actual %d)" % [anim, strip.get_height()])
				_check(strip.get_width() % CELL == 0,
					"pack: %s_strip.png ancho múltiplo exacto de 64 (actual %d)" % [
						anim, strip.get_width()])
				_check(strip.get_width() / CELL == expected_count,
					"pack: %s_strip.png tiene %d celdas" % [anim, expected_count])

		var actual_names: Array[String] = _png_names(anim_dir)
		var expected_names: Array[String] = []
		for index in range(expected_count):
			expected_names.append("%s_%02d.png" % [anim, index + 1])
		expected_names.sort()
		actual_names.sort()
		_check(actual_names == expected_names,
			"pack: %s tiene exactamente %d frames con los nombres contractuales" % [
				anim, expected_count])

		for frame_name in expected_names:
			var frame_path: String = anim_dir.path_join(frame_name)
			if not ResourceLoader.exists(frame_path):
				_check(false, "pack: existe el frame %s/%s" % [anim, frame_name])
				continue
			var texture: Texture2D = load(frame_path) as Texture2D
			_check(texture != null, "pack: %s/%s se puede cargar" % [anim, frame_name])
			if texture == null:
				continue
			_check(texture.get_width() == CELL and texture.get_height() == CELL,
				"pack: %s/%s mide 64x64 (actual %dx%d)" % [
					anim, frame_name, texture.get_width(), texture.get_height()])
			if texture.get_width() != CELL or texture.get_height() != CELL:
				continue
			_check(_frame_uses_palette(texture, palette),
				"pack: %s/%s usa solo la paleta canónica" % [anim, frame_name])

			var bbox: Rect2i = _opaque_bbox(texture)
			_check(bbox.size.x > 0 and bbox.size.y > 0,
				"pack: %s/%s no está totalmente vacío" % [anim, frame_name])
			if bbox.size.x <= 0 or bbox.size.y <= 0:
				continue
			var center_x: float = float(bbox.position.x) + float(bbox.size.x) * 0.5
			_check(absf(center_x - float(CELL) * 0.5) <= 1.0,
				"pack: %s/%s centrado horizontalmente (centro %.1f)" % [
					anim, frame_name, center_x])
			var bottom_margin: int = CELL - (bbox.position.y + bbox.size.y)
			_check(bottom_margin >= 2,
				"pack: %s/%s deja margen inferior >=2 (actual %d)" % [
					anim, frame_name, bottom_margin])

			if not has_union:
				union_bbox = bbox
				has_union = true
			else:
				var left: int = mini(union_bbox.position.x, bbox.position.x)
				var top: int = mini(union_bbox.position.y, bbox.position.y)
				var right: int = maxi(union_bbox.position.x + union_bbox.size.x,
					bbox.position.x + bbox.size.x)
				var bottom: int = maxi(union_bbox.position.y + union_bbox.size.y,
					bbox.position.y + bbox.size.y)
				union_bbox = Rect2i(left, top, right - left, bottom - top)

	if has_union:
		var union_center_x: float = float(union_bbox.position.x) \
			+ float(union_bbox.size.x) * 0.5
		var union_center_y: float = float(union_bbox.position.y) \
			+ float(union_bbox.size.y) * 0.5
		_check(absf(union_center_x - float(CELL) * 0.5) <= 1.0,
			"pack: la unión global está centrada horizontalmente (centro %.1f)" % union_center_x)
		_check(absf(union_center_y - float(CELL) * 0.5) <= 1.0,
			"pack: la unión global está centrada verticalmente (centro %.1f)" % union_center_y)
	else:
		_check(false, "pack: la unión global de frames no está vacía")


func _png_names(path: String) -> Array[String]:
	var names: Array[String] = []
	if not DirAccess.dir_exists_absolute(path):
		return names
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not dir.current_is_dir() \
				and entry.ends_with(".png"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return names


func _opaque_bbox(texture: Texture2D) -> Rect2i:
	var image: Image = texture.get_image()
	if image == null:
		return Rect2i()
	var left: int = CELL
	var top: int = CELL
	var right: int = -1
	var bottom: int = -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			left = mini(left, x)
			top = mini(top, y)
			right = maxi(right, x + 1)
			bottom = maxi(bottom, y + 1)
	if right < 0 or bottom < 0:
		return Rect2i()
	return Rect2i(left, top, right - left, bottom - top)


func _canonical_palette() -> Dictionary:
	var palette: Dictionary = {}
	if not FileAccess.file_exists(ART_BIBLE):
		return palette
	var expression: RegEx = RegEx.new()
	expression.compile("#[0-9a-fA-F]{6}")
	var text: String = FileAccess.get_file_as_string(ART_BIBLE)
	for result in expression.search_all(text):
		palette[result.get_string().trim_prefix("#").to_lower()] = true
	return palette


func _frame_uses_palette(texture: Texture2D, palette: Dictionary) -> bool:
	if palette.is_empty():
		return false
	var image: Image = texture.get_image()
	if image == null:
		return false
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			if color.a <= 0.0:
				continue
			var key: String = "%02x%02x%02x" % [
				int(round(color.r * 255.0)),
				int(round(color.g * 255.0)),
				int(round(color.b * 255.0)),
			]
			if not palette.has(key):
				return false
	return true


## ---------------------------------------------------------------------------
## Puertas deterministas: ambas deben salir 0 y no escribir ningún asset.
## ---------------------------------------------------------------------------
func _generator_checks() -> void:
	_run_generator_check(GEN_ZOMBIE_SKIN, PackedStringArray(["--check"]),
		"python3 tools/gen_zombie_skin.py --check sale 0")
	_run_generator_check(SKIN_PACK_TOOL, PackedStringArray(["check"]),
		"python3 tools/skin_pack.py check sale 0")
	# Autopruebas del importador: rechazan los packs sin silueta, bloquean
	# la escritura fuera del destino por symlinks y diagnostican los PNG
	# corruptos. Trabajo en un directorio temporal, fuera de res://.
	_run_generator_check(SKIN_PACK_TOOL, PackedStringArray(["selftest"]),
		"python3 tools/skin_pack.py selftest sale 0")


func _run_generator_check(script_path: String, arguments: PackedStringArray,
		label: String) -> void:
	var exists: bool = FileAccess.file_exists(script_path)
	_check(exists, "existe %s" % script_path.get_file())
	if not exists:
		_check(false, label + " (script ausente)")
		_check(false, label.replace("sale 0", "no escribe archivos") \
			+ " (script ausente)")
		return
	var before: Array[String] = _snapshot_outputs()
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


## Instantanea las superficies que los generadores pueden escribir.
##
## Se comparan RUTA + TAMANO + mtime: comparar solo la lista de rutas no
## detectaria una reescritura con bytes identicos.
##
## Se excluyen `__pycache__/` y los `.pyc`: son artefactos de Python, NO
## salidas del pipeline. El propio test los crea al ejecutar `python3`, de
## modo que en un checkout limpio la comparacion fallaria sin que las
## herramientas hubiesen escrito nada.
func _snapshot_outputs() -> Array[String]:
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


## ---------------------------------------------------------------------------
## B-G. Runtime: skin, rangos altos, fallback, FX, estados, orientación e hit.
## ---------------------------------------------------------------------------
func _runtime_checks() -> void:
	await _runtime_with_skin_checks()
	await _boss_profile_skin_checks()
	await _fallback_checks()
	await _malformed_pack_checks()
	await _visible_fx_checks()
	await _death_cancels_fx_checks()
	await _state_orientation_checks()
	await _hit_lock_checks()


func _runtime_with_skin_checks() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "runtime: Zombie.tscn se puede instanciar")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	var sprite: AnimatedSprite2D = zombie.get_node_or_null(
		"ZombieVisual/AnimatedSprite2D") as AnimatedSprite2D
	var body: Polygon2D = zombie.get_node_or_null("Body") as Polygon2D
	var nose: Polygon2D = zombie.get_node_or_null("Nose") as Polygon2D
	if visual == null or sprite == null or body == null or nose == null:
		_check(false, "runtime: el WALKER expone ZombieVisual, sprite, Body y Nose")
		return

	_check(_call_bool(visual, "uses_skin"),
		"runtime WALKER: uses_skin() es true")
	_check(_call_bool(visual, "has_skin"),
		"runtime WALKER: has_skin() es true")
	_check(sprite.visible, "runtime WALKER: la AnimatedSprite2D está visible")
	_check(not body.visible and not nose.visible,
		"runtime WALKER: Body y Nose están ocultos con skin")
	_check(not (sprite.visible and (body.visible or nose.visible)),
		"runtime WALKER: la visibilidad de skin y cubo es exclusiva")

	var frames: SpriteFrames = sprite.sprite_frames
	_check(frames != null, "runtime WALKER: existe SpriteFrames")
	if frames == null:
		return
	for canonical in CANONICAL_COUNTS.keys():
		var anim: String = String(canonical)
		var expected_count: int = int(CANONICAL_COUNTS[canonical])
		_check(frames.has_animation(anim),
			"runtime WALKER: existe la animación canónica '%s'" % anim)
		if not frames.has_animation(anim):
			continue
		# Fps y bucle del pack: dos fuentes de verdad (runtime y generador)
		# tienen que coincidir. Sin esta comprobacion, cambiar el fps en un
		# solo sitio no lo detectaria ninguna puerta.
		var expected_fps: float = float(CANONICAL_FPS.get(anim, 0.0))
		_check(is_equal_approx(frames.get_animation_speed(StringName(anim)),
				expected_fps),
			"runtime WALKER: '%s' usa %.0f fps (contrato del pack)" % [
				anim, expected_fps])
		_check(frames.get_animation_loop(StringName(anim)) ==
				bool(CANONICAL_LOOP.get(anim, false)),
			"runtime WALKER: '%s' %s en bucle (contrato del pack)" % [
				anim,
				"va" if bool(CANONICAL_LOOP.get(anim, false)) else "no va"])
		var actual_count: int = frames.get_frame_count(StringName(anim))
		_check(actual_count == expected_count,
			"runtime WALKER: '%s' tiene %d frames" % [anim, expected_count])
		if actual_count != expected_count:
			continue
		var atlas_regions_ok: bool = true
		for index in range(actual_count):
			var texture: Texture2D = frames.get_frame_texture(StringName(anim), index)
			if not texture is AtlasTexture:
				atlas_regions_ok = false
				continue
			var atlas: AtlasTexture = texture as AtlasTexture
			if atlas.atlas == null or not atlas.region.size.is_equal_approx(Vector2(CELL, CELL)) \
					or not is_equal_approx(atlas.region.position.x, float(index * CELL)) \
					or not is_equal_approx(atlas.region.position.y, 0.0):
				atlas_regions_ok = false
		_check(atlas_regions_ok,
			"runtime WALKER: cada frame de '%s' es AtlasTexture 64x64 en x=i*64" % anim)

	_check(int(sprite.texture_filter) == CanvasItem.TEXTURE_FILTER_NEAREST,
		"runtime WALKER: texture_filter NEAREST (valor 1)")
	_check(sprite.centered,
		"runtime WALKER: la sprite está centrada en su origen (pivot 0.5,0.5)")
	_check(_vector_close(sprite.offset, Vector2.ZERO, 0.0001),
		"runtime WALKER: offset == (0,0)")
	_check(_vector_close(sprite.scale, Vector2(0.5, 0.5), 0.0001),
		"runtime WALKER: scale == (0.5,0.5)")
	_check(sprite.z_index == 0, "runtime WALKER: z_index == 0")

	var second_zombie: Node = await _instantiate_zombie()
	if second_zombie == null:
		_check(false, "runtime: se puede instanciar un segundo WALKER")
		return
	var second_sprite: AnimatedSprite2D = second_zombie.get_node_or_null(
		"ZombieVisual/AnimatedSprite2D") as AnimatedSprite2D
	_check(second_sprite != null and second_sprite.sprite_frames != null \
			and second_sprite.sprite_frames != frames,
		"runtime: cada WALKER tiene su propio objeto SpriteFrames")


## R3 (ADR-006): ya NO hay rangos altos con presentacion propia. El unico
## arquetipo es el WALKER y el jefe "Tanque Alfa" es un PERFIL del mismo zombi:
## usa la MISMA skin, solo que mas grande. El cubo queda como FALLBACK.
func _boss_profile_skin_checks() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "runtime: se puede instanciar un zombi para el perfil de jefe")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	var sprite: AnimatedSprite2D = zombie.get_node_or_null(
		"ZombieVisual/AnimatedSprite2D") as AnimatedSprite2D
	var body: Polygon2D = zombie.get_node_or_null("Body") as Polygon2D
	var nose: Polygon2D = zombie.get_node_or_null("Nose") as Polygon2D
	if visual == null or sprite == null or body == null or nose == null:
		_check(false, "runtime: el perfil de jefe expone los nodos visuales")
		return
	# Tipo 1 = BOSS (el unico perfil que queda).
	visual.call("set_type", 1)
	await get_tree().process_frame
	_check(_call_bool(visual, "uses_skin"),
		"runtime jefe: uses_skin() es true (misma skin que el caminante)")
	_check(sprite.visible and not body.visible and not nose.visible,
		"runtime jefe: la skin es la presentacion visible")
	_check(_vector_close(sprite.scale, Vector2(0.95, 0.95), 0.0001),
		"runtime jefe: el perfil se presenta mas grande (0.95)")
	# El unico arquetipo sigue siendo el caminante: al volver, la skin del
	# caminante se restaura con su escala.
	visual.call("set_type", 0)
	await get_tree().process_frame
	_check(_call_bool(visual, "uses_skin"),
		"runtime: al volver a WALKER el skin vuelve")
	_check(sprite.visible and not body.visible and not nose.visible,
		"runtime: al volver a WALKER la skin vuelve a ser la presentación visible")
	_check(_vector_close(sprite.scale, Vector2(0.5, 0.5), 0.0001),
		"runtime: al volver a WALKER la escala vuelve a la del caminante")


func _fallback_checks() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "runtime: se puede instanciar un zombi para el fallback")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	var sprite: AnimatedSprite2D = zombie.get_node_or_null(
		"ZombieVisual/AnimatedSprite2D") as AnimatedSprite2D
	var body: Polygon2D = zombie.get_node_or_null("Body") as Polygon2D
	var nose: Polygon2D = zombie.get_node_or_null("Nose") as Polygon2D
	if visual == null or sprite == null or body == null or nose == null:
		_check(false, "runtime: el fallback encuentra los nodos visuales")
		return

	var bad_result: bool = _call_bool(visual, "install_skin",
		"res://assets/enemies/NO_EXISTE/")
	_check(not bad_result,
		"fallback: install_skin() con ruta inexistente devuelve false")
	visual.call("set_type", 0)
	await get_tree().process_frame
	_check(not _call_bool(visual, "uses_skin"),
		"fallback: tras la ruta inexistente el WALKER usa cubo")
	_check(body.visible and nose.visible and not sprite.visible,
		"fallback: el cubo queda visible y la sprite oculta")
	var fallback_frames: SpriteFrames = sprite.sprite_frames
	var no_partial_frames: bool = fallback_frames != null
	if fallback_frames != null:
		for canonical in CANONICAL_COUNTS.keys():
			if fallback_frames.get_frame_count(StringName(String(canonical))) != 0:
				no_partial_frames = false
				break
	_check(no_partial_frames,
		"fallback: SpriteFrames queda sin frames (no media skin colgada)")

	var good_result: bool = _call_bool(visual, "install_skin")
	_check(good_result, "fallback: install_skin() con la ruta por defecto devuelve true")
	var installed_frames: SpriteFrames = sprite.sprite_frames
	_check(installed_frames != null \
			and installed_frames.get_frame_count(StringName("idle")) == 2,
		"fallback: install_skin() correcto reinstala los frames")
	visual.call("set_type", 0)
	await get_tree().process_frame
	_check(_call_bool(visual, "uses_skin") and sprite.visible \
			and not body.visible and not nose.visible,
		"fallback: tras reinstalar el pack el skin vuelve a funcionar")


## Un pack con un strip de dimensiones incorrectas NO puede instalarse: el
## runtime construye una region por frame, asi que un strip corto deja los
## ultimos frames fuera del atlas. La garantia de fallback (ADR-005 §4) exige
## volver al cubo, no instalar una animacion estructuralmente rota.
func _malformed_pack_checks() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "runtime: se puede instanciar un zombi para el pack malformado")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	var sprite: AnimatedSprite2D = zombie.get_node_or_null(
		"ZombieVisual/AnimatedSprite2D") as AnimatedSprite2D
	var body: Polygon2D = zombie.get_node_or_null("Body") as Polygon2D
	var nose: Polygon2D = zombie.get_node_or_null("Nose") as Polygon2D
	if visual == null or sprite == null or body == null or nose == null:
		_check(false, "pack malformado: el zombi expone los nodos visuales")
		return

	_check(DirAccess.dir_exists_absolute(BAD_STRIP_PACK),
		"pack malformado: existe el fixture de regresion")
	_check(ResourceLoader.exists(BAD_STRIP_PACK.path_join("idle_strip.png")),
		"pack malformado: el fixture tiene el strip defectuoso")
	var bad_result: bool = _call_bool(visual, "install_skin", BAD_STRIP_PACK)
	_check(not bad_result,
		"pack malformado: install_skin() con un strip de ancho incorrecto devuelve false")
	_check(not _call_bool(visual, "uses_skin"),
		"pack malformado: el WALKER NO usa la skin invalida")
	_check(body.visible and nose.visible and not sprite.visible,
		"pack malformado: el cubo queda visible y la sprite oculta")
	var bad_frames: SpriteFrames = sprite.sprite_frames
	var no_residual_frames: bool = bad_frames != null
	if bad_frames != null:
		for canonical in CANONICAL_COUNTS.keys():
			if bad_frames.get_frame_count(StringName(String(canonical))) != 0:
				no_residual_frames = false
				break
	_check(no_residual_frames,
		"pack malformado: no quedan frames residuales del pack invalido")

	# Tras el rechazo, el pack canonico debe volver a instalarse sin problemas.
	var good_result: bool = _call_bool(visual, "install_skin")
	_check(good_result,
		"pack malformado: tras el rechazo el pack canonico se reinstala")


## La muerte cancela los FX: si el zombi muere durante una telegrafia o un
## squash, el tween seguiria deformando y tiñendo el cadaver mientras se
## reproduce el clip de muerte.
func _death_cancels_fx_checks() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "runtime: se puede instanciar un zombi para la muerte con FX")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	var sprite: AnimatedSprite2D = zombie.get_node_or_null(
		"ZombieVisual/AnimatedSprite2D") as AnimatedSprite2D
	if visual == null or sprite == null:
		_check(false, "muerte con FX: el zombi expone ZombieVisual y la sprite")
		return

	var base_modulate: Color = sprite.modulate
	visual.call("telegraph", 0)
	await get_tree().process_frame
	var live_tweens: Array = visual.get("_fx_tweens") as Array
	_check(live_tweens != null and live_tweens.size() == 1,
		"muerte con FX: telegraph() deja un tween vivo antes de morir")

	visual.call("play_death")
	await get_tree().process_frame
	var dead_tweens: Array = visual.get("_fx_tweens") as Array
	_check(dead_tweens != null and dead_tweens.is_empty(),
		"muerte con FX: play_death() cancela los tweens de FX")
	_check(not bool(visual.get("_is_telegraphing")),
		"muerte con FX: play_death() desactiva _is_telegraphing")
	_check(_vector_close(sprite.scale, Vector2(0.5, 0.5), 0.0001),
		"muerte con FX: play_death() restaura la escala base de la sprite")
	_check(_color_close(sprite.modulate, base_modulate, 0.0001),
		"muerte con FX: play_death() restaura el tinte base de la sprite")
	_check(sprite.animation == "death",
		"muerte con FX: play_death() reproduce el clip de muerte")


func _visible_fx_checks() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "runtime: se puede instanciar un zombi para los FX")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	var sprite: AnimatedSprite2D = zombie.get_node_or_null(
		"ZombieVisual/AnimatedSprite2D") as AnimatedSprite2D
	var body: Polygon2D = zombie.get_node_or_null("Body") as Polygon2D
	if visual == null or sprite == null or body == null:
		_check(false, "runtime: los FX encuentran los nodos visuales")
		return

	var sprite_base: Vector2 = sprite.scale
	visual.call("squash", 0.8, 0.12)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not _vector_close(sprite.scale, sprite_base, 0.0001),
		"FX WALKER: squash cambia la escala de la sprite visible")
	await _wait_for_fx_finish(visual)
	_check(_vector_close(sprite.scale, Vector2(0.5, 0.5), 0.0001),
		"FX WALKER: squash restaura la escala base de la sprite")

	var base_modulate: Color = sprite.modulate
	visual.call("telegraph", 0)
	var tweens: Array = visual.get("_fx_tweens") as Array
	_check(tweens != null and tweens.size() == 1,
		"FX WALKER: telegraph() crea exactamente un tween maestro")
	_check(bool(visual.get("_is_telegraphing")),
		"FX WALKER: telegraph() activa _is_telegraphing")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not _vector_close(sprite.scale, Vector2(0.5, 0.5), 0.0001),
		"FX WALKER: durante telegraph() cambia la escala de la sprite")
	_check(not _color_close(sprite.modulate, base_modulate, 0.0001),
		"FX WALKER: durante telegraph() cambia el tinte de la sprite")
	await _wait_for_fx_finish(visual)
	var finished_tweens: Array = visual.get("_fx_tweens") as Array
	_check(finished_tweens != null and finished_tweens.is_empty(),
		"FX WALKER: telegraph() termina sin tweens residuales")
	_check(not bool(visual.get("_is_telegraphing")),
		"FX WALKER: telegraph() desactiva _is_telegraphing al terminar")
	_check(_vector_close(sprite.scale, Vector2(0.5, 0.5), 0.0001),
		"FX WALKER: telegraph() restaura la escala base")
	_check(_color_close(sprite.modulate, base_modulate, 0.0001),
		"FX WALKER: telegraph() restaura el tinte base")

	# R3 (ADR-006): ya no hay arquetipos "altos" con el cubo como
	# presentacion propia. El cubo es el FALLBACK (pack ausente o
	# incompleto), y los FX tienen que aplicarse a lo que se VE.
	visual.call("install_skin", "res://assets/enemies/NO_EXISTE/")
	await get_tree().process_frame
	_check(not _call_bool(visual, "uses_skin"),
		"FX fallback: sin pack el zombi vuelve al cubo")
	var cube_base: Vector2 = body.scale
	var hidden_sprite_scale: Vector2 = sprite.scale
	visual.call("squash", 0.8, 0.12)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not _vector_close(body.scale, cube_base, 0.0001),
		"FX fallback: squash cambia la escala del cubo visible")
	_check(_vector_close(sprite.scale, hidden_sprite_scale, 0.0001),
		"FX fallback: squash no deforma la sprite oculta")
	await _wait_for_fx_finish(visual)
	_check(_vector_close(body.scale, cube_base, 0.0001),
		"FX fallback: squash restaura la escala base del cubo")


func _state_orientation_checks() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "runtime: se puede instanciar un zombi para los estados")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	var sprite: AnimatedSprite2D = zombie.get_node_or_null(
		"ZombieVisual/AnimatedSprite2D") as AnimatedSprite2D
	if visual == null or sprite == null:
		_check(false, "runtime: los estados encuentran ZombieVisual y la sprite")
		return

	visual.call("update_state", Vector2.ZERO, false, Vector2.ZERO, false)
	_check(sprite.animation == "idle", "estado: velocidad 0 reproduce 'idle'")
	visual.call("update_state", Vector2(60.0, 0.0), false, Vector2.RIGHT, false)
	_check(sprite.animation == "walk", "estado: velocidad 60 reproduce 'walk'")
	visual.call("update_state", Vector2(150.0, 0.0), false, Vector2.RIGHT, false)
	_check(sprite.animation == "run", "estado: velocidad 150 reproduce 'run'")
	visual.call("update_state", Vector2(60.0, 0.0), false, Vector2.RIGHT, true)
	_check(sprite.animation == "crawl", "estado: is_crawling reproduce 'crawl'")
	visual.call("update_state", Vector2.ZERO, false, Vector2.ZERO, true)
	_check(sprite.animation == "idle",
		"estado: is_crawling sin movimiento reproduce 'idle'")

	# Se aparta primero de PI/2 para comprobar una interpolación real hacia
	# la orientacion de marcha, no una igualdad accidental en el primer frame.
	visual.call("update_state", Vector2(0.0, 100.0), false, Vector2.DOWN, false)
	await _settle(0.35)
	var before_right: float = sprite.rotation
	visual.call("update_state", Vector2(100.0, 0.0), false, Vector2.RIGHT, false)
	await _settle(0.35)
	var after_right: float = sprite.rotation
	var before_distance: float = _angle_distance(before_right, PI * 0.5)
	var after_distance: float = _angle_distance(after_right, PI * 0.5)
	_check(after_distance < before_distance and after_distance < 0.4,
		"orientacion: la sprite gira hacia PI/2 (%.3f -> %.3f rad de error)" % [
			before_distance, after_distance])
	_check(not sprite.flip_h, "orientacion: flip_h es false con skin")


func _hit_lock_checks() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "runtime: se puede instanciar un zombi para el clip de hit")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	var sprite: AnimatedSprite2D = zombie.get_node_or_null(
		"ZombieVisual/AnimatedSprite2D") as AnimatedSprite2D
	if visual == null or sprite == null:
		_check(false, "runtime: el hit encuentra ZombieVisual y la sprite")
		return
	visual.call("play_hit")
	_check(sprite.animation == "hit", "hit: play_hit() reproduce el clip 'hit'")
	var hit_timer: float = float(visual.get("_hit_timer"))
	_check(hit_timer > 0.0, "hit: play_hit() activa el lock _hit_timer")
	visual.call("update_state", Vector2.ZERO, false, Vector2.ZERO, false)
	_check(sprite.animation == "hit",
		"hit: el lock impide que update_state() pise el clip con 'idle'")


## ---------------------------------------------------------------------------
## Utilidades de instanciación y comparación.
## ---------------------------------------------------------------------------
func _instantiate_zombie() -> Node:
	if not ResourceLoader.exists(ZOMBIE_SCENE):
		return null
	var packed: PackedScene = load(ZOMBIE_SCENE) as PackedScene
	if packed == null:
		return null
	var instance: Node = packed.instantiate()
	_instances.append(instance)
	add_child(instance)
	if instance.has_method("set_physics_process"):
		instance.call("set_physics_process", false)
	await get_tree().process_frame
	await get_tree().process_frame
	return instance


func _call_bool(node: Node, method: String, argument: Variant = null) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if argument == null:
		if not node.has_method(method):
			return false
		return bool(node.call(method))
	if not node.has_method(method):
		return false
	return bool(node.call(method, argument))


func _vector_close(left: Vector2, right: Vector2, epsilon: float) -> bool:
	return left.distance_to(right) <= epsilon


func _color_close(left: Color, right: Color, epsilon: float) -> bool:
	return absf(left.r - right.r) <= epsilon \
		and absf(left.g - right.g) <= epsilon \
		and absf(left.b - right.b) <= epsilon \
		and absf(left.a - right.a) <= epsilon


func _angle_distance(left: float, right: float) -> float:
	return absf(wrapf(left - right, -PI, PI))


func _settle(seconds: float) -> void:
	var frames: int = maxi(1, int(seconds * 60.0))
	for _index in range(frames):
		await get_tree().process_frame


func _wait_for_fx_finish(visual: Node, max_frames: int = 240) -> bool:
	for _index in range(max_frames):
		var tweens: Array = visual.get("_fx_tweens") as Array
		if tweens != null and tweens.is_empty():
			return true
		await get_tree().process_frame
	var remaining: Array = visual.get("_fx_tweens") as Array
	return remaining != null and remaining.is_empty()


func _cleanup() -> void:
	for instance in _instances:
		if is_instance_valid(instance):
			instance.queue_free()
	for _index in range(2):
		await get_tree().process_frame


func _asserts() -> void:
	if not ("--strict-assert" in OS.get_cmdline_user_args()):
		return
	assert(_failures.is_empty(), "ZOMBIE_SKIN_TEST: hay fallos")
