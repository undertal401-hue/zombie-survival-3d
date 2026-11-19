extends Node2D
class_name PlayerVisual

## =============================================================================
## PLAYER VISUAL - AnimatedSprite2D con todas las animaciones
## =============================================================================
## Maneja: idle, walk, run, attack_* (melee/pistola/escopeta/fusil), reload_* (pistola/escopeta/fusil), hurt, death
## Se conecta a Player para recibir estado de movimiento/acción
## =============================================================================

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

## Hoja real generada por tools/gen_art.py (ADR-001): 32x32, palette-locked.
const PLAYER_SHEET: String = "res://assets/art/sprites/player_sheet.png"
const FRAME: int = 32
const SHEET_COLS: int = 8

var _current_state: String = "idle"
var _is_attacking: bool = false
## Las animaciones usan 4 frames procedurales reutilizados para todas las
## acciones. animation_finished sí se emite, pero los clips son muy cortos:
## ataques y recargas necesitan un fallback temporal que fije su duración mínima.
var _attack_timer: float = 0.0

## Hit flash effect
var _hit_flash_timer: float = 0.0
var _hit_flash_duration: float = 0.1
@onready var _hit_flash_material: ShaderMaterial = preload("res://assets/shaders/HitFlashMaterial.tres")

## Squash / stretch (ADR game feel): solo escala el AnimatedSprite2D. El
## CollisionShape2D del Player es hermano de este nodo, así que las hitboxes
## nunca se tocan. La escala base la fija Player.tscn (1.15, 1.15).
var _base_scale: Vector2 = Vector2.ONE
var _squash_tween: Tween

## Estados de animación
enum AnimState {
	IDLE, WALK, RUN, 
	ATTACK_MELEE, ATTACK_PISTOL, ATTACK_SHOTGUN, ATTACK_RIFLE,
	RELOAD_PISTOL, RELOAD_SHOTGUN, RELOAD_RIFLE,
	HURT, DEATH
}

func _ready() -> void:
	_setup_animations()
	# La escala del sprite sale del .tscn: se captura antes de cualquier tween.
	_base_scale = animated_sprite.scale
	# Pixel art: muestreo puntual, sin interpolación (ADR-001).
	animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if animated_sprite.material is CanvasItemMaterial:
		(animated_sprite.material as CanvasItemMaterial).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	animated_sprite.play("idle")
	animated_sprite.animation_finished.connect(_on_animation_finished)

	# El sprite procedural sustituye al cubo verde de depuración. Se ocultan
	# los Polygon2D del Player para que no se dibujen encima de la sprite.
	for node_name in ["Body", "Nose"]:
		var debug_poly := get_node_or_null("../%s" % node_name) as Polygon2D
		if debug_poly != null:
			debug_poly.visible = false

	# Aplicar material de hit flash al sprite
	animated_sprite.material = _hit_flash_material.duplicate()
	_set_hit_flash(0.0)

func _process(delta: float) -> void:
	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
		var progress: float = clampf(_hit_flash_timer / _hit_flash_duration, 0.0, 1.0)
		_set_hit_flash(progress)

	if _attack_timer > 0.0:
		_attack_timer = maxf(_attack_timer - delta, 0.0)
		if _attack_timer <= 0.0 and _is_attacking:
			_is_attacking = false
			_current_state = ""

