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
const ZOMBIE_VISUAL_SCRIPT: String = "res://03_zombies/ZombieVisual.gd"
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

## Margen del lock del golpe sobre la duracion del clip. Es parte del
## CONTRATO: el lock no puede ser un literal que se quede corto si el arte
## cambia (la revision adversarial de R2 encontro exactamente eso).
const HIT_LOCK_MARGIN: float = 1.5
const HIT_FALLBACK: float = 0.2

## Contrato observable del backoff de skin: el primer fallo espera 250 ms y
## cada fallo posterior duplica el cooldown hasta el tope de 5000 ms. La
## secuencia completa se fija aqui para que una puerta no dependa del reloj
## ni de tiempos de espera reales.
const EXPECTED_SKIN_RETRY_DELAYS_MS: Array[int] = [
	250, 500, 1000, 2000, 4000, 5000, 5000,
]

var _failures: Array[String] = []
var _instances: Array[Node] = []

## Instantaneas del estado ESTATICO compartido por las instancias de skin. El
## suite restaura el estado al terminar cada ambito y, como red de seguridad,
## tambien en `_exit_tree()`: una interrupcion o un assert intermedio no puede
## dejar cache/retry contaminando la siguiente ejecucion.
var _skin_suite_cache_snapshot: Dictionary = {}
var _skin_suite_retry_snapshot: Dictionary = {}
var _skin_scope_cache_snapshot: Dictionary = {}
var _skin_scope_retry_snapshot: Dictionary = {}
var _skin_suite_state_captured: bool = false
var _skin_scope_active: bool = false


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	await get_tree().process_frame
	_capture_skin_suite_state()
	_pack_integrity_checks()
	_generator_checks()
	await _runtime_checks()
	await _adversarial_contract_checks()
	await _cleanup()
	_restore_skin_suite_state()
	print("ZOMBIE_SKIN_TEST failures=%d" % _failures.size())
	for failure in _failures:
		print("  - " + failure)
	# La salida queda fijada ANTES de los asserts opcionales.
	get_tree().quit(1 if not _failures.is_empty() else 0)
	_asserts()


## ---------------------------------------------------------------------------
## A-bis. Cierre de la revision adversarial de R2 (enmienda de ADR-005).
## ---------------------------------------------------------------------------
## Cuatro contratos que la revision encontro y que ninguna puerta exigia:
##
##   1. La tabla `fps`/`count` del GENERADOR (`gen_zombie_skin.py`) era
##      metadato muerto: cambiarla no alteraba un byte del pack y ninguna
##      puerta lo detectaba (la puerta de fps solo comparaba el runtime
##      contra una tabla constante escrita aqui). Ahora se CRUZAN las dos
##      tablas: generador y runtime deben coincidir en fps, count y bucle.
##   2. El lock del golpe (`_hit_timer`) era un literal (0,2 s) que solo
##      coincidia con la duracion del clip `hit` (2 frames a 10 fps) por
##      casualidad: si el arte cambiaba, el lock podia cortar el clip. Ahora
##      el lock se DERIVA de la tabla del pack y la puerta exige que coincida
##      con el valor derivado.
##   3. Un intento de carga fallido dejaba al zombi con el cubo PARA SIEMPRE
##      (el latch `_skin_attempted`): ahora `_process()` reintenta el mismo
##      directorio con cooldown y backoff compartidos por ruta.
##   4. El cadaver se quedaba congelado en el tinte rojo del golpe: al morir,
##      `_physics_process` se desactiva y `_update_flash()` ya no restaura el
##      tinte blanco.
func _adversarial_contract_checks() -> void:
	_begin_skin_state_scope()
	await _generator_runtime_cross_check()
	await _hit_lock_derivation_check()
	_end_skin_state_scope()

	_begin_skin_state_scope()
	await _failed_load_retry_check()
	_end_skin_state_scope()

	_begin_skin_state_scope()
	await _skin_retry_backoff_check()
	await _skin_retry_state_backoff_check()
	_end_skin_state_scope()

	_begin_skin_state_scope()
	await _skin_route_alias_check()
	_end_skin_state_scope()

	_begin_skin_state_scope()
	await _successful_load_clears_retry_check()
	_end_skin_state_scope()

	_begin_skin_state_scope()
	await _death_tint_check()
	_end_skin_state_scope()


