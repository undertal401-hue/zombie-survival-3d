extends Node2D
class_name ZombieVisual

## =============================================================================
## ZOMBIE VISUAL - presentacion HIBRIDA: skin de sprites para el rango bajo,
## cubo (Polygon2D) para los rangos altos.
## =============================================================================
## R1 (2026-11-20): el usuario decide que los personajes se quedan como CUBO
## y que él hará el arte pixel después.
##
## R2 (2026-11-20): el usuario pide poner piel pixel-art a los zombis de rango
## bajo. Decisiones (ADR-005):
##   - El skin se aplica SOLO a los tipos de la allowlist `SKIN_TYPES` (hoy,
##     el WALKER = zombi normal). RUNNER/TANK/SPITTER/SCREAMER/BOSS conservan
##     el cubo: son los rangos altos y mantienen su lectura de arquetipo.
##   - El pack (`assets/enemies/zombie/`) se carga en runtime como celdas de
##     64x64 (`AtlasTexture` por frame) en el `SpriteFrames` de CADA
##     instancia. Si el pack falta o esta incompleto, el zombi vuelve al
##     cubo: el juego nunca se rompe.
##   - Squash/stretch y telegrafia se aplican a lo que se VE (la sprite si hay
##     skin, el cubo si no), nunca a las hitboxes.
##   - El arte canonico del repo es CENITAL (view from above): el personaje
##     rota hacia la direccion de marcha, igual que el cubo.
##   - Se conserva la barra de vida del jefe (Ítem 12) y las 8 animaciones.
## =============================================================================

## `get_node_or_null` y no `$`: el script debe tolerar una escena sin sprite
## (fallback al cubo) sin abortar en `_ready()`.
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
## CAPA 2 / ÍTEM 12: barra exclusiva del jefe. No existe en el HUD global para
## no repartir estado: el propio Zombie empuja su ratio de vida aquí.
@onready var boss_bar: Node2D = get_node_or_null("boss_bar") as Node2D
@onready var boss_health: ColorRect = get_node_or_null("boss_bar/boss_health") as ColorRect

## El cubo visible (Polygon2D del Zombie). Lo escala Zombie.gd por arquetipo;
## aquí solo se anima (squash/telegrafía) y se tiñe.
@onready var _cube_body: Polygon2D = get_node_or_null("../Body") as Polygon2D
@onready var _cube_nose: Polygon2D = get_node_or_null("../Nose") as Polygon2D

var _current_state: String = "idle"
var _is_attacking: bool = false
var _is_dying: bool = false

## Duracion minima del bloqueo de ATAQUE (movimiento). El clip visual de
## "attack" dura 6 frames a 12 fps = 0.5 s con skin (y no existe en el cubo),
## asi que el clip y este temporizador coinciden: el timer es la garantia de
## que el zombi no se mueve mientras ataca aunque el clip no exista.
var _attack_timer: float = 0.0
const ATTACK_FALLBACK: float = 0.5

## Lock del golpe recibido. Sin frames (cubo) no hacia falta: no habia nada
## que interrumpir. Con skin, `play_hit()` reproduce un clip real y el
## `update_state()` del siguiente frame fisico lo pisaba con idle/walk/run:
## el golpe se veia UN solo frame. El lock mantiene el clip visible.
var _hit_timer: float = 0.0
const HIT_FALLBACK: float = 0.2

## Tipos de zombi (coincide con Zombie.Kind)
enum ZombieType { WALKER, RUNNER, TANK, SPITTER, SCREAMER, BOSS }

## -----------------------------------------------------------------------------
## SKIN DE SPRITES (rango bajo) - ADR-005
## -----------------------------------------------------------------------------
## Interruptor maestro de presentacion. false = cubo; true = skin cuando el
## tipo lo admite Y el pack esta disponible.
const USE_SPRITE_ART: bool = true

## Directorio del pack: frames sueltos (`<anim>/<anim>_NN.png`) + strips
## horizontales (`<anim>_strip.png`).
const SKIN_DIR: String = "res://assets/enemies/zombie/"

## Lado de la celda del pack (px). El strip es rebanable: celda N en x=N*64.
const SKIN_CELL: int = 64

## Tipos que llevan skin. "Rango bajo" = el zombi normal (WALKER).
## Allowlist EXPLICITA: anadir un tipo aqui es una decision de diseno, no un
## efecto colateral. El orden del enum NO se toca (los spawners, el audio y
## los FX usan enteros magicos derivados de el).
const SKIN_TYPES: Array[int] = [ZombieType.WALKER]

