extends Node2D
class_name PlayerVisual

## =============================================================================
## PLAYER VISUAL - el cubo (Polygon2D) es el sprite actual
## =============================================================================
## R1 (2026-11-20): el usuario decide que el personaje se queda como CUBO y
## que el arte pixel real lo hará él más adelante. Por tanto:
##   - NO se carga ninguna hoja PNG (las hojas y tools/gen_art.py se conservan
##     como banco de trabajo para ese arte futuro).
##   - El cubo `Body`/`Nose` del Player queda VISIBLE.
##   - Squash/stretch, telegrafía y hit-flash se aplican al CUBO, para que el
##     game feel siga siendo visible sin sprites.
##   - `load_sprite_sheet()` / `load_all_from_atlas()` siguen disponibles como
##     API: cuando el usuario instale su arte, basta con llamar a esas
##     funciones y poner `USE_SPRITE_ART = true`.
## =============================================================================

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var held_item: Sprite2D = $HeldItem

## Interruptor de presentación. false = cubo (actual). true = la sprite de
## frames pasa a verse y el cubo se oculta (arte futuro del usuario).
const USE_SPRITE_ART: bool = false

var _current_state: String = "idle"
var _is_attacking: bool = false
## Las animaciones no tienen frames (mismo contrato que los zombis en
## ea329e8): animation_finished nunca se emite, así que el fallback temporal
## fija la duración mínima de ataques y recargas.
var _attack_timer: float = 0.0

## Hit flash effect
var _hit_flash_timer: float = 0.0
var _hit_flash_duration: float = 0.1
@onready var _hit_flash_material: ShaderMaterial = preload("res://assets/shaders/HitFlashMaterial.tres")

## El cubo visible (Polygon2D del Player). Se escala y se tiñe, nunca la
## CollisionShape2D: las hitboxes quedan intactas.
@onready var _cube_body: Polygon2D = get_node_or_null("../Body") as Polygon2D
@onready var _cube_nose: Polygon2D = get_node_or_null("../Nose") as Polygon2D

## Squash / stretch (game feel): escala el cubo.
## R1: antes se creaba UN tween por polígono dentro de un bucle y solo se
## guardaba el último (`_squash_tween`), así que los anteriores quedaban
## huérfanos peleándose por la escala del cubo. Ahora se guardan TODOS y
## `_reset_fx()` los mata antes de aplicar el siguiente efecto.
var _base_scale: Vector2 = Vector2.ONE
var _cube_tweens: Array[Tween] = []
var _cube_base_scales: Array[Vector2] = []

## Estados de animación
enum AnimState {
	IDLE, WALK, RUN, 
	ATTACK_MELEE, ATTACK_PISTOL, ATTACK_SHOTGUN, ATTACK_RIFLE,
	RELOAD_PISTOL, RELOAD_SHOTGUN, RELOAD_RIFLE,
	HURT, DEATH
}

func _ready() -> void:
	_setup_animations()
	# La escala base del sprite sale del .tscn: se captura antes de cualquier tween.
	_base_scale = animated_sprite.scale
	# Muestreo puntual (sin interpolación): el objetivo es pixel art.
	animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if animated_sprite.material is CanvasItemMaterial:
		(animated_sprite.material as CanvasItemMaterial).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	animated_sprite.play("idle")
	animated_sprite.animation_finished.connect(_on_animation_finished)

	# Sprite para mostrar el objeto/arma equipado en el personaje.
	held_item.visible = false
	held_item.scale = Vector2(0.8, 0.8)
	held_item.z_index = 10
	held_item.offset = Vector2(8, -4)

	# Presentación: cubo visible, sprite de frames oculto (o al revés si el
	# usuario activa USE_SPRITE_ART con su arte).
	_apply_presentation()

	# Aplicar material de hit flash al sprite. Se mantiene aunque el sprite no
	# se vea: el arnés TestFixes (check 35) lee su uniform.
	animated_sprite.material = _hit_flash_material.duplicate()
	_set_hit_flash(0.0)

func _apply_presentation() -> void:
	var cube_nodes: Array[Polygon2D] = _cube_nodes()
	for poly in cube_nodes:
		if poly != null:
			poly.visible = not USE_SPRITE_ART
	animated_sprite.visible = USE_SPRITE_ART
	_cube_base_scales.clear()
	for poly in cube_nodes:
		if poly != null:
			_cube_base_scales.append(poly.scale)

## Los dos polígonos del cubo del Player (Body y Nose).
func _cube_nodes() -> Array[Polygon2D]:
	var nodes: Array[Polygon2D] = []
	if _cube_body != null:
		nodes.append(_cube_body)
	if _cube_nose != null:
		nodes.append(_cube_nose)
	return nodes

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

	# Velocidades definitivas (sin frames: el fallback temporal gobierna).
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

func update_from_player(player: Node2D, velocity: Vector2, weapon_controller: Node) -> void:
	if player == null:
		return
	
	var is_moving: bool = velocity.length() > 1.0
	var is_running: bool = Input.is_action_pressed("sprint") and is_moving
	# weapon_controller permanece en la firma porque Player.gd lo pasa, pero
	# hoy no se consulta: el arma se resuelve en play_attack()/play_reload()
	# desde el category que Player entrega. Quitar el parámetro exigiría tocar
	# Player.gd, fuera de esta superficie.
	
	# Orientación: el nodo Player ya rota hacia el ratón (rotation = +X hacia
	# el puntero), así que el cubo mira al objetivo sin transformaciones
	# adicionales. El sprite de frames mantiene su corrección de eje para
	# cuando el usuario instale su arte.
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