## 1. Generador <-> runtime: la tabla del generador no puede quedar muerta.
func _generator_runtime_cross_check() -> void:
	var source: String = ""
	if FileAccess.file_exists(GEN_ZOMBIE_SKIN):
		source = FileAccess.get_file_as_string(GEN_ZOMBIE_SKIN)
	_check(not source.is_empty(),
		"contrato: se puede leer %s" % GEN_ZOMBIE_SKIN)
	if source.is_empty():
		return
	# El parser se acota al BLOQUE `SKIN_ANIMS`: buscar en todo el fichero
	# permitiría que otro diccionario con la misma forma contaminase la
	# puerta. El bloque tiene que contener exactamente ocho clips y ocho
	# claves únicas.
	var block_start: int = source.find("SKIN_ANIMS = {")
	var block_end: int = source.find("\n}\n", block_start)
	_check(block_start >= 0 and block_end > block_start,
		"contrato: el generador tiene un bloque SKIN_ANIMS delimitado")
	if block_start < 0 or block_end <= block_start:
		return
	var skin_anims_block: String = source.substr(block_start, block_end - block_start)
	var regex := RegEx.new()
	# "walk": ("walk", (0, 1, 2, 3, 1), 8.0, True),
	var compiled: Error = regex.compile(
		"\"([a-z_]+)\"\\s*:\\s*\\(\"([a-z_]+)\"\\s*,\\s*\\(([^)]*)\\)\\s*,"
		+ "\\s*([0-9]+(?:\\.[0-9]+)?)\\s*,\\s*(True|False)\\)")
	_check(compiled == OK, "contrato: la tabla SKIN_ANIMS del generador es legible")
	if compiled != OK:
		return
	var matches: Array[RegExMatch] = regex.search_all(skin_anims_block)
	_check(matches.size() == 8,
		"contrato: SKIN_ANIMS tiene exactamente 8 animaciones (%d)" % matches.size())
	var unique_keys: Dictionary = {}
	for match in matches:
		unique_keys[match.get_string(1)] = true
	_check(unique_keys.size() == 8,
		"contrato: SKIN_ANIMS tiene exactamente 8 claves únicas (%d)" % unique_keys.size())
	var runtime_table: Dictionary = ZombieVisual.SKIN_ANIMATIONS
	var seen: Array[String] = []
	for match in matches:
		var pack_anim: String = match.get_string(1)
		var canonical: String = match.get_string(2)
		var poses: Array[String] = []
		for pose: String in match.get_string(3).split(",", false):
			var trimmed: String = pose.strip_edges()
			if not trimmed.is_empty():
				poses.append(trimmed)
		var fps: float = float(match.get_string(4))
		var loop: bool = match.get_string(5) == "True"
		seen.append(pack_anim)
		if not runtime_table.has(pack_anim):
			_check(false, "contrato: el runtime no declara el clip '%s' del generador"
				% pack_anim)
			continue
		var spec: Dictionary = runtime_table[pack_anim] as Dictionary
		_check(String(spec.get("canonical", "")) == canonical,
			"contrato: '%s' mapea a la misma animacion canonica (generador '%s' vs runtime '%s')"
				% [pack_anim, canonical, String(spec.get("canonical", ""))])
		_check(int(spec.get("count", -1)) == poses.size(),
			"contrato: '%s' tiene los mismos frames (generador %d vs runtime %d)"
				% [pack_anim, poses.size(), int(spec.get("count", -1))])
		_check(is_equal_approx(float(spec.get("fps", -1.0)), fps),
			"contrato: '%s' usa los mismos fps (generador %.1f vs runtime %.1f)"
				% [pack_anim, fps, float(spec.get("fps", -1.0))])
		_check(bool(spec.get("loop", not loop)) == loop,
			"contrato: '%s' tiene el mismo bucle (generador %s vs runtime %s)"
				% [pack_anim, str(loop), str(bool(spec.get("loop", false)))])
	for pack_anim in runtime_table.keys():
		_check(seen.has(String(pack_anim)),
			"contrato: el generador declara el clip '%s' que usa el runtime"
				% String(pack_anim))


