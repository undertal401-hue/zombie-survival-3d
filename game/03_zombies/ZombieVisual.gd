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

func play_attack() -> void:
	_is_attacking = true
	_attack_timer = ATTACK_FALLBACK
	animated_sprite.play("attack")

func play_hit() -> void:
	if _is_dying:
		return
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