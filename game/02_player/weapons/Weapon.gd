extends Resource
class_name Weapon

## =============================================================================
## WEAPON RESOURCE BASE - Sistema de armas data-driven
## =============================================================================
## Todas las armas son Resources, editables en Inspector, instanciables múltiples veces
## Sin código duplicado: comportamiento en Weapon, datos en cada Resource
## =============================================================================

## --- Identidad ---
@export var weapon_name: String = "Unnamed Weapon"
@export var description: String = ""
@export var icon: Texture2D

## --- Categoría y Slots ---
enum Category { MELEE, PISTOL, SHOTGUN, RIFLE, HEAVY, SPECIAL, THROWABLE, TOOL }
@export var category: Category = Category.PISTOL
@export var slot_index: int = 1  # 1-6 quick slots

## --- Daño y Balística ---
@export var base_damage: float = 10.0
@export var damage_falloff_start: float = 0.0      # 0 = sin falloff
@export var damage_falloff_end: float = 100.0      # distancia donde damage = min_damage
@export var min_damage: float = 1.0
@export var headshot_multiplier: float = 2.0
@export var limb_multiplier: float = 0.7

@export var range: float = 500.0                   # hitscan range
@export var spread: float = 0.0                    # radianes (0 = perfecto)
@export var spread_per_shot: float = 0.0           # bloom acumulativo
@export var max_spread: float = 0.5
@export var spread_recovery: float = 5.0           # por segundo

## --- Retroceso ---
## El bloom ensancha el cono; el retroceso desplaza el punto de impacto en una
## dirección fija. Juntos hacen que una ráfaga se abra visiblemente hacia arriba.
@export var recoil_per_shot: float = 0.0           # radianes de kick por disparo
@export var max_recoil: float = 0.0                # tope de kick acumulado
@export var recoil_recovery: float = 2.0           # radianes/segundo
@export var recoil_camera_kick: float = 1.0        # intensidad del kick de cámara

## Aguante necesario por disparo. El melee usa Player.MELEE_COST.
@export var stamina_cost: float = 3.0

## --- Condición ---
## La condición NO se guarda aquí: Inventory es la única fuente de verdad.
## Si no se especifica id, se usa el nombre del arma como clave de inventario.
@export var condition_item_id: String = ""
## Desgaste por disparo. Con 0.004 hacen falta 250 balas para romper el arma.
@export var wear_per_shot: float = 0.004

var condition: float:
	get: return _read_condition()

## --- Fire Rate ---
@export var fire_rate: float = 300.0               # RPM (rounds per minute)
@export var burst_count: int = 1                   # 1 = semi, >1 = burst
@export var burst_delay: float = 0.05              # entre tiros del burst
@export var is_automatic: bool = false             # hold to fire

## --- Movimiento ---
## Multiplicador aplicado a caminar y correr mientras esta arma está equipada.
@export var move_speed_multiplier: float = 1.0

## --- Ammo ---
@export var ammo_type: String = "pistol_ammo"      # key en Inventory
@export var magazine_size: int = 12
@export var ammo_per_shot: int = 1
## Perdigones por disparo (escopeta): cada uno es un raycast propio con su
## dispersión, pero el cargador paga una sola munición por gatillazo.
@export var pellets_per_shot: int = 1
@export var start_with_full_mag: bool = true

## --- Recarga ---
@export var reload_time: float = 2.0               # segundos
@export var reload_time_empty: float = 2.5         # extra si cargador vacío
@export var reload_shell_by_shell: bool = false    # escopeta: uno a uno
@export var shell_reload_time: float = 0.5         # por cartucho
@export var can_reload_cancel: bool = true         # interruptible
@export var chambered_round: bool = true           # +1 en recámara

## --- Melee Specific ---
@export var melee_range: float = 2.0
@export var melee_arc: float = PI / 3              # 60°
@export var melee_knockback: float = 200.0
@export var melee_cooldown: float = 0.6
@export var melee_hit_stop: float = 0.08           # duración del shake de cámara al golpear (no hit-stop global)
## Capacidad data-driven: una herramienta puede golpear y además talar recursos.
@export var can_chop_trees: bool = false

## --- Efectos Visuales/Sonoros ---
@export var muzzle_flash: PackedScene
@export var muzzle_flash_offset: Vector2 = Vector2(12, 0)
@export var muzzle_flash_scale: float = 1.0
@export var shell_casing: PackedScene
@export var shell_eject_offset: Vector2 = Vector2(-4, -2)
@export var shell_eject_force: float = 150.0
@export var tracer: PackedScene
@export var tracer_chance: float = 0.2
@export var impact_effects: Array[PackedScene]     # por superficie
@export var hit_sound: AudioStream
@export var fire_sound: AudioStream
@export var dry_fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var reload_empty_sound: AudioStream
@export var camera_shake_magnitude: float = 2.0
@export var camera_shake_duration: float = 0.1

## --- Avanzado ---
@export var penetration: int = 0                   # paredes atravesadas
@export var ricochet_chance: float = 0.0
@export var projectile_scene: PackedScene          # si no hitscan
@export var projectile_speed: float = 1000.0
@export var projectile_gravity: float = 0.0
@export var explosive_radius: float = 0.0
@export var explosive_damage_falloff: float = 0.5