## 2. El lock del golpe se deriva del pack (no es un literal que puede quedar
##    corto si el arte cambia).
func _hit_lock_derivation_check() -> void:
	var runtime_table: Dictionary = ZombieVisual.SKIN_ANIMATIONS
	var hit_count: int = 0
	var hit_fps: float = 0.0
	for pack_anim in runtime_table.keys():
		var spec: Dictionary = runtime_table[pack_anim] as Dictionary
		if String(spec.get("canonical", "")) != "hit":
			continue
		hit_count = int(spec.get("count", 0))
		hit_fps = float(spec.get("fps", 0.0))
		break
	_check(hit_count > 0 and hit_fps > 0.0,
		"lock hit: la tabla del pack declara el clip 'hit' (%d frames a %.1f fps)"
			% [hit_count, hit_fps])
	if hit_count <= 0 or hit_fps <= 0.0:
		return
	var clip_duration: float = float(hit_count) / hit_fps
	var expected: float = clip_duration * HIT_LOCK_MARGIN
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "lock hit: se puede instanciar un zombi")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	if visual == null:
		_check(false, "lock hit: el zombi tiene ZombieVisual")
		return
	var derived: float = -1.0
	if visual.has_method("hit_lock_duration"):
		derived = float(visual.call("hit_lock_duration"))
	_check(is_equal_approx(derived, expected),
		"lock hit: la duracion se DERIVA de la tabla (esperado %.3f s, obtenido %.3f s)"
			% [expected, derived])
	visual.call("play_hit")
	var timer: float = float(visual.get("_hit_timer"))
	# La puerta exige el lock DERIVADO (clip x margen), no solo que no sea
	# menor que el clip: con un literal de exactamente la duracion del clip
	# (0,2 s = 2 frames a 10 fps) el lock se agotaba EN EL MISMO INSTANTE
	# que terminaba el clip y lo cortaba (revision adversarial de R2, B2).
	# Con esta comprobacion, el literal 0,2 s falla.
	_check(timer >= expected - 0.001,
		"lock hit: el lock (%.3f s) cubre el clip con margen (%.3f s = %.3f s x %.1f)"
			% [timer, expected, clip_duration, HIT_LOCK_MARGIN])

	# El cubo no reproduce un clip de skin: conserva el lock corto historico.
	# El lock derivado (0,3 s con el pack actual) solo pertenece a la ruta con
	# skin; aplicarlo al cubo cambia su game feel sin necesidad.
	var fallback_dir: String = "res://assets/enemies/NO_EXISTE_LOCK/"
	visual.call("install_skin", fallback_dir)
	_check(not bool(visual.call("uses_skin")),
		"lock hit: la ruta de fallback usa el cubo")
	visual.call("play_hit")
	var cube_timer: float = float(visual.get("_hit_timer"))
	_check(is_equal_approx(cube_timer, HIT_FALLBACK),
		"lock hit: el cubo conserva HIT_FALLBACK=%.1f s (obtenido %.3f s)"
			% [HIT_FALLBACK, cube_timer])