## Mapa pack -> animacion canonica del runtime, con fps y bucle.
## Los fps vienen de la ficha del pack: el ataque dura 6/12 = 0.5 s, que es
## justo el `ATTACK_FALLBACK` del timer de ataque.
const SKIN_ANIMATIONS: Dictionary = {
	"idle": {"canonical": "idle", "count": 2, "fps": 4.0, "loop": true},
	"walk": {"canonical": "walk", "count": 5, "fps": 8.0, "loop": true},
	"walk_alt": {"canonical": "run", "count": 3, "fps": 12.0, "loop": true},
	"attack": {"canonical": "attack", "count": 6, "fps": 12.0, "loop": false},
	"attack_alt": {"canonical": "hit", "count": 2, "fps": 10.0, "loop": false},
	"special": {"canonical": "hurt", "count": 4, "fps": 10.0, "loop": false},
	"rise": {"canonical": "crawl", "count": 5, "fps": 8.0, "loop": true},
	"death": {"canonical": "death", "count": 6, "fps": 7.0, "loop": false},
}

## Las 8 animaciones canonicas que el runtime siempre declara (con o sin
## skin). "default" la crea SpriteFrames solo y no se toca.
const CANONICAL_ANIMS: Array[String] = [
	"idle", "walk", "run", "attack", "hit", "hurt", "death", "crawl"
]

## Velocidades y bucles de la presentacion con CUBO (sin frames).
const CANONICAL_FPS: Dictionary = {
	"idle": 6.0, "walk": 8.0, "run": 12.0, "attack": 18.0,
	"hit": 15.0, "hurt": 15.0, "death": 5.0, "crawl": 4.0,
}
const CANONICAL_LOOP: Dictionary = {
	"idle": true, "walk": true, "run": true, "attack": false,
	"hit": false, "hurt": false, "death": false, "crawl": true,
}

## Umbral walk/run (px/s). El WALKER camina a 80 px/s y el RUNNER a 150: con
## el umbral viejo (50) el zombi normal NUNCA teachinga 'walk' y el pack
## gastaba la animacion 'run' en practicamente todo el juego.
const WALK_RUN_THRESHOLD: float = 120.0

## Offset del AnimatedSprite2D con la presentacion en cubo (celda 32x32
## generada). Con skin el personaje va centrado en la celda de 64x64 y el
## offset es 0 para que el nodo quede en su centro, como el cubo.
const CUBE_SPRITE_OFFSET: Vector2 = Vector2(0.0, 8.0)

## z_index de la sprite con la presentacion en cubo (el de la escena). Con
## skin baja a 0: el zombi debe ordenarse en profundidad igual que el cubo de
## los demas tipos, si no el WALKER pasaria por DELANTE del vehiculo (z=4)
## y los otros zombis por detras.
const CUBE_SPRITE_Z_INDEX: int = 5
const SKIN_Z_INDEX: int = 0

## Estado del skin en ESTA instancia.
var _use_skin: bool = false
var _skin_ready: bool = false
var _skin_attempted: bool = false
var _skin_atlas: Dictionary = {}

## Ultimo tipo aplicado por `set_type()`. Lo necesita `install_skin()` para
## saber si al terminar de cargar el pack debe ACTIVAR la skin o dejar al
## zombi con el cubo (un TANK nunca lleva skin aunque el pack este bien).
var _current_type: int = ZombieType.WALKER

## Cache de texturas por directorio: las 8 texturas se cargan UNA vez por
## proceso, no una por zombi (un zombie cada vez es una escena distinta).
static var _skin_cache: Dictionary = {}

## Orientacion de la sprite (arte cenital): gira hacia la direccion de
## marcha. El cubo lo rota Zombie.gd; la sprite lo rota este nodo.
var _facing_target: float = PI * 0.5
var _facing_current: float = PI * 0.5
var _facing_valid: bool = false

## Paleta canónica (ART_BIBLE.md): BLOOD #b52b20, BLOOD_BRIGHT #e8563c.
const BOSS_BAR_WIDTH: float = 48.0
const BOSS_BAR_PHASE_1: Color = Color(0.71, 0.169, 0.125, 1.0)
const BOSS_BAR_PHASE_2: Color = Color(0.91, 0.337, 0.235, 1.0)