func _setup_animations() -> void:
	# Crear SpriteFrames programáticamente si no existe
	if animated_sprite.sprite_frames == null:
		animated_sprite.sprite_frames = SpriteFrames.new()
	
	var frames: SpriteFrames = animated_sprite.sprite_frames
	
	# Añadir todas las animaciones necesarias
	var anims: Array[String] = [
		"idle", "walk", "run",
		"attack_melee", "attack_pistol", "attack_shotgun", "attack_rifle",
		"reload_pistol", "reload_shotgun", "reload_rifle",
		"hurt", "death"
	]
	
	for anim in anims:
		if not frames.has_animation(anim):
			frames.add_animation(anim)

	# Hoja de pixel art real (ADR-001): 12 animaciones x 4 frames en una retícula
	# de 8 columnas de celdas de 32x32. Cada animação conserva sus 4 frames.
	var sheet: Texture2D = load(PLAYER_SHEET) as Texture2D
	if sheet == null:
		push_warning("PlayerVisual: no se pudo cargar %s" % PLAYER_SHEET)
	_install_frames(frames, sheet, anims, SHEET_COLS)

	# Velocidades definitivas sobre la hoja bitmap.
	frames.set_animation_speed("idle", 8)
	frames.set_animation_speed("walk", 10)
	frames.set_animation_speed("run", 14)
	frames.set_animation_speed("attack_melee", 20)
	frames.set_animation_speed("attack_pistol", 18)
	frames.set_animation_speed("attack_shotgun", 16)
	frames.set_animation_speed("attack_rifle", 22)
	frames.set_animation_speed("reload_pistol", 10)
	frames.set_animation_speed("reload_shotgun", 8)
	frames.set_animation_speed("reload_rifle", 10)
	frames.set_animation_speed("hurt", 12)
	frames.set_animation_speed("death", 6)
	
	# Loop settings
	frames.set_animation_loop("idle", true)
	frames.set_animation_loop("walk", true)
	frames.set_animation_loop("run", true)
	frames.set_animation_loop("attack_melee", false)
	frames.set_animation_loop("attack_pistol", false)
	frames.set_animation_loop("attack_shotgun", false)
	frames.set_animation_loop("attack_rifle", false)
	frames.set_animation_loop("reload_pistol", false)
	frames.set_animation_loop("reload_shotgun", false)
	frames.set_animation_loop("reload_rifle", false)
	frames.set_animation_loop("hurt", false)
	frames.set_animation_loop("death", false)

## Instala 4 frames por animación desde una hoja de celdas de 32x32.
## `cell` se numera en orden de lectura: fila 0 primero, izq. -> der.
func _install_frames(frames: SpriteFrames, sheet: Texture2D,
		anims: Array, cols: int) -> void:
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
			cell += 1

func update_from_player(player: Node2D, velocity: Vector2, weapon_controller: Node) -> void:
	if player == null:
		return
	
	var is_moving: bool = velocity.length() > 1.0
	var is_running: bool = Input.is_action_pressed("sprint") and is_moving
	# weapon_controller permanece en la firma porque Player.gd lo pasa, pero
	# hoy no se consulta: el arma se resuelve en play_attack()/play_reload()
	# desde el category que Player entrega. Quitar el parámetro exigiría tocar
	# Player.gd, fuera de esta superficie.
	
	# Orientación del sprite (también durante ataques y recargas): el dibujo
	# procedural tiene la coronilla y el cañón hacia -Y, pero el nodo Player
	# apunta +X. Como este sprite es hijo del jugador, su rotación global es
	# player.rotation + animated_sprite.rotation; compensamos +PI/2 para que
	# el -Y del dibujo caiga exactamente sobre la dirección del ratón.
	# No se usa flip_h: espejar el dibujo partía el arma y la coronilla.
	var to_mouse: Vector2 = player.get_global_mouse_position() - player.global_position
	if to_mouse.length_squared() > 0.25:
		var aim_angle: float = to_mouse.angle()
		var delta: float = wrapf(aim_angle - player.rotation, -PI, PI)
		animated_sprite.rotation = PI * 0.5 + delta
	else:
		animated_sprite.rotation = PI * 0.5
	animated_sprite.flip_h = false
	
	# Determinar estado
	var new_state: String
	
	if _is_attacking:
		return  # No interrumpir animación de ataque/recarga
	
	if is_running:
		new_state = "run"
	elif is_moving:
		new_state = "walk"
	else:
		new_state = "idle"
	
	# Cambiar animación si cambió el estado
	if new_state != _current_state:
		_current_state = new_state
		animated_sprite.play(new_state)

## Devuelve el sprite a su escala base y cancela cualquier FX previo.
func _reset_fx() -> void:
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	_squash_tween = null
	animated_sprite.scale = _base_scale


## Aplastamiento: ancho extra, alto reducido, vuelta a la base.
func squash(amount: float = 0.85, duration: float = 0.12) -> void:
	_reset_fx()
	var factor: float = clampf(amount, 0.5, 1.0)
	var target: Vector2 = Vector2(_base_scale.x / factor, _base_scale.y * factor)
	_squash_tween = create_tween()
	_squash_tween.tween_property(animated_sprite, "scale", target, duration * 0.4)
	_squash_tween.tween_property(animated_sprite, "scale", _base_scale, duration * 0.6)