## 3. Una carga fallida se reintenta en el ciclo de vida real, con cooldown
##    compartido por directorio. No basta con que `set_type()` lo intente: esa
##    llamada solo ocurre al aplicar el tipo y no vuelve durante el juego.
func _failed_load_retry_check() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "reintento: se puede instanciar un zombi")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	if visual == null:
		_check(false, "reintento: el zombi tiene ZombieVisual")
		return
	if not visual.has_method("skin_load_attempts") \
			or not visual.has_method("skin_attempted_dir"):
		_check(false, "reintento: ZombieVisual expone skin_load_attempts() y skin_attempted_dir()")
		return

	# Dos zombis usan la MISMA ruta rota. El cooldown es compartido por ruta:
	# cuando venza, solo uno reclama el intento para no montar una estampida.
	var second_zombie: Node = await _instantiate_zombie()
	var second_visual: Node = null
	if second_zombie != null:
		second_visual = second_zombie.get_node_or_null("ZombieVisual")
	if second_visual == null:
		_check(false, "reintento: se puede instanciar un segundo zombi")
		return
	if not second_visual.has_method("skin_load_attempts") \
			or not second_visual.has_method("skin_attempted_dir"):
		_check(false, "reintento: el segundo ZombieVisual expone las APIs públicas")
		return

	var bad_dir: String = "res://assets/enemies/NO_EXISTE_R3/"
	visual.call("install_skin", bad_dir)
	second_visual.call("install_skin", bad_dir)
	var first_before: int = int(visual.call("skin_load_attempts"))
	var second_before: int = int(second_visual.call("skin_load_attempts"))
	_check(first_before > 0 and second_before > 0,
		"reintento: los intentos fallidos quedan registrados via API publica (%d, %d)"
			% [first_before, second_before])
	_check(String(visual.call("skin_attempted_dir")) == bad_dir
			and String(second_visual.call("skin_attempted_dir")) == bad_dir,
		"reintento: se conserva el directorio inyectado")

	# NO se llama a `set_type()`: el reintento tiene que salir del ciclo de vida
	# normal de `ZombieVisual._process()`.
	await get_tree().create_timer(0.5).timeout
	var first_after: int = int(visual.call("skin_load_attempts"))
	var second_after: int = int(second_visual.call("skin_load_attempts"))
	var delta: int = (first_after - first_before) + (second_after - second_before)
	_check(delta == 1,
		"reintento: _process reintenta automaticamente con cooldown compartido por ruta (delta=%d)"
			% delta)
	_check(String(visual.call("skin_attempted_dir")) == bad_dir
			and String(second_visual.call("skin_attempted_dir")) == bad_dir,
		"reintento: el directorio inyectado se conserva tras el reintento")

	# Tras el intento, el backoff impide otra estampida en el frame siguiente.
	await get_tree().process_frame
	var first_next_frame: int = int(visual.call("skin_load_attempts"))
	var second_next_frame: int = int(second_visual.call("skin_load_attempts"))
	_check(first_next_frame == first_after and second_next_frame == second_after,
		"reintento: el backoff evita repetir el intento en el frame siguiente")


## El backoff se exige por su SECUENCIA COMPLETA, no solo por el hecho de que
## exista un cooldown. El calculo se extrae a una funcion pura para que la
## puerta no dependa del reloj ni tenga que esperar 17,75 s en tiempo real.
func _skin_retry_backoff_check() -> void:
	var delay_callable := Callable(ZombieVisual, "_skin_retry_delay_ms")
	_check(delay_callable.is_valid(),
		"reintento: el runtime implementa _skin_retry_delay_ms() como calculo testeable")
	if not delay_callable.is_valid():
		return
	var actual_delays: Array[int] = []
	for failure_count in range(1, EXPECTED_SKIN_RETRY_DELAYS_MS.size() + 1):
		actual_delays.append(int(delay_callable.call(failure_count)))
	_check(actual_delays == EXPECTED_SKIN_RETRY_DELAYS_MS,
		"reintento: backoff exacto 250->500->1000->2000->4000->5000->5000 ms (obtenido %s)"
			% str(actual_delays))


