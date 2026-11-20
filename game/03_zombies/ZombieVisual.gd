extends Node2D
class_name ZombieVisual

## =============================================================================
## ZOMBIE VISUAL - el cubo (Polygon2D) es el sprite actual
## =============================================================================
## R1 (2026-11-20): el usuario decide que los personajes se quedan como CUBO
## y que él hará el arte pixel después. Por tanto:
##   - NO se carga ninguna hoja PNG (las hojas y tools/gen_art.py se conservan
##     como banco de trabajo para ese arte futuro).
##   - El cubo `Body`/`Nose` del Zombie queda VISIBLE; su color y escala por
##     arquetipo los sigue fijando Zombie.gd (`_apply_kind`).
##   - Squash/stretch y telegrafía se aplican al CUBO, nunca a las hitboxes.
##   - Se conserva la barra de vida del jefe (Ítem 12) y las 8 animaciones;
##     sin frames, el fallback temporal gobierna la duración (como en ea329e8).
## =============================================================================

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
## CAPA 2 / ÍTEM 12: barra exclusiva del jefe. No existe en el HUD global para
## no repartir estado: el propio Zombie empuja su ratio de vida aquí.
@onready var boss_bar: Node2D = $boss_bar
@onready var boss_health: ColorRect = $boss_bar/boss_health

## El cubo visible (Polygon2D del Zombie). Lo escala Zombie.gd por arquetipo;
## aquí solo se anima (squash/telegrafía) y se tiñe.
@onready var _cube_body: Polygon2D = get_node_or_null("../Body") as Polygon2D
@onready var _cube_nose: Polygon2D = get_node_or_null("../Nose") as Polygon2D

var _current_state: String = "idle"
var _is_attacking: bool = false
var _is_dying: bool = false

## Zombie.tscn no asigna sprite_frames y este script no añade frames: las ocho
## animaciones quedan vacías, así que animation_finished nunca se emite. El
## fallback temporal es lo único que desbloquea update_state().
var _attack_timer: float = 0.0
const ATTACK_FALLBACK: float = 0.5

## Tipos de zombi (coincide con Zombie.Kind)
enum ZombieType { WALKER, RUNNER, TANK, SPITTER, SCREAMER, BOSS }

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
var _cube_tweens: Array[Tween] = []
var _is_telegraphing: bool = false

func _ready() -> void:
	_setup_animations()
	_base_scale = animated_sprite.scale
	_base_modulate = animated_sprite.modulate
	# Muestreo puntual (sin interpolación): el objetivo es pixel art.
	animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if animated_sprite.material is CanvasItemMaterial:
		(animated_sprite.material as CanvasItemMaterial).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	animated_sprite.play("idle")
	animated_sprite.animation_finished.connect(_on_animation_finished)

	# Presentación R1: se ve el CUBO. El AnimatedSprite2D queda oculto porque
	# no tiene frames (el arte pixel real lo hará el usuario más adelante).
	_apply_presentation()

## Interruptor de presentación. false = cubo (actual). true = la sprite de
## frames pasa a verse y el cubo se oculta (arte futuro del usuario).
const USE_SPRITE_ART: bool = false

func _apply_presentation() -> void:
	var cube_nodes: Array[Polygon2D] = _cube_nodes()
	for poly in cube_nodes:
		if poly != null:
			poly.visible = not USE_SPRITE_ART
	animated_sprite.visible = USE_SPRITE_ART
	# La escala base se captura aquí: `set_type()` la actualizará con la del
	# arquetipo cuando Zombie.gd aplique el tipo.
	_capture_cube_base_scales()

func _setup_animations() -> void:
	if animated_sprite.sprite_frames == null:
		animated_sprite.sprite_frames = SpriteFrames.new()
	
	var frames: SpriteFrames = animated_sprite.sprite_frames
	
	# `hurt` es el nombre canónico; `hit` se conserva por compatibilidad.
	var anims: Array[String] = [
		"idle", "walk", "run", "attack", "hit", "hurt", "death", "crawl"
	]

	for anim in anims:
		if not frames.has_animation(anim):
			frames.add_animation(anim)

	# Velocidades base (se ajustan por tipo en set_type)
	frames.set_animation_speed("idle", 6)
	frames.set_animation_speed("walk", 8)
	frames.set_animation_speed("run", 12)
	frames.set_animation_speed("attack", 18)
	frames.set_animation_speed("hit", 15)
	frames.set_animation_speed("hurt", 15)
	frames.set_animation_speed("death", 5)
	frames.set_animation_speed("crawl", 4)
	
	# Loop settings
	frames.set_animation_loop("idle", true)
	frames.set_animation_loop("walk", true)
	frames.set_animation_loop("run", true)
	frames.set_animation_loop("attack", false)
	frames.set_animation_loop("hit", false)
	frames.set_animation_loop("hurt", false)
	frames.set_animation_loop("death", false)
	frames.set_animation_loop("crawl", true)