## --- Estado Runtime (no serializado) ---
var current_ammo: int = 0
var ammo_in_chamber: int = 0
var is_reloading: bool = false
var reload_timer: float = 0.0
var current_spread: float = 0.0
var current_recoil: float = 0.0
var last_shot_time: float = 0.0
var burst_shots_fired: int = 0
## Cartuchos ya sacados del inventario por una recarga cartucho a cartucho.
## Si la recarga se cancela hay que devolverlos (y quitarlos del cargador).
var _reload_consumed: int = 0

func _init() -> void:
	_initialize_state()

func _initialize_state() -> void:
	current_ammo = magazine_size if start_with_full_mag else 0
	ammo_in_chamber = 1 if (chambered_round and current_ammo > 0) else 0
	if chambered_round and current_ammo > 0:
		current_ammo -= 1
	is_reloading = false
	reload_timer = 0.0
	current_spread = 0.0
	current_recoil = 0.0
	last_shot_time = 0.0
	burst_shots_fired = 0
	_reload_consumed = 0

## Clave de inventario que posee la condición de este arma.
func _condition_key() -> String:
	var key: String = condition_item_id if condition_item_id != "" else weapon_name
	return key.strip_edges()

func _read_condition() -> float:
	var key: String = _condition_key()
	if key == "":
		return 1.0
	# get_condition devuelve 1.0 para ids desconocidos: arma nueva por defecto.
	return Inventory.get_condition(key)

## API delgada exigida por QA: la condición nunca se duplica en el Resource.
func is_broken() -> bool:
	return condition <= 0.0

## Restaura la condición en Inventory. Si el arma no está como objeto se crea
## una unidad silenciosa para poder reparar; el estado sigue viviendo allí.
func repair(amount: float = 1.0) -> void:
	var key: String = _condition_key()
	if key == "" or amount <= 0.0:
		return
	if Inventory.count(key) <= 0:
		if Inventory.get_method_argument_count("add_item") >= 3:
			Inventory.add_item(key, 1, true)
		else:
			Inventory.add_item(key, 1)
	Inventory.repair_item(key, amount)

func _apply_wear(amount: float) -> void:
	var key: String = _condition_key()
	if key == "" or amount <= 0.0 or Inventory.count(key) <= 0:
		return
	Inventory.degrade_item(key, amount)

func get_total_ammo() -> int:
	return current_ammo + ammo_in_chamber

## Capacidad total del arma. magazine_size incluye la bala de la recámara:
## con 12 balas cargadas quedan 11 en el cargador y 1 en la recámara.
func get_max_ammo() -> int:
	return magazine_size

func can_fire() -> bool:
	if is_reloading:
		return false
	# Un arma rota no dispara hasta repararla (la condición vive en Inventory).
	if is_broken():
		return false
	# La recámara se realimenta desde el cargador: lo que importa es el total.
	if get_total_ammo() < maxi(ammo_per_shot, 1):
		return false
	if burst_shots_fired >= burst_count:
		return false
	return true

func get_fire_interval() -> float:
	return 60.0 / fire_rate

func apply_spread() -> void:
	current_spread = minf(current_spread + maxf(spread_per_shot, 0.0), maxf(max_spread, 0.0))
	current_recoil = minf(current_recoil + maxf(recoil_per_shot, 0.0), maxf(max_recoil, 0.0))
	# Desgaste real: el arma se gasta al usarla, sin duplicar el estado aquí.
	_apply_wear(wear_per_shot)

func recover_spread(delta: float) -> void:
	current_spread = maxf(current_spread - maxf(spread_recovery, 0.0) * delta, 0.0)
	current_recoil = maxf(current_recoil - maxf(recoil_recovery, 0.0) * delta, 0.0)

func get_effective_spread() -> float:
	return spread + current_spread

## Sesgo direccional acumulado (radianes). Siempre positivo: cada disparo de
## una ráfaga empuja el impacto hacia el mismo lado, como un retroceso real.
func get_recoil_angle() -> float:
	return current_recoil

func get_stamina_cost() -> float:
	return maxf(stamina_cost, 0.0)

func consume_ammo() -> void:
	# Disparar gasta munición de verdad: si la recámara está vacía se alimenta
	# con una bala del cargador, y el cargador baja con cada disparo.
	var to_consume: int = maxi(ammo_per_shot, 1)
	while to_consume > 0:
		if ammo_in_chamber <= 0:
			if current_ammo <= 0:
				break
			current_ammo -= 1
			ammo_in_chamber = 1
		var used: int = mini(ammo_in_chamber, to_consume)
		ammo_in_chamber -= used
		to_consume -= used
	# El contador de ráfaga lo lleva WeaponController (un disparo = una cuenta).

