extends Node2D
class_name ZombieVisual

## =============================================================================
## ZOMBIE VISUAL - AnimatedSprite2D por tipo de zombi
## =============================================================================
## Tipos: WALKER, RUNNER, TANK, SPITTER, SCREAMER
## Animaciones: idle, walk, run, attack, hit, death, crawl
## =============================================================================

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

## Hojas de pixel art real generadas por tools/gen_art.py (ADR-001).
## Todas comparten el mismo layout: 8 animaciones x 4 frames, 8 columnas de 32x32.
const SHEETS: Array[String] = [
	"res://assets/art/sprites/zombie_walker.png",
	"res://assets/art/sprites/zombie_runner.png",
	"res://assets/art/sprites/zombie_tank.png",
	"res://assets/art/sprites/zombie_spitter.png",
	"res://assets/art/sprites/zombie_screamer.png",
]
const FRAME: int = 32
const SHEET_COLS: int = 8

## AtlasTexture creados por _setup_animations(); set_type solo cambia su atlas.
var _frame_atlases: Array[AtlasTexture] = []

var _current_state: String = "idle"
var _is_attacking: bool = false
var _is_dying: bool = false

## Game feel: squash/stretch y telegrafía comparten un único tween para que
## nunca peleen por animated_sprite.scale. Solo se anima el sprite: las
## hitboxes del Zombie son hermanas de este nodo y permanecen intactas.
var _base_scale: Vector2 = Vector2.ONE
var _base_modulate: Color = Color.WHITE
var _fx_tween: Tween
var _is_telegraphing: bool = false

## Zombie.tscn no asigna sprite_frames y este script no añade frames: las siete
## animaciones quedan vacías, así que animation_finished nunca se emite. El
## fallback temporal es lo único que desbloquea update_state() (PlayerVisual sí
## tiene frames procedurales y necesita el suyo por ser clips muy cortos).
var _attack_timer: float = 0.0
const ATTACK_FALLBACK: float = 0.5

## Tipos de zombi (coincide con Zombie.Kind)
enum ZombieType { WALKER, RUNNER, TANK, SPITTER, SCREAMER }

func _ready() -> void:
	_setup_animations()
	# Base antes de set_type(): este último la recalcula por arquetipo.
	_base_scale = animated_sprite.scale
	_base_modulate = animated_sprite.modulate
	# Pixel art: muestreo puntual, sin interpolación (ADR-001).
	animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if animated_sprite.material is CanvasItemMaterial:
		(animated_sprite.material as CanvasItemMaterial).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	animated_sprite.play("idle")
	animated_sprite.animation_finished.connect(_on_animation_finished)

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

	# Frames reales desde la hoja del walker (hoja por defecto). set_type()
	# sustituye el atlas por el del arquetipo correspondiente.
	var sheet: Texture2D = load(SHEETS[ZombieType.WALKER]) as Texture2D
	if sheet == null:
		push_warning("ZombieVisual: no se pudo cargar %s" % SHEETS[ZombieType.WALKER])
	_install_frames(frames, sheet, anims, SHEET_COLS)

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

## Instala 4 frames por animación desde una hoja de celdas de 32x32 y guarda
## los AtlasTexture para poder cambiar de arquetipo sin reconstruir SpriteFrames.
func _install_frames(frames: SpriteFrames, sheet: Texture2D,
		anims: Array, cols: int) -> void:
	_frame_atlases.clear()
	var cell: int = 0
	for anim_variant in anims:
		var anim: String = String(anim_variant)
		while frames.get_frame_count(anim) > 0:
			frames.remove_frame(anim, frames.get_frame_count(anim) - 1)
		for f in range(4):
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			var col: int = cell % cols
			var row: int = int(floor(float(cell) / float(cols)))
			atlas.region = Rect2(float(col * FRAME), float(row * FRAME),
				float(FRAME), float(FRAME))
			frames.add_frame(anim, atlas, 1.0, f)
			_frame_atlases.append(atlas)
			cell += 1