## Game feel: squash/stretch y telegrafía comparten los mismos tweens para que
## nunca peleen por la escala. Solo se anima el cubo: las hitboxes del Zombie
## son hermanas de este nodo y permanecen intactas.
##
## R1: antes había UN `_fx_tween` creado dentro de un bucle, así que solo se
## conservaba el último (los anteriores quedaban huérfanos peleándose por la
## escala) y, en la telegrafía, el patrón `set_parallel(true)` +
## `tween_interval()` + `set_parallel(true)` NO respetaba el "hold": la vuelta
## a la base arrancaba en el mismo instante que la subida y el pulso era
## invisible. Medido con una sonda sobre Godot 4.7.2:
##   patrón viejo  -> subida 0.007-0.076, "vuelta" 0.076-0.173 (sin hold)
##   patrón nuevo  -> subida 0.007-0.076, hold 0.076-0.376, vuelta 0.376-0.476
## Ahora hay un tween POR polígono: dentro de cada tween las fases son
## secuenciales (subir -> hold -> bajar) y entre polígonos corren en paralelo
## porque son tweens distintos. Todos se guardan para poder matarlos.
var _base_scale: Vector2 = Vector2.ONE
var _base_modulate: Color = Color.WHITE
## Escala base de la SPRITE (la del arquetipo). Es distinta de la del cubo:
## el cubo mide 24 unidades y la skin 64 px a escala 0.5.
var _sprite_base_scale: Vector2 = Vector2.ONE
## Tweens de los FX de escala. Hay UNO por efecto y escribe sobre lo que se
## esta viendo (cubo o skin), nunca sobre las hitboxes.
var _fx_tweens: Array[Tween] = []
var _is_telegraphing: bool = false

func _ready() -> void:
	_reset_animations()
	if animated_sprite != null:
		_base_scale = animated_sprite.scale
		_base_modulate = animated_sprite.modulate
		_sprite_base_scale = animated_sprite.scale
		# Muestreo puntual (sin interpolación): el objetivo es pixel art.
		animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if animated_sprite.material is CanvasItemMaterial:
			(animated_sprite.material as CanvasItemMaterial).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		animated_sprite.play("idle")
		animated_sprite.animation_finished.connect(_on_animation_finished)

	# Presentación: se ve el CUBO hasta que `set_type()` diga lo contrario.
	# El tipo lo aplica Zombie.gd (`_apply_kind`) DESPUÉS de este `_ready()`.
	_apply_presentation()

## --- Skin: carga, instalacion y fallback --------------------------------------

## Carga (o reutiliza) el pack de skin. `base_dir` es inyectable para poder
## probar el fallback al cubo sin tocar disco.
## Devuelve true si el pack quedo disponible y COMPLETO.
##
## Al terminar, la presentacion queda coherente con el resultado: si el pack
## se carga bien y el tipo vigente lo admite, la skin queda VISIBLE; si no,
## el zombi vuelve al cubo. Esto permite recuperar el skin tras un fallback
## sin depender de que nadie llame a `set_type()` otra vez.
func install_skin(base_dir: String = SKIN_DIR) -> bool:
	_skin_attempted = true
	if animated_sprite == null:
		_skin_ready = false
		_use_skin = false
		_apply_presentation()
		return false
	var atlas: Dictionary = _load_skin_atlas(base_dir)
	_skin_atlas = atlas
	_skin_ready = not atlas.is_empty()
	if _skin_ready:
		_install_skin_frames()
		_use_skin = USE_SPRITE_ART and SKIN_TYPES.has(_current_type)
	else:
		# Pack ausente o incompleto: se limpian los frames para que no
		# quede media skin colgada y el zombi vuelve al cubo.
		_clear_skin_frames()
		_use_skin = false
	_apply_presentation()
	return _skin_ready

## Atlas de celdas por animacion canonica. Cacheado por ruta: las texturas se
## cargan una sola vez por proceso, no una por zombi.
##
## Un CARGA FALLIDA no se cachea: si el pack no esta (o esta incompleto), el
## siguiente intento vuelve a mirar el disco. Cachear el fallo dejaria al
## proceso ciego para siempre aunque el arte apareciese despues.
##
## Las DIMENSIONES del strip se validan: el runtime construye una region
## `Rect2(i*64, 0, 64, 64)` por frame, asi que un strip mas corto que
## `count*64` deja los ultimos frames FUERA del atlas (la region se sale de
## la textura y el frame sale recortado o vacio) y uno mas alto desalinea
## las celdas. Un pack invalido debe producir el fallback al cubo, no una
## animacion estructuralmente rota.
static func _load_skin_atlas(base_dir: String) -> Dictionary:
	if _skin_cache.has(base_dir):
		return _skin_cache[base_dir]
	var built: Dictionary = {}
	for pack_anim in SKIN_ANIMATIONS.keys():
		var spec: Dictionary = SKIN_ANIMATIONS[pack_anim]
		var path: String = base_dir.path_join(String(pack_anim) + "_strip.png")
		if not ResourceLoader.exists(path):
			return {}
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			return {}
		var count: int = int(spec["count"])
		var expected_width: int = count * SKIN_CELL
		if count <= 0 \
				or texture.get_height() != SKIN_CELL \
				or texture.get_width() != expected_width:
			push_warning("ZombieVisual: pack de skin invalido (%s: %dx%d, se esperan %dx%d); se usa el cubo" % [
				String(pack_anim),
				texture.get_width(),
				texture.get_height(),
				expected_width,
				SKIN_CELL,
			])
			return {}
		var frames: Array[Texture2D] = []
		for i in count:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(
				float(i * SKIN_CELL), 0.0, float(SKIN_CELL), float(SKIN_CELL))
			frames.append(atlas)
		built[String(spec["canonical"])] = {
			"frames": frames,
			"fps": float(spec["fps"]),
			"loop": bool(spec["loop"]),
		}
	_skin_cache[base_dir] = built
	return built