func _process(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer = maxf(_attack_timer - delta, 0.0)
		if _attack_timer <= 0.0 and _is_attacking:
			_is_attacking = false
			_current_state = ""  # Forzar actualización en siguiente frame

func set_type(type: int) -> void:
	# Cancelar CUALQUIER efecto en curso y devolver el cubo a su estado base:
	# antes solo se mataban los tweens, así que `_is_telegraphing` seguía en
	# true y el tinte/la escala deformada se quedaban pegados al cubo.
	_reset_fx()
	_capture_cube_base_scales()
	# Ajustar velocidades y escala según tipo (el cubo lo tinte Zombie.gd).
	var frames: SpriteFrames = animated_sprite.sprite_frames
	if frames == null:
		return
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

## La barra del jefe se actualiza desde Zombie con el ratio hp/max_hp real.
## En fase 2 (enraged) cambia a BLOOD_BRIGHT para señalar el cambio de patrón.
func update_boss_health(ratio: float, enraged: bool = false) -> void:
	if boss_bar == null or boss_health == null:
		return
	boss_bar.visible = not _is_dying
	boss_health.offset_right = -24.0 + BOSS_BAR_WIDTH * clampf(ratio, 0.0, 1.0)
	boss_health.color = BOSS_BAR_PHASE_2 if enraged else BOSS_BAR_PHASE_1


func update_state(velocity: Vector2, is_chasing: bool, target_direction: Vector2, is_crawling: bool = false) -> void:
	if _is_attacking or _is_dying:
		return
	
	var speed: float = velocity.length()
	var new_state: String
	
	if is_crawling:
		new_state = "crawl" if speed >= 5.0 else "idle"
	elif speed < 5.0:
		new_state = "idle"
	elif speed < 50.0:
		new_state = "walk"
	else:
		new_state = "run"
	
	# Flip horizontal
	if target_direction.x != 0:
		animated_sprite.flip_h = target_direction.x < 0
	
	if new_state != _current_state:
		_current_state = new_state
		animated_sprite.play(new_state)

## --- Cubo: lo que realmente se ve -------------------------------------------

func _cube_nodes() -> Array[Polygon2D]:
	var nodes: Array[Polygon2D] = []
	if _cube_body != null:
		nodes.append(_cube_body)
	if _cube_nose != null:
		nodes.append(_cube_nose)
	return nodes

## Escala actual de cada polígono del cubo. Se lee en el momento del FX:
## Zombie.gd la fija por arquetipo al instanciar y puede cambiarla después.
## Escala base del cubo por arquetipo.
## `Zombie.gd:_apply_kind()` la fija con `set_cube_base_scales()`, que aplica
## la escala y ACTUALIZA esta base en la MISMA operación. Antes era una
## instantánea tomada en `set_type()`, lo que dejaba un protocolo implícito
## ("asignar escala → set_type()") y permitía que un cambio de escala
## posterior fuera pisado por el FX al restaurar la base.
##
## Sin esta memoria, `_cube_scale_targets()` releía la escala deformada por el
## último FX: el cubo se quedaba deformado para siempre y las deformaciones
## se acumulaban (medido: escala 1.38 tras telegrafía + squash encadenados,
## cuando la base del arquetipo es 1.0).
var _cube_base_scales: Array[Vector2] = []

## Fija la escala del cubo por arquetipo Y su base en una sola operación.
## Es la única vía para cambiar la escala base: así el FX siempre restaura
## la escala vigente y no una instantánea desfasada.
func set_cube_base_scales(body_scale: Vector2, nose_scale: Vector2) -> void:
	_kill_cube_tweens()
	_is_telegraphing = false
	if _cube_body != null:
		_cube_body.scale = body_scale
	if _cube_nose != null:
		_cube_nose.scale = nose_scale
	_restore_cube_tint()
	_capture_cube_base_scales()

## Captura la escala actual del cubo como nueva escala base.
func _capture_cube_base_scales() -> void:
	_cube_base_scales.clear()
	for poly in _cube_nodes():
		_cube_base_scales.append(poly.scale if poly != null else Vector2.ONE)

## Escala base de cada polígono del cubo (la que fija el arquetipo).
func _cube_scale_targets() -> Array[Vector2]:
	var targets: Array[Vector2] = []
	var nodes: Array[Polygon2D] = _cube_nodes()
	for i in nodes.size():
		if i < _cube_base_scales.size():
			targets.append(_cube_base_scales[i])
		else:
			targets.append(nodes[i].scale if nodes[i] != null else Vector2.ONE)
	return targets

func _restore_cube_scale() -> void:
	var nodes: Array[Polygon2D] = _cube_nodes()
	var targets: Array[Vector2] = _cube_scale_targets()
	for i in nodes.size():
		if nodes[i] != null:
			nodes[i].scale = targets[i]

func _restore_cube_tint() -> void:
	for poly in _cube_nodes():
		if poly != null:
			poly.modulate = Color.WHITE

## Cancela FX anteriores y deja el cubo exactamente en su estado base.
func _reset_fx() -> void:
	_kill_cube_tweens()
	_is_telegraphing = false
	animated_sprite.scale = _base_scale
	animated_sprite.modulate = _base_modulate
	_restore_cube_scale()
	_restore_cube_tint()

## Mata TODOS los tweens del cubo (no solo el último).
func _kill_cube_tweens() -> void:
	for t in _cube_tweens:
		if t != null and t.is_valid():
			t.kill()
	_cube_tweens.clear()

func _on_fx_finished() -> void:
	_is_telegraphing = false
	animated_sprite.scale = _base_scale
	animated_sprite.modulate = _base_modulate
	_restore_cube_scale()
	_restore_cube_tint()
	_cube_tweens.clear()

## Aplastamiento al recibir daño: ancho extra y alto reducido.
func squash(amount: float = 0.85, duration: float = 0.12) -> void:
	_reset_fx()
	var factor: float = clampf(amount, 0.5, 1.0)
	var base: Array[Vector2] = _cube_scale_targets()
	var target: Array[Vector2] = []
	for b in base:
		target.append(Vector2(b.x / factor, b.y * factor))
	_start_cube_scale_tween(target, base, duration * 0.4, duration * 0.6)

## Estiramiento al atacar: estrecho y alto, como un resorte.
func stretch(amount: float = 0.88, duration: float = 0.12) -> void:
	_reset_fx()
	var factor: float = clampf(amount, 0.5, 1.0)
	var base: Array[Vector2] = _cube_scale_targets()
	var target: Array[Vector2] = []
	for b in base:
		target.append(Vector2(b.x * factor, b.y / factor))
	_start_cube_scale_tween(target, base, duration * 0.4, duration * 0.6)

## Aplica la escala a TODOS los polígonos del cubo a la vez.
## `amount` 0 = escala base, 1 = escala objetivo.
func _apply_cube_scale(amount: float, base: Array[Vector2], target: Array[Vector2]) -> void:
	var nodes: Array[Polygon2D] = _cube_nodes()
	for i in nodes.size():
		var poly: Polygon2D = nodes[i]
		if poly == null or not is_instance_valid(poly):
			continue
		if i < base.size() and i < target.size():
			poly.scale = base[i].lerp(target[i], amount)

## Tween MAESTRO de un efecto de escala: UN solo tween para todo el cubo.
## Con un tween por polígono, el `finished` conectado solo al último podía
## dejar al otro escribiendo escala mientras un FX nuevo ya había empezado.
func _start_cube_scale_tween(target: Array[Vector2], base: Array[Vector2],
		t_in: float, t_out: float) -> void:
	var master: Tween = create_tween()
	master.tween_method(_apply_cube_scale.bind(base, target), 0.0, 1.0, t_in)
	master.tween_method(_apply_cube_scale.bind(base, target), 1.0, 0.0, t_out)
	_cube_tweens.append(master)
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
	var base_list: Array[Vector2] = _cube_scale_targets()
	var master: Tween = create_tween()
	for _pulse in range(pulses):
		# `tween_method` llama con (valor, ...argumentos_bound), por eso el
		# helper recibe primero el valor interpolado.
		master.tween_method(_apply_pulse_all.bind(base_list, factor, tint),
			0.0, 1.0, 0.07)
		master.tween_interval(hold)
		master.tween_method(_apply_pulse_all.bind(base_list, factor, tint),
			1.0, 0.0, 0.10)
	_cube_tweens.append(master)
	master.finished.connect(_on_fx_finished)

## Telegrafía: aplica escala + tinte a TODO el cubo a la vez.
## `amount` 0 = estado base, 1 = estado pulsado.
func _apply_pulse_all(amount: float, base_list: Array[Vector2],
		factor: float, tint: Color) -> void:
	var nodes: Array[Polygon2D] = _cube_nodes()
	for i in nodes.size():
		var poly: Polygon2D = nodes[i]
		if poly == null or not is_instance_valid(poly):
			continue
		if i < base_list.size():
			var base: Vector2 = base_list[i]
			poly.scale = base.lerp(base * factor, amount)
		poly.modulate = Color.WHITE.lerp(tint, amount)

func play_attack() -> void:
	# Si hay telegrafía en curso, ella ya está animando la escala: no la corta.
	if not _is_telegraphing:
		punch_scale()
	_is_attacking = true
	_attack_timer = ATTACK_FALLBACK
	animated_sprite.play("attack")

func play_hit() -> void:
	if _is_dying:
		return
	squash(0.78, 0.14)
	animated_sprite.play("hit")
	_current_state = ""

func play_death() -> void:
	_is_dying = true
	if boss_bar != null:
		boss_bar.visible = false
	animated_sprite.play("death")

func play_crawl() -> void:
	if _is_dying:
		return
	animated_sprite.play("crawl")
	_current_state = ""

func _on_animation_finished() -> void:
	if _is_attacking and animated_sprite.animation == "attack":
		_is_attacking = false
		_attack_timer = 0.0
		_current_state = ""  # Forzar actualización en siguiente frame
	
	if _is_dying and animated_sprite.animation == "death":
		# La animación de muerte termina, el zombie se queda en el último frame
		pass

func set_modulate_color(color: Color) -> void:
	animated_sprite.modulate = color
	for poly in _cube_nodes():
		if poly != null:
			poly.modulate = color

func get_sprite_rect() -> Rect2:
	return animated_sprite.get_rect()
