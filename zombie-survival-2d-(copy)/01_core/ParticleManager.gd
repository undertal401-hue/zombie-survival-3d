extends Node

## =============================================================================
## PARTICLE MANAGER - Pool de partículas para evitar instanciar/destruir constantemente
## =============================================================================

static var instance: ParticleManager

var _blood_pool: Array[GPUParticles2D] = []
var _impact_pool: Array[GPUParticles2D] = []
var _muzzle_pool: Array[GPUParticles2D] = []

var _blood_scene: PackedScene = preload("res://assets/particles/BloodParticles.tscn")
var _impact_scene: PackedScene = preload("res://assets/particles/ImpactParticles.tscn")
var _muzzle_scene: PackedScene = preload("res://assets/particles/MuzzleFlashParticles.tscn")

const POOL_SIZE: int = 30
var _pools_initialized: bool = false
var _reuse_index: int = 0

## --- Decals poolados (ÍTEM 4) -------------------------------------------------
## Tope duro: el combate intenso nunca debe acumular más de 64 decals.
const MAX_DECALS: int = 64

## Paleta canónica de `res://assets/art/ART_BIBLE.md` (§2, tabla de 16 colores).
## Se mantienen los hex como const para que el módulo siga funcionando aunque
## el archivo de arte no esté disponible; `_load_decal_palette()` los sobrescribe
## con los valores leídos del ART_BIBLE al iniciar.
const ART_BIBLE_PATH: String = "res://assets/art/ART_BIBLE.md"
const BLOOD_HEX: String = "#b52b20"        # BLOOD (índice 13, rojo sangre canónico)
const BLOOD_DARK_HEX: String = "#6e1712"   # BLOOD_DARK (sangre seca)
const BLOOD_BRIGHT_HEX: String = "#e8563c" # BLOOD_BRIGHT (sangre fresca)
const STEEL_DARK_HEX: String = "#55626d"   # STEEL_DARK (metal / hormigón)
const STEEL_LIGHT_HEX: String = "#9aabb6"  # STEEL_LIGHT
const LEATHER_DARK_HEX: String = "#33261a" # LEATHER_DARK (madera)
const OLIVE_DARK_HEX: String = "#33421f"   # OLIVE_DARK (carne podrida)

## Tiempo de vida de cada decal, en segundos (configurable desde el inspector).
@export var decal_lifetime: float = 14.0

## Pool de Sprite2D ligeros. El contenedor `Decals` es hijo de este autoload.
var decal_pool: Array[Sprite2D] = []
var _decal_container: Node2D
var _decal_cursor: int = 0
var _decal_time_left: PackedFloat32Array = PackedFloat32Array()
var _decal_texture: ImageTexture
var _decal_palette: Dictionary = {}

func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_load_decal_palette()
	# Inicializar pools de forma diferida para evitar errores de "busy setting up children"
	call_deferred("_initialize_pools")

func _initialize_pools() -> void:
	# Guard temprano: _ready() agenda esta función con call_deferred(), pero un
	# _get_*() puede ejecutarse antes de que el deferred se procese. Sin este
	# guard se crearían dos veces los pools (90 partículas extra por vez).
	if _pools_initialized:
		return
	_pools_initialized = true
	_ensure_decal_container()
	for i in range(POOL_SIZE):
		_blood_pool.push_back(_create_blood())
		_impact_pool.push_back(_create_impact())
		_muzzle_pool.push_back(_create_muzzle())

func _create_blood() -> GPUParticles2D:
	var p: GPUParticles2D = _blood_scene.instantiate()
	get_tree().root.add_child(p)
	p.emitting = false
	return p

func _create_impact() -> GPUParticles2D:
	var p: GPUParticles2D = _impact_scene.instantiate()
	get_tree().root.add_child(p)
	p.emitting = false
	return p

func _create_muzzle() -> GPUParticles2D:
	var p: GPUParticles2D = _muzzle_scene.instantiate()
	get_tree().root.add_child(p)
	p.emitting = false
	return p

## Busca un emisor libre; si todos están ocupados reutiliza uno en round-robin
## en vez de instanciar otro. Sin este límite, un combate intenso (o varias
## partidas, ya que este nodo es autoload) acumula GPUParticles2D bajo root
## sin liberarlos nunca.
func _take_emitter(pool: Array[GPUParticles2D]) -> GPUParticles2D:
	if not _pools_initialized:
		_initialize_pools()
	for p in pool:
		if not p.emitting:
			return p
	if pool.is_empty():
		return null
	var reused: GPUParticles2D = pool[_reuse_index % pool.size()]
	_reuse_index += 1
	return reused