## Contrato del ESTADO REAL de retry. No basta con que el helper puro devuelva
## la secuencia: el registro inicial y cada avance runtime tienen que dejar el
## mismo resultado en `retry_at_ms`, `failures` y `delay_ms`.
##
## Para que una desconexion silenciosa no pueda pasar por equivalencia
## numerica (la antigua duplicacion del `delay_ms` anterior producia la misma
## serie), la puerta comprueba ademas que ambas funciones mantienen la llamada
## explicita al helper. El reloj se manipula de forma determinista poniendo el
## cooldown vencido; no se esperan 17,75 s.
func _skin_retry_state_backoff_check() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "reintento: se puede instanciar un zombi para observar el estado")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	if visual == null:
		_check(false, "reintento: el zombi tiene ZombieVisual")
		return

	_check(_script_function_contains(ZOMBIE_VISUAL_SCRIPT,
			"_register_skin_retry", "_skin_retry_delay_ms("),
		"reintento: _register_skin_retry() usa el helper de backoff")
	_check(_script_function_contains(ZOMBIE_VISUAL_SCRIPT,
			"_advance_skin_retry", "_skin_retry_delay_ms("),
		"reintento: _advance_skin_retry() usa el helper de backoff")

	var bad_dir: String = "res://assets/enemies/NO_EXISTE_R2_HOTFIX4/"
	var retry_state: Dictionary = ZombieVisual._skin_retry_after
	retry_state.clear()

	# REGISTRO INICIAL real. `install_skin()` falla y delega en
	# `_register_skin_retry()`; se observan los tres campos mutados.
	var before_register_ms: int = Time.get_ticks_msec()
	var failed_result: bool = not bool(visual.call("install_skin", bad_dir))
	var after_register_ms: int = Time.get_ticks_msec()
	_check(failed_result,
		"reintento: el intento inicial de una ruta inexistente falla")
	if retry_state.size() != 1:
		_check(false,
			"reintento: el registro inicial deja una sola entrada (entradas=%d)"
				% retry_state.size())
		return
	var entry_values: Array = retry_state.values()
	var entry: Dictionary = entry_values[0] as Dictionary
	var initial_delay_ms: int = EXPECTED_SKIN_RETRY_DELAYS_MS[0]
	_check(int(entry.get("failures", -1)) == 1,
		"reintento: el registro inicial deja failures=1")
	_check(int(entry.get("delay_ms", -1)) == initial_delay_ms,
		"reintento: el registro inicial deja delay_ms=%d (obtenido %d)"
			% [initial_delay_ms, int(entry.get("delay_ms", -1))])
	var initial_retry_at_ms: int = int(entry.get("retry_at_ms", -1))
	_check(initial_retry_at_ms >= before_register_ms + initial_delay_ms
			and initial_retry_at_ms <= after_register_ms + initial_delay_ms,
		"reintento: el registro inicial programa retry_at_ms con +%d ms"
			% initial_delay_ms)

	# AVANCES RUNTIME reales. En cada iteracion se vence el cooldown sin
	# esperar: `_process()` reclama el intento, lo falla y deja el siguiente
	# estado REAL en el diccionario compartido.
	for index in range(1, EXPECTED_SKIN_RETRY_DELAYS_MS.size()):
		entry["retry_at_ms"] = 0
		var attempts_before: int = int(visual.call("skin_load_attempts"))
		var before_advance_ms: int = Time.get_ticks_msec()
		visual.call("_process", 0.0)
		var after_advance_ms: int = Time.get_ticks_msec()
		var attempts_after: int = int(visual.call("skin_load_attempts"))
		if retry_state.size() != 1:
			_check(false,
				"reintento: el avance runtime conserva una sola entrada (entradas=%d)"
					% retry_state.size())
			return
		entry_values = retry_state.values()
		entry = entry_values[0] as Dictionary
		var expected_delay_ms: int = EXPECTED_SKIN_RETRY_DELAYS_MS[index]
		var expected_failures: int = index + 1
		_check(attempts_after == attempts_before + 1,
			"reintento: el avance runtime %d realiza un intento" % index)
		_check(int(entry.get("failures", -1)) == expected_failures,
			"reintento: el avance runtime %d deja failures=%d (obtenido %d)"
				% [index, expected_failures, int(entry.get("failures", -1))])
		_check(int(entry.get("delay_ms", -1)) == expected_delay_ms,
			"reintento: el avance runtime %d deja delay_ms=%d (obtenido %d)"
				% [index, expected_delay_ms, int(entry.get("delay_ms", -1))])
		var retry_at_ms: int = int(entry.get("retry_at_ms", -1))
		_check(retry_at_ms >= before_advance_ms + expected_delay_ms
				and retry_at_ms <= after_advance_ms + expected_delay_ms,
			"reintento: el avance runtime %d programa retry_at_ms con +%d ms"
				% [index, expected_delay_ms])