## Instala los frames del skin en el SpriteFrames de ESTA instancia.
## El SpriteFrames es POR INSTANCIA (nunca compartido): `set_type()` cambia
## las velocidades de animacion y un recurso compartido las contaminaria
## (el ultimo zombi instanciado mandaria sobre los demas).
func _install_skin_frames() -> void:
	var playing: String = animated_sprite.animation if animated_sprite != null else ""
	_reset_animations(_skin_atlas)
	if animated_sprite == null:
		return
	# Al reconstruir las animaciones se pierde la que estaba en curso: se
	# restaura la misma (o "idle" si ya no existe). El estado se resincroniza
	# aparte con `_current_state = ""`, porque si no el `update_state()`
	# siguiente creeria que la animacion ya es la correcta y el zombi se
	# quedaria congelado en "idle" mientras camina.
	if playing == "" or not animated_sprite.sprite_frames.has_animation(playing):
		playing = "idle"
	animated_sprite.play(playing)

## Deja las 8 animaciones canonicas sin frames (presentacion con cubo).
func _clear_skin_frames() -> void:
	_reset_animations()

## ¿Hay un pack de skin utilizable en esta instancia?
func has_skin() -> bool:
	return _skin_ready

## ¿Esta instancia se esta mostrando CON skin (no solo con el pack cargado)?
func uses_skin() -> bool:
	return _use_skin

## --- Animaciones ---------------------------------------------------------------

## (Re)crea las 8 animaciones canonicas. `atlas` vacio = presentacion con
## cubo (sin frames); con atlas = los frames del skin (y sus fps).
func _reset_animations(atlas: Dictionary = {}) -> void:
	if animated_sprite == null:
		return
	if animated_sprite.sprite_frames == null:
		animated_sprite.sprite_frames = SpriteFrames.new()
	var frames: SpriteFrames = animated_sprite.sprite_frames
	for anim in CANONICAL_ANIMS:
		if frames.has_animation(anim):
			frames.remove_animation(anim)
	for anim in CANONICAL_ANIMS:
		frames.add_animation(anim)
		var spec: Dictionary = {}
		if not atlas.is_empty() and atlas.has(anim):
			spec = atlas[anim]
		if spec.is_empty():
			frames.set_animation_speed(anim, float(CANONICAL_FPS.get(anim, 8.0)))
			frames.set_animation_loop(anim, bool(CANONICAL_LOOP.get(anim, false)))
		else:
			frames.set_animation_speed(anim, float(spec["fps"]))
			frames.set_animation_loop(anim, bool(spec["loop"]))
			for texture in spec["frames"]:
				frames.add_frame(anim, texture)

## --- Presentacion ---------------------------------------------------------------

## Elige que se ve: el cubo o la skin. `set_type()` es la autoridad final
## (los tests cambian el tipo DESPUES de instanciar).
##
## Es NULL-SAFE: `install_skin()` puede llamarse antes de que el nodo exista
## o en una escena sin `AnimatedSprite2D`, y esta funcion no debe abortar en
## ese caso (el fallback al cubo debe funcionar AUNQUE no haya sprite).
func _apply_presentation() -> void:
	var cube_visible: bool = not _use_skin
	for poly in _cube_nodes():
		if poly != null:
			poly.visible = cube_visible
	if animated_sprite != null:
		animated_sprite.visible = _use_skin
		# Con skin el personaje va centrado en la celda de 64x64: offset 0 para
		# que el nodo quede en su centro (igual que el cubo). Sin skin se
		# conserva el offset del arte de 32x32.
		animated_sprite.offset = Vector2.ZERO if _use_skin else CUBE_SPRITE_OFFSET
		animated_sprite.z_index = SKIN_Z_INDEX if _use_skin else CUBE_SPRITE_Z_INDEX
	# La escala base se captura aquí: `set_type()` la actualizará con la del
	# arquetipo cuando Zombie.gd aplique el tipo.
	_capture_cube_base_scales()