func start_reload(force_empty: bool = false) -> bool:
	if is_reloading:
		return false
	if get_total_ammo() >= get_max_ammo():
		return false  # ya lleno: no gastar balas del inventario
	
	is_reloading = true
	burst_shots_fired = 0
	_reload_consumed = 0
	if reload_shell_by_shell:
		# Escopeta: un cartucho cada intervalo, con devolución si se cancela.
		reload_timer = maxf(shell_reload_time, 0.01)
		return true
	var empty_bonus: float = 0.0
	if force_empty or ammo_in_chamber <= 0:
		empty_bonus = reload_time_empty - reload_time
	reload_timer = reload_time + empty_bonus
	return true

func update_reload(delta: float) -> bool:
	if not is_reloading:
		return false
	
	reload_timer -= delta
	if reload_shell_by_shell:
		# Un cartucho por intervalo: se descuenta del inventario al insertarlo,
		# no al terminar, para que cancelar pueda devolverlo con exactitud.
		while reload_timer <= 0.0 and is_reloading:
			if get_total_ammo() >= get_max_ammo() or ammo_type == "" or Inventory.count(ammo_type) <= 0:
				finish_reload()
				return true
			Inventory.remove_item(ammo_type, 1)
			_reload_consumed += 1
			if chambered_round and ammo_in_chamber <= 0:
				ammo_in_chamber = 1
			else:
				current_ammo = mini(current_ammo + 1, maxi(magazine_size - ammo_in_chamber, 0))
			reload_timer += maxf(shell_reload_time, 0.01)
		return false
	if reload_timer <= 0.0:
		finish_reload()
		return true
	return false

func finish_reload() -> void:
	# En armas sin recámara la bala "lista" vuelve al cargador al recargar.
	if not chambered_round and ammo_in_chamber > 0:
		current_ammo += ammo_in_chamber
		ammo_in_chamber = 0
	
	if not reload_shell_by_shell:
		# Solo se pide al inventario lo que realmente cabe: ni sobrecarga ni
		# consumo al recargar un arma que ya está llena.
		var needed: int = maxi(get_max_ammo() - get_total_ammo(), 0)
		var available: int = Inventory.count(ammo_type) if ammo_type != "" else 0
		var to_load: int = mini(needed, available)
		
		if to_load > 0 and ammo_type != "":
			Inventory.remove_item(ammo_type, to_load)
		
		# Recámara primero; el resto al cargador sin superar su capacidad.
		if chambered_round and ammo_in_chamber <= 0 and to_load > 0:
			ammo_in_chamber = 1
			to_load -= 1
		current_ammo = mini(current_ammo + to_load, magazine_size - ammo_in_chamber)
		if not chambered_round:
			ammo_in_chamber = 0
	# En mode cartucho a cartucho el inventario ya se descontó en update_reload().
	_reload_consumed = 0
	
	is_reloading = false
	reload_timer = 0.0
	burst_shots_fired = 0

## Cancela una recarga. `force` se usa al subir a vehículo: ningún arma debe
## seguir recargando en segundo plano mientras se conduce.
func cancel_reload(force: bool = false) -> void:
	if not is_reloading:
		return
	if not can_reload_cancel and not force:
		return
	# Devolver los cartuchos ya insertados y sacarlos del arma: sin esto una
	# recarga interrumpida duplicaría munición (o la perdería silenciosamente).
	if _reload_consumed > 0 and ammo_type != "":
		var pending: int = mini(_reload_consumed, get_total_ammo())
		var returned: int = 0
		while pending > 0:
			if ammo_in_chamber > 0:
				ammo_in_chamber -= 1
			elif current_ammo > 0:
				current_ammo -= 1
			else:
				break
			pending -= 1
			returned += 1
		if returned > 0:
			Inventory.add_item(ammo_type, returned)
	_reload_consumed = 0
	is_reloading = false
	reload_timer = 0.0
	burst_shots_fired = 0

func get_reload_progress() -> float:
	if not is_reloading:
		return 1.0
	if reload_shell_by_shell:
		return clampf(1.0 - (reload_timer / maxf(shell_reload_time, 0.01)), 0.0, 1.0)
	var extra: float = 0.0
	if ammo_in_chamber <= 0:
		extra = reload_time_empty - reload_time
	return 1.0 - (reload_timer / (reload_time + extra))

## --- Serialización para save/load ---
func get_state_dict() -> Dictionary:
	return {
		"current_ammo": current_ammo,
		"ammo_in_chamber": ammo_in_chamber,
		"is_reloading": is_reloading,
		"reload_timer": reload_timer,
		"current_spread": current_spread,
		"current_recoil": current_recoil,
		"burst_shots_fired": burst_shots_fired,
		"reload_consumed": _reload_consumed,
	}

func load_state_dict(data: Dictionary) -> void:
	current_ammo = data.get("current_ammo", current_ammo)
	ammo_in_chamber = data.get("ammo_in_chamber", ammo_in_chamber)
	is_reloading = data.get("is_reloading", is_reloading)
	reload_timer = data.get("reload_timer", reload_timer)
	current_spread = data.get("current_spread", current_spread)
	current_recoil = data.get("current_recoil", current_recoil)
	burst_shots_fired = data.get("burst_shots_fired", burst_shots_fired)
	_reload_consumed = data.get("reload_consumed", _reload_consumed)