## Los alias de una ruta deben compartir la MISMA clave de cache y de retry.
## La ruta inyectada sigue siendo observable tal cual en `skin_attempted_dir()`:
## la normalizacion es solo interna y no reescribe la API publica.
func _skin_route_alias_check() -> void:
	var route_key_callable := Callable(ZombieVisual, "_skin_route_key")
	_check(route_key_callable.is_valid(),
		"alias: el runtime implementa _skin_route_key()")
	var resource_pack: String = "res://assets/enemies/zombie"
	var resource_pack_slash: String = "res://assets/enemies/zombie/"
	var absolute_pack: String = ProjectSettings.globalize_path(resource_pack)
	if route_key_callable.is_valid():
		var resource_key: String = String(route_key_callable.call(resource_pack))
		var slash_key: String = String(route_key_callable.call(resource_pack_slash))
		var absolute_key: String = String(route_key_callable.call(absolute_pack))
		_check(resource_key == slash_key and resource_key == absolute_key,
			"alias: res://pack, res://pack/ y su absoluto comparten clave (obtenido %s | %s | %s)"
				% [resource_key, slash_key, absolute_key])

	# CACHE: cargar la ruta resource deja una sola entrada; sus dos alias deben
	# reutilizar ese atlas, no crear caches paralelas.
	var skin_cache: Dictionary = ZombieVisual._skin_cache
	var cache_size_before: int = skin_cache.size()
	var atlas_callable := Callable(ZombieVisual, "_load_skin_atlas")
	_check(atlas_callable.is_valid(),
		"alias: el runtime expone el seam privado _load_skin_atlas()")
	if atlas_callable.is_valid():
		var resource_atlas: Dictionary = atlas_callable.call(resource_pack) as Dictionary
		var slash_atlas: Dictionary = atlas_callable.call(resource_pack_slash) as Dictionary
		var absolute_atlas: Dictionary = atlas_callable.call(absolute_pack) as Dictionary
		_check(not resource_atlas.is_empty(),
			"alias: el pack resource se puede cargar para la prueba de cache")
		_check(not slash_atlas.is_empty() and not absolute_atlas.is_empty()
				and slash_atlas == resource_atlas and absolute_atlas == resource_atlas,
			"alias: los tres alias recuperan el MISMO atlas")
		_check(skin_cache.size() == cache_size_before + 1,
			"alias: los tres alias comparten una sola entrada de cache (entradas anadidas=%d)"
				% (skin_cache.size() - cache_size_before))

	# RETRY: tres instancias reciben tres alias de la misma ruta inexistente.
	# Solo puede existir una entrada y, al vencer el cooldown, una sola instancia
	# puede reclamar el intento automatico.
	var retry_state: Dictionary = ZombieVisual._skin_retry_after
	retry_state.clear()
	var bad_resource: String = "res://assets/enemies/NO_EXISTE_ALIAS"
	var bad_resource_slash: String = "res://assets/enemies/NO_EXISTE_ALIAS/"
	var bad_absolute: String = ProjectSettings.globalize_path(bad_resource)
	var visuals: Array[Node] = []
	var injected_paths: Array[String] = [
		bad_resource, bad_resource_slash, bad_absolute,
	]
	for injected_path in injected_paths:
		var zombie: Node = await _instantiate_zombie()
		var visual: Node = null
		if zombie != null:
			visual = zombie.get_node_or_null("ZombieVisual")
		if visual == null:
			_check(false, "alias: se puede instanciar un zombi para el retry")
			return
		visuals.append(visual)
		var failed_result: bool = not bool(visual.call("install_skin", injected_path))
		_check(failed_result,
			"alias: la ruta inexistente '%s' falla" % injected_path)
		_check(String(visual.call("skin_attempted_dir")) == injected_path,
			"alias: la ruta inyectada '%s' se conserva observable" % injected_path)
	_check(retry_state.size() == 1,
		"alias: los tres alias comparten una sola entrada de retry (entradas=%d)"
			% retry_state.size())
	if retry_state.size() != 1:
		return

	for entry_value: Variant in retry_state.values():
		var entry: Dictionary = entry_value as Dictionary
		entry["retry_at_ms"] = 0
	var runtime_attempts: int = 0
	for visual in visuals:
		var attempts_before: int = int(visual.call("skin_load_attempts"))
		visual.call("_process", 0.0)
		var attempts_after: int = int(visual.call("skin_load_attempts"))
		runtime_attempts += attempts_after - attempts_before
	_check(runtime_attempts == 1,
		"alias: el cooldown compartido permite UN solo avance runtime entre alias (intentos=%d)"
			% runtime_attempts)
	var entry_values: Array = retry_state.values()
	var shared_entry: Dictionary = entry_values[0] as Dictionary
	_check(int(shared_entry.get("failures", -1)) == 2
			and int(shared_entry.get("delay_ms", -1)) == EXPECTED_SKIN_RETRY_DELAYS_MS[1],
		"alias: el estado compartido conserva failures/delay tras el avance")