## Devuelve el cubo a su escala base y cancela cualquier FX previo.
func _reset_fx() -> void:
	for t in _cube_tweens:
		if t != null and t.is_valid():
			t.kill()
	_cube_tweens.clear()
	animated_sprite.scale = _base_scale
	_restore_cube_scale()


## Escala base actual de cada polígono del cubo (puede venir del arquetipo).
func _cube_scale_targets() -> Array[Vector2]:
	var targets: Array[Vector2] = []
	var nodes: Array[Polygon2D] = _cube_nodes()
	for i in nodes.size():
		var poly: Polygon2D = nodes[i]
		if poly == null:
			targets.append(Vector2.ONE)
			continue
		if i < _cube_base_scales.size():
			targets.append(_cube_base_scales[i])
		else:
			targets.append(poly.scale)
	return targets


func _restore_cube_scale() -> void:
	var nodes: Array[Polygon2D] = _cube_nodes()
	var targets: Array[Vector2] = _cube_scale_targets()
	for i in nodes.size():
		if nodes[i] != null:
			nodes[i].scale = targets[i]


## Aplastamiento: ancho extra, alto reducido, vuelta a la base.
func squash(amount: float = 0.85, duration: float = 0.12) -> void:
	_reset_fx()
	var factor: float = clampf(amount, 0.5, 1.0)
	var nodes: Array[Polygon2D] = _cube_nodes()
	var targets: Array[Vector2] = _cube_scale_targets()
	for i in nodes.size():
		var poly: Polygon2D = nodes[i]
		if poly == null:
			continue
		var base: Vector2 = targets[i]
		var target: Vector2 = Vector2(base.x / factor, base.y * factor)
		_cube_tweens.append(_scale_tween(poly, target, base, duration))


## Estiramiento: estrecho y alto, vuelta a la base. Es el "punch" del ataque.
func stretch(amount: float = 0.88, duration: float = 0.12) -> void:
	_reset_fx()
	var factor: float = clampf(amount, 0.5, 1.0)
	var nodes: Array[Polygon2D] = _cube_nodes()
	var targets: Array[Vector2] = _cube_scale_targets()
	for i in nodes.size():
		var poly: Polygon2D = nodes[i]
		if poly == null:
			continue
		var base: Vector2 = targets[i]
		var target: Vector2 = Vector2(base.x * factor, base.y / factor)
		_cube_tweens.append(_scale_tween(poly, target, base, duration))


## Tween de escala de UN polígono: dos fases SECUENCIALES (aplastar -> volver).
## Un tween por polígono: los polígonos se animan a la vez (son tweens
## distintos) y ninguno queda huérfano.
func _scale_tween(poly: Polygon2D, target: Vector2, base: Vector2, duration: float) -> Tween:
	var tween: Tween = create_tween()
	tween.tween_property(poly, "scale", target, duration * 0.4)
	tween.tween_property(poly, "scale", base, duration * 0.6)
	return tween


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
	# Sin frames no hay animation_finished: imponer duración mínima.
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
	for poly in _cube_nodes():
		if poly != null:
			poly.modulate = color

## API para cargar sprites reales desde archivos (pipeline ADR-001).
## El usuario la usará cuando tenga su arte: llama a load_all_from_atlas() con
## la hoja y pone USE_SPRITE_ART = true.
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
	# El cubo es lo que se ve: el destello se aplica también a sus polígonos.
	var flash: float = clampf(progress, 0.0, 1.0)
	var tint: Color = Color(1.0, 1.0 - 0.45 * flash, 1.0 - 0.45 * flash, 1.0)
	for poly in _cube_nodes():
		if poly != null:
			poly.modulate = tint

## Muestra el sprite del objeto/arma equipado en el personaje.
## Cada tipo de objeto tiene un color distinto (pixel art simple).
func set_held_item(item_id: String) -> void:
	if item_id == "" or item_id == null:
		held_item.visible = false
		held_item.texture = null
		return

	# Colores pixel art para cada tipo de objeto
	var color_map: Dictionary = {
		"Pistola 9mm": Color(255, 50, 50, 255),       # Rojo - pistola
		"Escopeta 12ga": Color(255, 150, 50, 255),     # Naranja - escopeta
		"Fusil 5.56mm": Color(50, 100, 255, 255),      # Azul - fusil
		"Machete": Color(50, 200, 50, 255),            # Verde - machete
		"scrap": Color(139, 69, 19, 255),              # Marrón - madera/chatarra
		"cloth": Color(200, 200, 200, 255),            # Gris - tela
		"medkit": Color(200, 50, 50, 255),             # Rojo oscuro - botiquín
		"comida": Color(255, 215, 0, 255),             # Amarillo - comida
		"pistol_ammo": Color(0, 200, 200, 255),        # Cian - munición pistola
		"rifle_ammo": Color(0, 150, 255, 255),         # Azul claro - munición fusil
		"shotgun_ammo": Color(255, 100, 0, 255),       # Naranja oscuro - munición escopeta
		"combustible": Color(200, 100, 0, 255),        # Naranja - combustible
		"vehicle_fuel": Color(255, 50, 0, 255),        # Naranja rojo - combustible vehículo
		"llave": Color(150, 50, 200, 255),             # Púrpura - llave
	}

	var color: Color = color_map.get(item_id, Color.WHITE)
	var tex: ImageTexture = _make_color_texture(color)
	held_item.texture = tex
	held_item.visible = true

func _make_color_texture(color: Color) -> ImageTexture:
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	return tex
