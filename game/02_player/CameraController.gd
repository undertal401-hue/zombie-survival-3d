extends Camera2D
## CAPA 1, ÍTEM 9 — cámara con suavizado, look-ahead, shake direccional y
## zoom punch. La cámara es hija del jugador: hereda su transformación y lo
## sigue sin código extra. Este script solo gestiona `offset` y `zoom`.
##
## El `offset` tiene AUTORÍA EXCLUSIVA aquí: cada frame se recompone como
## `look_offset + shake_offset` y se redondea a píxel para no romper el snap 2D
## de la Capa 0. El shake se SUMA al look-ahead, nunca lo sustituye.

# --- Configuración -------------------------------------------------------------
@export var look_ahead_distance: float = 120.0  ## tope de desplazamiento hacia el ratón (px)
@export var look_ahead_smoothing: float = 8.0   ## velocidad del lerp (1/s)
@export var shake_decay: float = 7.0            ## decaimiento exponencial del shake (1/s)
@export var shake_max_offset: float = 24.0      ## tope práctico del temblor (px)
@export var punch_amount: float = 0.06          ## profundidad por defecto del zoom punch
@export var punch_in_time: float = 0.07         ## duración de la ida del punch
@export var punch_out_time: float = 0.16        ## duración de la vuelta a (1,1)

# --- Estado interno ------------------------------------------------------------
var _look_offset: Vector2 = Vector2.ZERO
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_dir: Vector2 = Vector2.ZERO
var _shake_mag: float = 0.0

var _weapon_controller: Node = null
var _punch_tween: Tween = null

# --- Ciclo de vida -------------------------------------------------------------

func _ready() -> void:
	set_process(true)
	_connect_weapon_fire()
	_connect_player_damage()

func _exit_tree() -> void:
	_disconnect_weapon_fire()
	_disconnect_player_damage()
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	_punch_tween = null

func _process(delta: float) -> void:
	look_ahead(delta)
	_decay_shake(delta)
	# El shake se suma al look-ahead; round() respeta el snap a píxel de la Capa 0.
	offset = (_look_offset + _shake_offset).round()

# --- ÍTEM 9a. Look-ahead -------------------------------------------------------

## Desplaza suavemente el offset hacia el ratón, limitado a ~120 px.
func look_ahead(delta: float) -> void:
	# En headless no hay puntero real: un ratón fantasma en (0,0) desplazaría
	# la cámara 120 px y rompería el clamp de QA. Sin puntero, objetivo = centro.
	if DisplayServer.get_name() == "headless":
		_look_offset = _look_offset.lerp(Vector2.ZERO, clampf(delta * look_ahead_smoothing, 0.0, 1.0))
		return
	var mouse: Vector2 = get_global_mouse_position()
	var target: Vector2 = mouse - global_position
	if target.length() > look_ahead_distance:
		target = target.normalized() * look_ahead_distance
	_look_offset = _look_offset.lerp(target, clampf(delta * look_ahead_smoothing, 0.0, 1.0))

# --- ÍTEM 9b. Shake direccional ------------------------------------------------

## Kick direccional con decaimiento exponencial. `direction` marca el eje del
## golpe; si no hay dirección (p. ej. daño recibido) se elige un ángulo aleatorio
## defendible en lugar de un Vector2.ZERO que no produciría temblor.
func shake(direction: Vector2, intensity: float) -> void:
	var mag: float = clampf(intensity, 0.0, shake_max_offset * 4.0)
	if mag <= 0.0:
		return
	var dir: Vector2 = direction
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT.rotated(randf() * TAU)
	else:
		dir = dir.normalized()
	_shake_dir = dir
	_shake_mag = maxf(_shake_mag, mag)
	_shake_offset = dir * mag

func _decay_shake(delta: float) -> void:
	if _shake_mag <= 0.05:
		_shake_mag = 0.0
		_shake_offset = Vector2.ZERO
		return
	_shake_mag *= exp(-shake_decay * delta)
	# Jitter pequeño sobre el eje direccional para que el temblor siga "vivo".
	var jitter: Vector2 = Vector2(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0) * (_shake_mag * 0.25)
	_shake_offset = _shake_dir * _shake_mag + jitter

# --- ÍTEM 9c. Zoom punch -------------------------------------------------------

## Zoom punch temporal: reduce el zoom y vuelve a (1,1) mediante un Tween.
func punch(amount: float) -> void:
	var depth: float = clampf(amount, 0.0, 0.5)
	if depth <= 0.0:
		return
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	var target: float = maxf(0.5, 1.0 - depth)
	_punch_tween = create_tween()
	_punch_tween.tween_property(self, "zoom", Vector2(target, target), punch_in_time)
	_punch_tween.tween_property(self, "zoom", Vector2.ONE, punch_out_time)

# --- Conexiones defensivas -----------------------------------------------------

func _connect_weapon_fire() -> void:
	# El hijo `_ready()` corre antes que el del padre, así que el grupo "player"
	# puede aún no estar listo: primero el padre directo, luego el grupo.
	var player: Node = get_parent()
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return
	var wc: Node = player.get_node_or_null("WeaponController")
	if wc == null or not is_instance_valid(wc):
		var found: Array[Node] = player.find_children("*", "WeaponController", true, false)
		if not found.is_empty():
			wc = found[0]
	if wc == null or not is_instance_valid(wc):
		return
	if not wc.has_signal("fire_requested"):
		return
	var cb := Callable(self, "_on_fire_requested")
	if wc.is_connected("fire_requested", cb):
		return
	wc.connect("fire_requested", cb)
	_weapon_controller = wc

func _disconnect_weapon_fire() -> void:
	if _weapon_controller == null or not is_instance_valid(_weapon_controller):
		return
	var cb := Callable(self, "_on_fire_requested")
	if _weapon_controller.has_signal("fire_requested") \
			and _weapon_controller.is_connected("fire_requested", cb):
		_weapon_controller.disconnect("fire_requested", cb)
	_weapon_controller = null

func _connect_player_damage() -> void:
	if not EventBus.has_signal("player_damaged"):
		return
	var cb := Callable(self, "_on_player_damaged")
	if EventBus.is_connected("player_damaged", cb):
		return
	EventBus.connect("player_damaged", cb)

func _disconnect_player_damage() -> void:
	if not EventBus.has_signal("player_damaged"):
		return
	var cb := Callable(self, "_on_player_damaged")
	if EventBus.is_connected("player_damaged", cb):
		EventBus.disconnect("player_damaged", cb)

# --- Handlers ------------------------------------------------------------------

func _on_fire_requested(weapon: Object, from: Vector2, to: Vector2) -> void:
	if not is_instance_valid(self):
		return
	var aim: Vector2 = to - from
	# Intensidad según el arma: magnitud de shake + retroceso acumulado.
	var intensity: float = 6.0
	if weapon != null and is_instance_valid(weapon):
		var mag: Variant = weapon.get("camera_shake_magnitude")
		if mag != null:
			intensity = float(mag)
		var recoil: Variant = weapon.get("current_recoil")
		if recoil != null:
			intensity += float(recoil) * 12.0
	shake(aim, intensity)
	punch(clampf(intensity / 140.0, 0.01, punch_amount))

func _on_player_damaged(amount: float, _source: Node) -> void:
	if not is_instance_valid(self):
		return
	# Sin dirección de impacto: shake() elige un ángulo aleatorio defendible.
	shake(Vector2.ZERO, clampf(6.0 + amount * 0.35, 6.0, shake_max_offset))