## Cambia la hoja de arte manteniendo regiones, speeds y timers intactos.
func _apply_sheet(type: int) -> void:
	if type < 0 or type >= SHEETS.size():
		type = ZombieType.WALKER
	var sheet: Texture2D = load(SHEETS[type]) as Texture2D
	if sheet == null:
		push_warning("ZombieVisual: no se pudo cargar %s" % SHEETS[type])
		return
	for atlas in _frame_atlases:
		atlas.atlas = sheet

func _process(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer = maxf(_attack_timer - delta, 0.0)
		if _attack_timer <= 0.0 and _is_attacking:
			_is_attacking = false
			_current_state = ""  # Forzar actualización en siguiente frame

func set_type(type: int) -> void:
	# Hoja de arte según arquetipo (visual); no toca combate ni timers.
	_apply_sheet(type)
	# Ajustar velocidades y escala según tipo
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

	# Cada arquetipo define la escala/tinte base sobre la que vuelven los FX.
	_base_scale = animated_sprite.scale
	_base_modulate = animated_sprite.modulate

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

## Cancela FX anteriores y deja el sprite exactamente en su estado base.
func _reset_fx() -> void:
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = null
	_is_telegraphing = false
	animated_sprite.scale = _base_scale
	animated_sprite.modulate = _base_modulate

func _on_fx_finished() -> void:
	_is_telegraphing = false
	animated_sprite.scale = _base_scale
	animated_sprite.modulate = _base_modulate
	_fx_tween = null

## Aplastamiento al recibir daño: ancho extra y alto reducido.
func squash(amount: float = 0.85, duration: float = 0.12) -> void:
	_reset_fx()
	var factor: float = clampf(amount, 0.5, 1.0)
	var target: Vector2 = Vector2(_base_scale.x / factor, _base_scale.y * factor)
	_fx_tween = create_tween()
	_fx_tween.tween_property(animated_sprite, "scale", target, duration * 0.4)
	_fx_tween.tween_property(animated_sprite, "scale", _base_scale, duration * 0.6)
	_fx_tween.finished.connect(_on_fx_finished)

## Estiramiento al atacar: estrecho y alto, como un resorte.
func stretch(amount: float = 0.88, duration: float = 0.12) -> void:
	_reset_fx()
	var factor: float = clampf(amount, 0.5, 1.0)
	var target: Vector2 = Vector2(_base_scale.x * factor, _base_scale.y / factor)
	_fx_tween = create_tween()
	_fx_tween.tween_property(animated_sprite, "scale", target, duration * 0.4)
	_fx_tween.tween_property(animated_sprite, "scale", _base_scale, duration * 0.6)
	_fx_tween.finished.connect(_on_fx_finished)

func punch_scale(amount: float = 0.88, duration: float = 0.12) -> void:
	stretch(amount, duration)


## Telegrafía por arquetipo (kind coincide con Zombie.Kind / ZombieType).
## TANK: aura roja + tamaño. SPITTER: inflado previo. SCREAMER: onda pulsante.
## WALKER/RUNNER: aviso sutil. Todo se hace sobre el sprite, nunca hitboxes.
func telegraph(kind: int) -> void:
	if _is_dying:
		return
	_reset_fx()
	_is_telegraphing = true
	var factor: float = 1.05
	var tint: Color = _base_modulate
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
		1:  # RUNNER - aviso breve
			factor = 1.07
			tint = Color(1.0, 0.82, 0.82, 1.0)
			hold = 0.04
		_:  # WALKER - aviso mínimo
			factor = 1.04
			tint = Color(1.0, 0.92, 0.92, 1.0)
			hold = 0.04
	_fx_tween = create_tween()
	for _pulse in range(pulses):
		_fx_tween.set_parallel(true)
		_fx_tween.tween_property(animated_sprite, "scale", _base_scale * factor, 0.07)
		_fx_tween.tween_property(animated_sprite, "modulate", tint, 0.07)
		_fx_tween.set_parallel(false)
		_fx_tween.tween_interval(hold)
		_fx_tween.set_parallel(true)
		_fx_tween.tween_property(animated_sprite, "scale", _base_scale, 0.10)
		_fx_tween.tween_property(animated_sprite, "modulate", _base_modulate, 0.10)
		_fx_tween.set_parallel(false)
	_fx_tween.finished.connect(_on_fx_finished)

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

func get_sprite_rect() -> Rect2:
	return animated_sprite.get_rect()