## Un intento posterior exitoso debe cerrar el estado de retry de ESA ruta y
## restaurar la skin. Para observar el mismo contrato sin escribir fixtures,
## se envenena solo la entrada de cache de la ruta canonica: el primer intento
## falla por el atlas vacio y el siguiente vuelve a cargar el pack real.
func _successful_load_clears_retry_check() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "reintento: se puede instanciar un zombi para la recuperacion")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	var sprite: AnimatedSprite2D = zombie.get_node_or_null(
		"ZombieVisual/AnimatedSprite2D") as AnimatedSprite2D
	if visual == null or sprite == null:
		_check(false, "reintento: el zombi expone ZombieVisual y la sprite")
		return

	var skin_cache: Dictionary = ZombieVisual._skin_cache
	var retry_state: Dictionary = ZombieVisual._skin_retry_after
	var route_key_callable := Callable(ZombieVisual, "_skin_route_key")
	var route_key: String = SKIN_DIR
	if route_key_callable.is_valid():
		route_key = String(route_key_callable.call(SKIN_DIR))
	skin_cache[route_key] = {}
	var failed_result: bool = bool(visual.call("install_skin", SKIN_DIR))
	_check(not failed_result,
		"reintento: el intento fallido deja un estado de retry para la ruta")
	_check(retry_state.has(route_key),
		"reintento: el estado de retry registra la ruta que fallo")

	# La ruta deja de estar envenenada: el siguiente intento automatico puede
	# cargar el pack canonico y debe reemplazar el estado de retry por una
	# skin visible. Se vence el cooldown sin espera real.
	var attempts_before_recovery: int = int(visual.call("skin_load_attempts"))
	skin_cache.erase(route_key)
	var retry_entry_value: Variant = retry_state.get(route_key, {})
	if retry_entry_value is Dictionary:
		var retry_entry: Dictionary = retry_entry_value as Dictionary
		retry_entry["retry_at_ms"] = 0
	visual.call("_process", 0.0)
	var attempts_after_recovery: int = int(visual.call("skin_load_attempts"))
	_check(attempts_after_recovery == attempts_before_recovery + 1,
		"reintento: el ciclo automatico realiza un intento posterior (delta=%d)"
			% (attempts_after_recovery - attempts_before_recovery))
	_check(not retry_state.has(route_key),
		"reintento: el intento exitoso cancela el estado de retry de la ruta")
	_check(bool(visual.call("uses_skin")) and sprite.visible,
		"reintento: el intento posterior restaura la skin visible")