func _process(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer = maxf(_attack_timer - delta, 0.0)
		if _attack_timer <= 0.0 and _is_attacking:
			_is_attacking = false
			_current_state = ""  # Forzar actualización en siguiente frame
	if _hit_timer > 0.0:
		_hit_timer = maxf(_hit_timer - delta, 0.0)
		if _hit_timer <= 0.0:
			_current_state = ""  # Forzar actualización en siguiente frame
	# Orientacion del skin: el arte canonico es cenital y mira hacia "arriba"
	# en la celda, asi que se le suma 90 grados para que apunte en la misma
	# direccion que el cubo (que rota en Zombie.gd).
	if _use_skin and animated_sprite != null:
		if _facing_valid:
			_facing_current = lerp_angle(_facing_current, _facing_target,
				minf(delta * 8.0, 1.0))
		animated_sprite.rotation = _facing_current

func set_type(type: int) -> void:
	# El tipo vigente se registra ANTES de cargar el skin: `install_skin()`
	# lo consulta para decidir si la skin puede quedar visible.
	_current_type = type
	# Cancelar CUALQUIER efecto en curso y devolver el cubo a su estado base:
	# antes solo se mataban los tweens, así que `_is_telegraphing` seguía en
	# true y el tinte/la escala deformada se quedaban pegados al cubo.
	_reset_fx()
	_capture_cube_base_scales()
	# Decidir la presentacion ANTES de tocar el sprite: el skin se carga una
	# sola vez (y solo si el tipo lo admite). Si el pack no esta, el zombi
	# se queda con el cubo: el juego no se rompe nunca por el arte.
	_use_skin = USE_SPRITE_ART and SKIN_TYPES.has(type)
	if _use_skin and not _skin_attempted:
		install_skin()
	_use_skin = _use_skin and _skin_ready
	# Ajustar velocidades y escala según tipo (el cubo lo tinte Zombie.gd).
	# Sin `AnimatedSprite2D` no hay nada que presentar: el cubo se queda y el
	# zombi sigue funcionando (el arte nunca rompe el juego).
	if animated_sprite == null:
		_apply_presentation()
		return
	var frames: SpriteFrames = animated_sprite.sprite_frames
	if frames == null:
		return
	# El tinte del arquetipo se reevalua aqui: sin este reset, un zombi que
	# cambiase de tipo conservaria el tinte del anterior.
	animated_sprite.modulate = Color.WHITE
	match type:
		ZombieType.WALKER:
			animated_sprite.scale = Vector2(0.5, 0.5)
			frames.set_animation_speed("walk", 8)
			frames.set_animation_speed("run", 10)
		ZombieType.RUNNER:
			animated_sprite.scale = Vector2(0.45, 0.45)
			animated_sprite.modulate = Color(1.0, 0.7, 0.7, 1.0)  # Tinte rojizo
			frames.set_animation_speed("walk", 12)
			frames.set_animation_speed("run", 18)
		ZombieType.TANK:
			animated_sprite.scale = Vector2(0.7, 0.7)
			animated_sprite.modulate = Color(0.6, 0.6, 0.7, 1.0)  # Tinte azulado/blindaje
			frames.set_animation_speed("walk", 5)
			frames.set_animation_speed("run", 7)
		ZombieType.SPITTER:
			animated_sprite.scale = Vector2(0.5, 0.5)
			animated_sprite.modulate = Color(0.7, 1.0, 0.7, 1.0)  # Tinte verdoso
			frames.set_animation_speed("walk", 7)
			frames.set_animation_speed("run", 9)
		ZombieType.SCREAMER:
			animated_sprite.scale = Vector2(0.45, 0.45)
			animated_sprite.modulate = Color(1.0, 0.5, 1.0, 1.0)  # Tinte magenta
			frames.set_animation_speed("walk", 9)
			frames.set_animation_speed("run", 14)
		ZombieType.BOSS:
			# "Tanque Alfa": corpulento, acero con sangre y animación más pesada.
			animated_sprite.scale = Vector2(0.95, 0.95)
			animated_sprite.modulate = Color(0.85, 0.75, 0.75, 1.0)
			frames.set_animation_speed("walk", 4)
			frames.set_animation_speed("run", 6)

	# La barra solo existe visualmente para el jefe; el resto la mantiene oculta.
	if boss_bar != null:
		boss_bar.visible = (type == ZombieType.BOSS)
	if type == ZombieType.BOSS:
		update_boss_health(1.0, false)

	# Cada arquetipo define la escala/tinte base sobre la que vuelven los FX.
	_base_scale = animated_sprite.scale
	_base_modulate = animated_sprite.modulate
	_sprite_base_scale = animated_sprite.scale
	# El cubo y la skin son mutuamente excluyentes: el que no se ve, no se
	# anima ni recibe FX.
	_apply_presentation()
	if _use_skin:
		# Los fps del PACK mandan sobre los del arquetipo: la ficha del arte
		# es la que define el ritmo de cada animacion.
		_install_skin_frames()
		# Forzar la resincronizacion del estado en el siguiente update_state.
		_current_state = ""

## La barra del jefe se actualiza desde Zombie con el ratio hp/max_hp real.
## En fase 2 (enraged) cambia a BLOOD_BRIGHT para señalar el cambio de patrón.
func update_boss_health(ratio: float, enraged: bool = false) -> void:
	if boss_bar == null or boss_health == null:
		return
	boss_bar.visible = not _is_dying
	boss_health.offset_right = -24.0 + BOSS_BAR_WIDTH * clampf(ratio, 0.0, 1.0)
	boss_health.color = BOSS_BAR_PHASE_2 if enraged else BOSS_BAR_PHASE_1


func update_state(velocity: Vector2, is_chasing: bool, target_direction: Vector2, is_crawling: bool = false) -> void:
	if _is_attacking or _is_dying or _hit_timer > 0.0:
		return
	
	var speed: float = velocity.length()
	var new_state: String
	
	if is_crawling:
		new_state = "crawl" if speed >= 5.0 else "idle"
	elif speed < 5.0:
		new_state = "idle"
	elif speed < WALK_RUN_THRESHOLD:
		new_state = "walk"
	else:
		new_state = "run"
	
	# Orientacion: el cubo lo rota Zombie.gd con el angulo de la velocidad.
	# La skin hace lo mismo (el arte es cenital y mira hacia arriba en la
	# celda, por eso el +90 grados).
	if speed > 8.0:
		_facing_target = velocity.angle() + PI * 0.5
		_facing_valid = true
	
	# Flip horizontal. Con skin NO se espeja: la sprite rota hacia la marcha
	# y el espejo daria dos orientaciones contradictorias a la vez.
	if animated_sprite != null:
		if _use_skin:
			animated_sprite.flip_h = false
		elif target_direction.x != 0:
			animated_sprite.flip_h = target_direction.x < 0

	if new_state != _current_state:
		_current_state = new_state
		if animated_sprite != null:
			animated_sprite.play(new_state)

## --- Cubo y skin: lo que realmente se ve --------------------------------------

func _cube_nodes() -> Array[Polygon2D]:
	var nodes: Array[Polygon2D] = []
	if _cube_body != null:
		nodes.append(_cube_body)
	if _cube_nose != null:
		nodes.append(_cube_nose)
	return nodes

## Nodos que reciben los FX de escala (squash/stretch/telegrafía).
## Si el zombi usa skin, el cubo está OCULTO y los FX tienen que aplicarse a la
## sprite: si no, el aplastamiento al recibir daño o el aviso antes de atacar
## serían invisibles. Nunca los dos (el FX se aplicaria dos veces).
func _fx_nodes() -> Array[CanvasItem]:
	var nodes: Array[CanvasItem] = []
	if _use_skin:
		if animated_sprite != null:
			nodes.append(animated_sprite)
		return nodes
	for poly in _cube_nodes():
		if poly != null:
			nodes.append(poly)
	return nodes

## Tinte base de un nodo de FX: el cubo usa su color plano (modulate blanco)
## y la sprite el tinte de arquetipo.
func _fx_base_tint(node: CanvasItem) -> Color:
	if node != null and node == animated_sprite:
		return _base_modulate
	return Color.WHITE

## Escala actual de cada polígono del cubo. Se lee en el momento del FX:
## Zombie.gd la fija por arquetipo al instanciar y puede cambiarla después.
## Escala base del cubo por arquetipo.
## `Zombie.gd:_apply_kind()` la fija con `set_cube_base_scales()`, que aplica
## la escala y ACTUALIZA esta base en la MISMA operación. Antes era una
## instantánea tomada en `set_type()`, lo que dejaba un protocolo implícito
## ("asignar escala → set_type()") y permitía que un cambio de escala
## posterior fuera pisado por el FX al restaurar la base.
##
## Sin esta memoria, `_fx_scale_targets()` releía la escala deformada por el
## último FX: el cubo se quedaba deformado para siempre y las deformaciones
## se acumulaban (medido: escala 1.38 tras telegrafía + squash encadenados,
## cuando la base del arquetipo es 1.0).
var _cube_base_scales: Array[Vector2] = []

## Fija la escala del cubo por arquetipo Y su base en una sola operación.
## Es la única vía para cambiar la escala base: así el FX siempre restaura
## la escala vigente y no una instantánea desfasada.
func set_cube_base_scales(body_scale: Vector2, nose_scale: Vector2) -> void:
	_kill_fx_tweens()
	_is_telegraphing = false
	if _cube_body != null:
		_cube_body.scale = body_scale
	if _cube_nose != null:
		_cube_nose.scale = nose_scale
	_restore_fx_tint()
	_capture_cube_base_scales()

## Captura la escala actual del cubo como nueva escala base.
func _capture_cube_base_scales() -> void:
	_cube_base_scales.clear()
	for poly in _cube_nodes():
		_cube_base_scales.append(poly.scale if poly != null else Vector2.ONE)

## Escala base de lo que se está viendo (la del cubo o la de la sprite).
func _fx_scale_targets() -> Array[Vector2]:
	var targets: Array[Vector2] = []
	if _use_skin:
		targets.append(_sprite_base_scale)
		return targets
	var nodes: Array[Polygon2D] = _cube_nodes()
	for i in nodes.size():
		if i < _cube_base_scales.size():
			targets.append(_cube_base_scales[i])
		else:
			targets.append(nodes[i].scale if nodes[i] != null else Vector2.ONE)
	return targets

func _restore_fx_scale() -> void:
	var nodes: Array[CanvasItem] = _fx_nodes()
	var targets: Array[Vector2] = _fx_scale_targets()
	for i in nodes.size():
		if nodes[i] != null and i < targets.size():
			nodes[i].scale = targets[i]

func _restore_fx_tint() -> void:
	for poly in _cube_nodes():
		if poly != null:
			poly.modulate = Color.WHITE
	if _use_skin and animated_sprite != null:
		animated_sprite.modulate = _base_modulate

## Cancela FX anteriores y deja lo que se ve exactamente en su estado base.
func _reset_fx() -> void:
	_kill_fx_tweens()
	_is_telegraphing = false
	if animated_sprite != null:
		animated_sprite.scale = _base_scale
		animated_sprite.modulate = _base_modulate
	_restore_fx_scale()
	_restore_fx_tint()

## Mata TODOS los tweens de FX (no solo el último).
func _kill_fx_tweens() -> void:
	for t in _fx_tweens:
		if t != null and t.is_valid():
			t.kill()
	_fx_tweens.clear()

func _on_fx_finished() -> void:
	_is_telegraphing = false
	if animated_sprite != null:
		animated_sprite.scale = _base_scale
		animated_sprite.modulate = _base_modulate
	_restore_fx_scale()
	_restore_fx_tint()
	_fx_tweens.clear()

## Aplastamiento al recibir daño: ancho extra y alto reducido.
func squash(amount: float = 0.85, duration: float = 0.12) -> void:
	_reset_fx()
	var factor: float = clampf(amount, 0.5, 1.0)
	var base: Array[Vector2] = _fx_scale_targets()
	var target: Array[Vector2] = []
	for b in base:
		target.append(Vector2(b.x / factor, b.y * factor))
	_start_fx_scale_tween(target, base, duration * 0.4, duration * 0.6)

## Estiramiento al atacar: estrecho y alto, como un resorte.
func stretch(amount: float = 0.88, duration: float = 0.12) -> void:
	_reset_fx()
	var factor: float = clampf(amount, 0.5, 1.0)
	var base: Array[Vector2] = _fx_scale_targets()
	var target: Array[Vector2] = []
	for b in base:
		target.append(Vector2(b.x * factor, b.y / factor))
	_start_fx_scale_tween(target, base, duration * 0.4, duration * 0.6)

## Aplica la escala a TODO lo que se ve a la vez (cubo o skin).
## `amount` 0 = escala base, 1 = escala objetivo.
func _apply_fx_scale(amount: float, base: Array[Vector2], target: Array[Vector2]) -> void:
	var nodes: Array[CanvasItem] = _fx_nodes()
	for i in nodes.size():
		var node: CanvasItem = nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		if i < base.size() and i < target.size():
			node.scale = base[i].lerp(target[i], amount)

## Tween MAESTRO de un efecto de escala: UN solo tween para todo lo visible.
## Con un tween por nodo, el `finished` conectado solo al último podía
## dejar al otro escribiendo escala mientras un FX nuevo ya había empezado.
func _start_fx_scale_tween(target: Array[Vector2], base: Array[Vector2],
		t_in: float, t_out: float) -> void:
	var master: Tween = create_tween()
	master.tween_method(_apply_fx_scale.bind(base, target), 0.0, 1.0, t_in)
	master.tween_method(_apply_fx_scale.bind(base, target), 1.0, 0.0, t_out)
	_fx_tweens.append(master)
	master.finished.connect(_on_fx_finished)

func punch_scale(amount: float = 0.88, duration: float = 0.12) -> void:
	stretch(amount, duration)


## Telegrafía por arquetipo (kind coincide con Zombie.Kind / ZombieType).
## TANK: aura roja + tamaño. SPITTER: inflado previo. SCREAMER: onda pulsante.
## BOSS: dos pulsos rojos anchos (carga/slam). WALKER/RUNNER: aviso sutil.
## Todo se hace sobre el CUBO, nunca hitboxes.
func telegraph(kind: int) -> void:
	if _is_dying:
		return
	_reset_fx()
	_is_telegraphing = true
	var factor: float = 1.05
	var tint: Color = Color.WHITE
	var hold: float = 0.07
	var pulses: int = 1
	match kind:
		2:  # TANK - aura roja y ensanchamiento antes de la carga
			factor = 1.18
			tint = Color(1.0, 0.30, 0.30, 1.0)
			hold = 0.12
		3:  # SPITTER - se infla antes de escupir
			factor = 1.34
			tint = Color(0.65, 1.0, 0.60, 1.0)
			hold = 0.10
		4:  # SCREAMER - onda expansiva (tres pulsos)
			factor = 1.10
			tint = Color(1.0, 0.70, 1.0, 1.0)
			hold = 0.06
			pulses = 3
		5:  # BOSS "Tanque Alfa" - dos pulsos rojos anchos antes de la carga
			factor = 1.28
			tint = BOSS_BAR_PHASE_2  # BLOOD_BRIGHT, paleta canónica
			hold = 0.14
			pulses = 2
		1:  # RUNNER - aviso breve
			factor = 1.07
			tint = Color(1.0, 0.82, 0.82, 1.0)
			hold = 0.04
		_:  # WALKER - aviso mínimo
			factor = 1.04
			tint = Color(1.0, 0.92, 0.92, 1.0)
			hold = 0.04
	# R1-polish: un ÚNICO tween maestro para todo el cubo y fases SECUENCIALES
	# dentro: subir (0.07) -> hold -> bajar (0.10) -> (hold) -> repetir.
	# - El patrón anterior (`set_parallel` + `tween_interval` + `set_parallel`)
	#   no respetaba el hold: la bajada arrancaba en el mismo instante que la
	#   subida y el pulso de aviso era invisible (medido con sonda Godot 4.7.2).
	# - Con un tween por polígono, el `finished` conectado solo al último
	#   dejaba al otro escribiendo escala mientras un FX nuevo empezaba.
	# - Ahora el tween maestro escribe TODOS los polígonos en la misma
	#   llamada, así que hay un solo dueño del ciclo de vida.
	var base_list: Array[Vector2] = _fx_scale_targets()
	var master: Tween = create_tween()
	for _pulse in range(pulses):
		# `tween_method` llama con (valor, ...argumentos_bound), por eso el
		# helper recibe primero el valor interpolado.
		master.tween_method(_apply_pulse_all.bind(base_list, factor, tint),
			0.0, 1.0, 0.07)
		master.tween_interval(hold)
		master.tween_method(_apply_pulse_all.bind(base_list, factor, tint),
			1.0, 0.0, 0.10)
	_fx_tweens.append(master)
	master.finished.connect(_on_fx_finished)

## Telegrafía: aplica escala + tinte a TODO lo visible a la vez.
## `amount` 0 = estado base, 1 = estado pulsado.
func _apply_pulse_all(amount: float, base_list: Array[Vector2],
		factor: float, tint: Color) -> void:
	var nodes: Array[CanvasItem] = _fx_nodes()
	for i in nodes.size():
		var node: CanvasItem = nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		if i < base_list.size():
			var base: Vector2 = base_list[i]
			node.scale = base.lerp(base * factor, amount)
		node.modulate = _fx_base_tint(node).lerp(tint, amount)

func play_attack() -> void:
	# Si hay telegrafía en curso, ella ya está animando la escala: no la corta.
	if not _is_telegraphing:
		punch_scale()
	_is_attacking = true
	_attack_timer = ATTACK_FALLBACK
	if animated_sprite != null:
		animated_sprite.play("attack")

func play_hit() -> void:
	if _is_dying:
		return
	squash(0.78, 0.14)
	if animated_sprite != null:
		animated_sprite.play("hit")
	_hit_timer = HIT_FALLBACK
	_current_state = ""

func play_death() -> void:
	# La muerte es la dueña del estado visual: si el zombi muere durante una
	# telegrafia o un squash, el tween seguiria deformando y tiñendo el cadaver
	# mientras se reproduce el clip de muerte. Se cancelan los FX y se
	# restauran escala y tinte ANTES de empezar el clip.
	_reset_fx()
	_is_dying = true
	if boss_bar != null:
		boss_bar.visible = false
	if animated_sprite != null:
		animated_sprite.play("death")

func play_crawl() -> void:
	if _is_dying:
		return
	if animated_sprite != null:
		animated_sprite.play("crawl")
	_current_state = ""

func _on_animation_finished() -> void:
	if animated_sprite == null:
		return
	if _is_attacking and animated_sprite.animation == "attack":
		_is_attacking = false
		_attack_timer = 0.0
		_current_state = ""  # Forzar actualización en siguiente frame
	
	if _is_dying and animated_sprite.animation == "death":
		# La animación de muerte termina, el zombie se queda en el último frame
		pass

func set_modulate_color(color: Color) -> void:
	if animated_sprite != null:
		animated_sprite.modulate = color
	for poly in _cube_nodes():
		if poly != null:
			poly.modulate = color

func get_sprite_rect() -> Rect2:
	if animated_sprite == null:
		return Rect2()
	return animated_sprite.get_rect()
