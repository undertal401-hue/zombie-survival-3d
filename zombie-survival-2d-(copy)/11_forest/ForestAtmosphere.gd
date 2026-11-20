extends Node2D

## Atmósfera ligera del bosque: linterna ámbar que sigue al jugador y viñeta
## verde oliva apagado por debajo del HUD. La luz solar la gestiona Main.gd.

const LANTERN_COLOR: Color = Color(1.0, 0.72, 0.32)
const LANTERN_ENERGY: float = 0.22
const LANTERN_OFFSET: Vector2 = Vector2(0.0, -8.0)
const VIGNETTE_EDGE: Color = Color(0.06, 0.08, 0.05, 0.42)
const TEXTURE_SIZE: int = 256
const LANTERN_FADE_IN: float = 0.5
const LANTERN_FADE_OUT: float = 0.5
const VIGNETTE_FADE_IN: float = 0.8
const VIGNETTE_FADE_OUT: float = 0.5

var _player: Node2D = null
var _lantern: PointLight2D = null
var _vignette_layer: CanvasLayer = null
var _vignette: TextureRect = null
var _lantern_tween: Tween = null
var _vignette_tween: Tween = null
var _in_forest: bool = false

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node2D
	EventBus.forest_entered.connect(_on_forest_entered)
	EventBus.forest_exited.connect(_on_forest_exited)
	_build_lantern()
	_build_vignette()

func _build_lantern() -> void:
	_lantern = PointLight2D.new()
	_lantern.name = "Lantern"
	_lantern.texture = _make_radial_texture(
		Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)
	)
	_lantern.color = LANTERN_COLOR
	_lantern.energy = 0.0
	_lantern.texture_scale = 3.0  # Radio base 128 px x 3 ≈ 380 px (float en Godot 4).
	_lantern.enabled = false
	add_child(_lantern)

func _build_vignette() -> void:
	_vignette_layer = CanvasLayer.new()
	_vignette_layer.name = "ForestVignette"
	_vignette_layer.layer = 0  # Por debajo del HUD (1) y del inventario (2).
	add_child(_vignette_layer)

	_vignette = TextureRect.new()
	_vignette.name = "Vignette"
	_vignette.texture = _make_radial_texture(
		Color(1.0, 1.0, 1.0, 0.0), VIGNETTE_EDGE
	)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_vignette_layer.add_child(_vignette)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _make_radial_texture(p_center: Color, p_edge: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([p_center, p_edge])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = TEXTURE_SIZE
	texture.height = TEXTURE_SIZE
	return texture

func _process(_delta: float) -> void:
	if not _in_forest or not is_instance_valid(_player):
		return
	_lantern.global_position = _player.global_position + LANTERN_OFFSET

func _on_forest_entered() -> void:
	if _in_forest:
		return
	_in_forest = true
	_kill_tweens()
	if is_instance_valid(_player):
		_lantern.global_position = _player.global_position + LANTERN_OFFSET
	_lantern.enabled = true

	_lantern_tween = create_tween()
	_lantern_tween.tween_property(_lantern, "energy", LANTERN_ENERGY, LANTERN_FADE_IN)

	_vignette_tween = create_tween()
	_vignette_tween.tween_property(_vignette, "modulate:a", 1.0, VIGNETTE_FADE_IN)

func _on_forest_exited() -> void:
	if not _in_forest:
		return
	_in_forest = false
	_kill_tweens()

	_lantern_tween = create_tween()
	_lantern_tween.tween_property(_lantern, "energy", 0.0, LANTERN_FADE_OUT)
	_lantern_tween.tween_callback(_disable_lantern)

	_vignette_tween = create_tween()
	_vignette_tween.tween_property(_vignette, "modulate:a", 0.0, VIGNETTE_FADE_OUT)

func _kill_tweens() -> void:
	if _lantern_tween != null and _lantern_tween.is_valid():
		_lantern_tween.kill()
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()

func _disable_lantern() -> void:
	if is_instance_valid(_lantern):
		_lantern.enabled = false