## Estiramiento: estrecho y alto, vuelta a la base. Es el "punch" del ataque.
func stretch(amount: float = 0.88, duration: float = 0.12) -> void:
	_reset_fx()
	var factor: float = clampf(amount, 0.5, 1.0)
	var target: Vector2 = Vector2(_base_scale.x * factor, _base_scale.y / factor)
	_squash_tween = create_tween()
	_squash_tween.tween_property(animated_sprite, "scale", target, duration * 0.4)
	_squash_tween.tween_property(animated_sprite, "scale", _base_scale, duration * 0.6)


func punch_scale(amount: float = 0.88, duration: float = 0.12) -> void:
	stretch(amount, duration)


func play_attack(weapon_category: int) -> void:
	punch_scale()
	_is_attacking = true
	var anim_name: String
	match weapon_category:
		0: anim_name = "attack_melee"
		1: anim_name = "attack_pistol"
		2: anim_name = "attack_shotgun"
		3: anim_name = "attack_rifle"
		_: anim_name = "attack_pistol"
	
	animated_sprite.play(anim_name)
	# Los frames procedurales terminan demasiado pronto: imponer duración mínima.
	_attack_timer = 0.35

func play_reload(weapon_category: int) -> void:
	_is_attacking = true
	var anim_name: String
	match weapon_category:
		1: anim_name = "reload_pistol"
		2: anim_name = "reload_shotgun"
		3: anim_name = "reload_rifle"
		_: anim_name = "reload_pistol"
	
	animated_sprite.play(anim_name)
	_attack_timer = 0.9

func play_hurt() -> void:
	squash(0.8, 0.16)
	animated_sprite.play("hurt")
	# Trigger hit flash
	_hit_flash_timer = _hit_flash_duration
	_set_hit_flash(1.0)

func play_death() -> void:
	animated_sprite.play("death")

func _on_animation_finished() -> void:
	# Con frames reales la animación termina antes del fallback: limpiar ambos.
	if animated_sprite.animation in ["attack_melee", "attack_pistol", "attack_shotgun", "attack_rifle",
		"reload_pistol", "reload_shotgun", "reload_rifle"]:
		_is_attacking = false
		_attack_timer = 0.0
		_current_state = ""

func set_modulate_color(color: Color) -> void:
	animated_sprite.modulate = color

## API para cargar sprites reales desde archivos (pipeline ADR-001).
func load_sprite_sheet(anim_name: String, texture: Texture2D,
		h_frames: int, v_frames: int, frame_count: int = -1) -> void:
	var frames: SpriteFrames = animated_sprite.sprite_frames
	if frames == null or texture == null or h_frames <= 0 or v_frames <= 0:
		return
	if not frames.has_animation(anim_name):
		frames.add_animation(anim_name)
	while frames.get_frame_count(anim_name) > 0:
		frames.remove_frame(anim_name, frames.get_frame_count(anim_name) - 1)
	var fw: int = int(floor(float(texture.get_width()) / float(h_frames)))
	var fh: int = int(floor(float(texture.get_height()) / float(v_frames)))
	var total: int = h_frames * v_frames
	if frame_count > 0:
		total = mini(frame_count, total)
	for i in range(total):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		var col: int = i % h_frames
		var row: int = int(floor(float(i) / float(h_frames)))
		atlas.region = Rect2(float(col * fw), float(row * fh),
			float(fw), float(fh))
		frames.add_frame(anim_name, atlas, 1.0, i)

## layout = { "anim": {"h_frames": int, "v_frames": int, "frame_count": int} }
func load_all_from_atlas(atlas: Texture2D, layout: Dictionary) -> void:
	for anim_variant in layout.keys():
		var cfg: Dictionary = layout[anim_variant] as Dictionary
		if cfg == null:
			continue
		load_sprite_sheet(String(anim_variant), atlas,
			int(cfg.get("h_frames", 1)), int(cfg.get("v_frames", 1)),
			int(cfg.get("frame_count", -1)))

func _set_hit_flash(progress: float) -> void:
	var mat := animated_sprite.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("hit_flash_progress", progress)