func _get_blood() -> GPUParticles2D:
	return _take_emitter(_blood_pool)

func _get_impact() -> GPUParticles2D:
	return _take_emitter(_impact_pool)

func _get_muzzle() -> GPUParticles2D:
	return _take_emitter(_muzzle_pool)

## API Pública

func spawn_blood(position: Vector2, direction: Vector2 = Vector2.ZERO, count: int = 20) -> void:
	var p: GPUParticles2D = _get_blood()
	if p == null:
		return
	p.global_position = position
	if direction != Vector2.ZERO:
		p.rotation = direction.angle()
	p.amount = count
	p.emitting = true

func spawn_blood_burst(position: Vector2, direction: Vector2, count: int = 10) -> void:
	spawn_blood(position, direction, count)

func spawn_wall_blood(position: Vector2, normal: Vector2, count: int = 15) -> void:
	var p: GPUParticles2D = _get_blood()
	if p == null:
		return
	p.global_position = position
	p.rotation = normal.angle() - PI/2
	p.amount = count
	p.emitting = true

func spawn_impact(position: Vector2, direction: Vector2, surface: int = 1) -> void:
	var p: GPUParticles2D = _get_impact()
	if p == null:
		return
	p.global_position = position
	if direction != Vector2.ZERO:
		p.rotation = direction.angle()
	p.emit_at(position, direction, surface)

func spawn_impact_metal(position: Vector2, direction: Vector2) -> void:
	spawn_impact(position, direction, ImpactParticles.SurfaceType.METAL)

func spawn_impact_concrete(position: Vector2, direction: Vector2) -> void:
	spawn_impact(position, direction, ImpactParticles.SurfaceType.CONCRETE)

func spawn_impact_wood(position: Vector2, direction: Vector2) -> void:
	spawn_impact(position, direction, ImpactParticles.SurfaceType.WOOD)

func spawn_impact_flesh(position: Vector2, direction: Vector2) -> void:
	spawn_impact(position, direction, ImpactParticles.SurfaceType.FLESH)

func spawn_impact_dirt(position: Vector2, direction: Vector2) -> void:
	spawn_impact(position, direction, ImpactParticles.SurfaceType.DIRT)

func spawn_muzzle_flash(position: Vector2, direction: Vector2, weapon_type: int = 0) -> void:
	var p: GPUParticles2D = _get_muzzle()
	if p == null:
		return
	p.global_position = position
	p.rotation = direction.angle()
	p.emit_at(position, direction, weapon_type)


## =============================================================================
## DECALS — manchas persistentes pooladas con identidad pixel art
## =============================================================================

## Crea (o reutiliza) un decal en `pos`. El color se pasa explícitamente; los
## puntos de combate usan `palette_color()` para garantizar que viene de la
## paleta del ART_BIBLE. Nunca se instancian escenas: Sprite2D + ImageTexture
## 8×8 compartida, filtro NEAREST y posición snapped al píxel.
func spawn_decal(kind: StringName, pos: Vector2, color: Color) -> void:
	var container: Node2D = _ensure_decal_container()
	if container == null:
		return
	var sprite: Sprite2D
	var time_index: int
	if decal_pool.size() < MAX_DECALS:
		sprite = _create_decal_sprite()
		decal_pool.append(sprite)
		_decal_time_left.append(0.0)
		container.add_child(sprite)
		time_index = decal_pool.size() - 1
	else:
		time_index = _decal_cursor % decal_pool.size()
		sprite = decal_pool[time_index]
	_decal_cursor += 1
	var snapped: Vector2 = pos.round()
	var variant_seed: int = int(absf(snapped.x) + absf(snapped.y)) % 4
	sprite.global_position = snapped
	sprite.rotation = float(variant_seed) * (PI * 0.5)
	sprite.scale = Vector2.ONE * _decal_scale_for(kind)
	sprite.modulate = color
	sprite.set_meta("decal_color", color)
	sprite.visible = true
	_decal_time_left[time_index] = maxf(decal_lifetime, 0.0)


## Color canónico de la paleta leída del ART_BIBLE; si falta el archivo se usan
## las constantes hex derivadas del mismo documento (fallback documentado).
func palette_color(name: StringName) -> Color:
	if _decal_palette.has(name):
		return _decal_palette[name] as Color
	return _fallback_palette_color(name)


