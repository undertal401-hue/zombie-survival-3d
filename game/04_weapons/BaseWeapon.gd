class_name BaseWeapon


extends Node3D
## Base de todas las armas (composicion).
##
## Gestiona municion, equipado, recarga y el evento de disparo. Las subclases
## implementan el comportamiento concreto (hitscan, melee, proyectil).
## Accesible globalmente via `BaseWeapon` (class_name).

signal fired(weapon: BaseWeapon)
signal reload_started(weapon: BaseWeapon, duration: float)
signal reload_finished(weapon: BaseWeapon)
signal ammo_changed(weapon: BaseWeapon, magazine: int, reserve: int)
signal empty(weapon: BaseWeapon)

@export var data: WeaponData = null

var magazine: int = 0
var reserve_ammo: int = 0
var is_equipped: bool = false
var is_reloading: bool = false
var total_shots_fired: int = 0

var _owner: Node3D = null
var _reload_system: ReloadSystem


func _ready() -> void:
	if data == null:
		data = WeaponData.new()
	magazine = data.magazine
	reserve_ammo = data.reserve_max
	_reload_system = ReloadSystem.new()
	_reload_system.name = "ReloadSystem"
	_reload_system.weapon = self
	add_child(_reload_system)


## Configura el duenio del arma (jugador).
## @param owner_node: nodo que la sostiene.
func set_wielder(owner_node: Node3D) -> void:
	_owner = owner_node


## Equipa/desequipa el arma (visibilidad y audio).
## @param equipped: estado.
func set_equipped(equipped: bool) -> void:
	is_equipped = equipped
	visible = equipped
	if equipped:
		EventBus.weapon_equipped.emit(self)
	else:
		EventBus.weapon_unequipped.emit(self)


## True si puede disparar/golpear ahora.
func can_fire() -> bool:
	if is_reloading or data == null:
		return false
	return magazine > 0 and not _reload_system.is_busy()


## Punto de entrada de disparo. Las subclases lo implementan.
func trigger_pulled() -> void:
	if not can_fire():
		if magazine <= 0:
			EventBus.weapon_empty_clicked.emit(self)
			empty.emit(self)
		return
	fire()


## Libera el gatillo (para armas semiautomáticas y de carga).
func trigger_released() -> void:
	pass


## Dispara el arma. Solo valida municion; el efecto lo hace la subclase.
func fire() -> void:
	if data == null or magazine <= 0:
		EventBus.weapon_empty_clicked.emit(self)
		return
	magazine -= 1
	total_shots_fired += 1
	EventBus.ammo_changed.emit(self, magazine, reserve_ammo)
	ammo_changed.emit(self, magazine, reserve_ammo)
	fired.emit(self)
	if magazine == 0:
		empty.emit(self)


## Inicia la recarga si hay reserva.
## @return true si se inicio.
func reload() -> bool:
	if is_reloading or reserve_ammo <= 0 or magazine >= data.magazine:
		return false
	_reload_system.start_reload(data.reload_time)
	return true


## Anade municion de reserva.
## @param amount: cantidad.
## @return cantidad realmente anadida.
func add_reserve_ammo(amount: int) -> int:
	if amount <= 0 or data == null:
		return 0
	var space: int = data.reserve_max - reserve_ammo
	var added: int = mini(amount, maxi(space, 0))
	reserve_ammo += added
	EventBus.ammo_changed.emit(self, magazine, reserve_ammo)
	return added


## Completa la recarga (llamado por ReloadSystem).
func finish_reload() -> void:
	if data == null:
		return
	var needed: int = data.magazine - magazine
	var taken: int = mini(needed, reserve_ammo)
	magazine += taken
	reserve_ammo -= taken
	is_reloading = false
	EventBus.weapon_reload_finished.emit(self)
	EventBus.ammo_changed.emit(self, magazine, reserve_ammo)
	reload_finished.emit(self)


## Marca recarga en curso (llamado por ReloadSystem).
func mark_reloading(duration: float) -> void:
	is_reloading = true
	EventBus.weapon_reload_started.emit(self, duration)
	reload_started.emit(self, duration)


## Progreso de recarga 0..1.
func reload_progress() -> float:
	return _reload_system.progress() if _reload_system != null else 0.0


## Duenio del arma.
func get_wielder() -> Node3D:
	return _owner


## Punto de origen del disparo ( boca del arma ).
func get_muzzle_position() -> Vector3:
	return global_position + Vector3.UP * 0.2


## Direccion de disparo desde la camara o del duenio.
func get_fire_direction() -> Vector3:
	if _owner is Player and (_owner as Player).camera_rig != null:
		return (_owner as Player).camera_rig.get_aim_direction()
	return -global_transform.basis.z