## 4. El cadaver no conserva el tinte rojo del golpe.
func _death_tint_check() -> void:
	var zombie: Node = await _instantiate_zombie()
	if zombie == null:
		_check(false, "cadaver: se puede instanciar un zombi")
		return
	var visual: Node = zombie.get_node_or_null("ZombieVisual")
	_check(visual != null and bool(visual.call("uses_skin")),
		"cadaver: el zombi de la prueba usa la skin (el defecto solo se ve con skin)")
	zombie.call("take_damage", 10000.0, null, 0)
	var tint: Color = zombie.modulate
	_check(_color_close(tint, Color.WHITE, 0.001),
		"cadaver: al morir se restaura el tinte (modulate=%s, se esperaba blanco)"
			% str(tint))


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
	_begin_skin_state_scope()
	await _runtime_with_skin_checks()
	await _boss_profile_skin_checks()
	await _fallback_checks()
	await _malformed_pack_checks()
	await _visible_fx_checks()
	await _death_cancels_fx_checks()
	await _state_orientation_checks()
	await _hit_lock_checks()
	_end_skin_state_scope()


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
## Utilidades de instanciación, estado global y comparación.
## ---------------------------------------------------------------------------
## Extrae el cuerpo de una funcion del script para comprobar el cableado
## literal del helper. Esta comprobacion es intencionalmente arquitectónica:
## protege contra la desconexion silenciosa que conserva el mismo resultado
## numerico, no sustituye la observacion del estado real de arriba.
func _script_function_contains(script_path: String, function_name: String,
		needle: String) -> bool:
	var source: String = FileAccess.get_file_as_string(script_path)
	if source.is_empty():
		return false
	var marker: String = "func %s(" % function_name
	var body_start: int = source.find(marker)
	if body_start < 0:
		return false
	var body_end: int = source.find("\n\nfunc ", body_start + marker.length())
	if body_end < 0:
		body_end = source.length()
	return source.substr(body_start, body_end - body_start).contains(needle)


## Captura el estado global al inicio del suite. Se restaura tanto en el
## camino normal como en `_exit_tree()`.
func _capture_skin_suite_state() -> void:
	_skin_suite_cache_snapshot = ZombieVisual._skin_cache.duplicate(true)
	_skin_suite_retry_snapshot = ZombieVisual._skin_retry_after.duplicate(true)
	_skin_suite_state_captured = true


## Restaura el estado global del suite. Se reasignan los diccionarios, no se
## mutan sus referencias: cualquier vista local deja de observar el estado
## estatico compartido, como pretende el contrato de aislamiento.
func _restore_skin_suite_state() -> void:
	if not _skin_suite_state_captured:
		return
	ZombieVisual._skin_cache = _skin_suite_cache_snapshot.duplicate(true)
	ZombieVisual._skin_retry_after = _skin_suite_retry_snapshot.duplicate(true)


## Inicia un ambito aislado para una prueba que toque cache/retry.
func _begin_skin_state_scope() -> void:
	_skin_scope_cache_snapshot = ZombieVisual._skin_cache.duplicate(true)
	_skin_scope_retry_snapshot = ZombieVisual._skin_retry_after.duplicate(true)
	_skin_scope_active = true


## Cierra el ambito aislado. Si una asercion interrumpe el flujo antes de esta
## llamada, `_exit_tree()` ejecuta igualmente la misma restauracion.
func _end_skin_state_scope() -> void:
	if not _skin_scope_active:
		return
	ZombieVisual._skin_cache = _skin_scope_cache_snapshot.duplicate(true)
	ZombieVisual._skin_retry_after = _skin_scope_retry_snapshot.duplicate(true)
	_skin_scope_active = false


func _exit_tree() -> void:
	_end_skin_state_scope()
	_restore_skin_suite_state()


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