func _fallback_palette_color(name: StringName) -> Color:
	match name:
		&"blood":
			return Color(BLOOD_HEX)
		&"blood_dark", &"flesh":
			return Color(BLOOD_DARK_HEX)
		&"blood_bright":
			return Color(BLOOD_BRIGHT_HEX)
		&"steel_light":
			return Color(STEEL_LIGHT_HEX)
		&"wood", &"dirt", &"leather_dark":
			return Color(LEATHER_DARK_HEX)
		&"olive_dark":
			return Color(OLIVE_DARK_HEX)
		_:
			return Color(STEEL_DARK_HEX)


## Parsea la tabla "§2. Paleta canónica" del ART_BIBLE en tiempo de ejecución.
## Solo acepta celdas `| N | NOMBRE | #rrggbb | ... |`, de modo que el resto del
## documento (incluidos los encabezados) no contamina la paleta.
func _load_decal_palette() -> void:
	_decal_palette = {
		&"blood": Color(BLOOD_HEX),
		&"blood_dark": Color(BLOOD_DARK_HEX),
		&"blood_bright": Color(BLOOD_BRIGHT_HEX),
		&"steel_dark": Color(STEEL_DARK_HEX),
		&"steel_light": Color(STEEL_LIGHT_HEX),
		&"leather_dark": Color(LEATHER_DARK_HEX),
		&"olive_dark": Color(OLIVE_DARK_HEX),
	}
	if not FileAccess.file_exists(ART_BIBLE_PATH):
		push_warning("ParticleManager: ART_BIBLE.md no disponible; se usa la paleta const derivada de él.")
		return
	var text: String = FileAccess.get_file_as_string(ART_BIBLE_PATH)
	for line in text.split("\n"):
		if not line.begins_with("|"):
			continue
		var cells: PackedStringArray = line.split("|")
		if cells.size() < 4:
			continue
		var name: String = cells[2].strip_edges().to_lower()
		var hex: String = cells[3].strip_edges()
		if name.is_empty() or hex.length() < 7 or not hex.begins_with("#"):
			continue
		hex = hex.substr(0, 7).to_lower()
		if not _is_hex_color(hex):
			continue
		_decal_palette[StringName(name)] = Color.html(hex)


func _is_hex_color(value: String) -> bool:
	if value.length() != 7 or not value.begins_with("#"):
		return false
	const DIGITS: String = "0123456789abcdef"
	for i in range(1, 7):
		if not DIGITS.contains(value.substr(i, 1)):
			return false
	return true


func _ensure_decal_container() -> Node2D:
	if is_instance_valid(_decal_container):
		return _decal_container
	var existing: Node = get_node_or_null("Decals")
	if existing is Node2D:
		_decal_container = existing as Node2D
		return _decal_container
	var container: Node2D = Node2D.new()
	container.name = "Decals"
	add_child(container)
	_decal_container = container
	return _decal_container


func _create_decal_sprite() -> Sprite2D:
	if _decal_texture == null:
		_decal_texture = _build_decal_texture()
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = _decal_texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = true
	sprite.z_index = -1
	return sprite


## Mancha 8×8 en blanco con alpha recortado; el color real se aplica por
## modulate. Una sola textura para todo el pool, sin assets en disco.
func _build_decal_texture() -> ImageTexture:
	var mask: Array[String] = [
		"00100100",
		"01111110",
		"11111111",
		"11111111",
		"11111111",
		"01111110",
		"00100100",
		"00011000",
	]
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in range(8):
		var row: String = mask[y]
		for x in range(8):
			var opaque: bool = row.substr(x, 1) == "1"
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0 if opaque else 0.0))
	return ImageTexture.create_from_image(image)


func _decal_scale_for(kind: StringName) -> float:
	match kind:
		&"blood", &"flesh", &"zombie", &"blood_bright":
			return 2.0
		&"impact", &"concrete", &"metal", &"wood", &"dirt":
			return 1.5
		_:
			return 1.5


## Envejecimiento de decals: se ocultan al expirar y se reinician al reutilizar.
## No se hace queue_free() para mantener el pool acotado y estable.
func _process(delta: float) -> void:
	if decal_pool.is_empty():
		return
	for i in range(decal_pool.size()):
		var remaining: float = _decal_time_left[i]
		if remaining <= 0.0:
			continue
		remaining -= delta
		if remaining <= 0.0:
			_decal_time_left[i] = 0.0
			decal_pool[i].visible = false
			continue
		_decal_time_left[i] = remaining
		if remaining < 2.0:
			var base: Color = decal_pool[i].get_meta("decal_color", Color.WHITE)
			base.a *= clampf(remaining / 2.0, 0.0, 1.0)
			decal_pool[i].modulate = base
