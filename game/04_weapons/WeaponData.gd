class_name WeaponData

extends Resource
## Definicion data-driven de un arma.
##
## Las 14+ armas comparten esta recurso; solo cambian los valores. Nunca se
## hardcodea dano, cadencia o municion en los scripts de comportamiento.
## Accesible globalmente via `WeaponData` (class_name).

enum SlotType {
	PRIMARY,
	SECONDARY,
	MELEE,
}

enum FireMode {
	SEMI,
	AUTO,
	PUMP,
	BOLT,
	CHARGE,
	PROJECTILE,
}

enum AmmoType {
	NONE,
	LIGHT,
	HEAVY,
	SHELLS,
	BOLTS,
	ROCKETS,
	EXPERIMENTAL,
}

@export_group("Identity")
@export var weapon_id: StringName = &"weapon"
@export var display_name: String = "Arma"
@export var description: String = ""
@export var slot_type: SlotType = SlotType.PRIMARY
@export var fire_mode: FireMode = FireMode.SEMI
@export var ammo_type: AmmoType = AmmoType.LIGHT

@export_group("Damage")
@export var damage: float = 20.0
@export var headshot_multiplier: float = 2.0
@export var damage_falloff_start: float = 20.0
@export var damage_falloff_end: float = 60.0
@export var damage_falloff_min: float = 0.4
@export var infection: float = 0.0
@export var knockback: float = 4.0

@export_group("Handling")
@export var fire_rate: float = 4.0
@export var magazine: int = 12
@export var reserve_max: int = 120
@export var reload_time: float = 1.6
@export var spread_degrees: float = 1.2
@export var ads_spread_degrees: float = 0.3
@export var range: float = 80.0
@export var pellets: int = 1
@export var recoil: float = 0.6
@export var ads_fov: float = 50.0

@export_group("Projectile")
@export var projectile_scene: String = ""
@export var projectile_speed: float = 0.0
@export var projectile_gravity: float = 0.0
@export var is_hitscan: bool = true

@export_group("Melee")
@export var melee_range: float = 2.2
@export var melee_arc_degrees: float = 100.0
@export var melee_charge_time: float = 0.6
@export var melee_charge_multiplier: float = 2.0

@export_group("Economy")
@export var rarity_id: StringName = &"common"
@export var price: int = 100
@export var unlock_wave: int = 1
@export var is_experimental: bool = false


## True si el arma usa proyectil en vez de hitscan.
func uses_projectile() -> bool:
	return not is_hitscan or fire_mode == FireMode.PROJECTILE


## Cadencia en segundos entre disparos.
func shot_interval() -> float:
	return 1.0 / maxf(fire_rate, 0.01)


## Spread actual segun si se apunta.
func spread_for(ads: bool) -> float:
	return ads_spread_degrees if ads else spread_degrees


## Dano con falloff de distancia.
## @param distance: distancia al impacto.
## @return dano ajustado.
func damage_at_distance(distance: float) -> float:
	if distance <= damage_falloff_start:
		return damage
	if distance >= damage_falloff_end:
		return damage * damage_falloff_min
	var t: float = (distance - damage_falloff_start) / (damage_falloff_end - damage_falloff_start)
	return lerpf(damage, damage * damage_falloff_min, t)


## Tabla de las 14+ armas del juego.
static func catalog() -> Array[WeaponData]:
	var list: Array[WeaponData] = []
	list.append(_make_pistol())
	list.append(_make_revolver())
	list.append(_make_shotgun())
	list.append(_make_assault_rifle())
	list.append(_make_smg())
	list.append(_make_sniper())
	list.append(_make_crossbow())
	list.append(_make_grenade_launcher())
	list.append(_make_minigun())
	list.append(_make_experimental())
	list.append(_make_knife())
	list.append(_make_machete())
	list.append(_make_fire_axe())
	list.append(_make_hammer())
	list.append(_make_katana())
	list.append(_make_nail_bat())
	return list


static func _base(id: StringName, display: String, slot: SlotType, mode: FireMode,
		ammo: AmmoType) -> WeaponData:
	var data := WeaponData.new()
	data.weapon_id = id
	data.display_name = display
	data.slot_type = slot
	data.fire_mode = mode
	data.ammo_type = ammo
	return data


## Fabricas publicas por tipo (usadas por las clases de arma concretas).
static func pistol() -> WeaponData: return _make_pistol()
static func revolver() -> WeaponData: return _make_revolver()
static func shotgun() -> WeaponData: return _make_shotgun()
static func assault_rifle() -> WeaponData: return _make_assault_rifle()
static func smg() -> WeaponData: return _make_smg()
static func sniper() -> WeaponData: return _make_sniper()
static func crossbow() -> WeaponData: return _make_crossbow()
static func grenade_launcher() -> WeaponData: return _make_grenade_launcher()
static func minigun() -> WeaponData: return _make_minigun()
static func experimental() -> WeaponData: return _make_experimental()
static func knife() -> WeaponData: return _make_knife()
static func machete() -> WeaponData: return _make_machete()
static func fire_axe() -> WeaponData: return _make_fire_axe()
static func hammer() -> WeaponData: return _make_hammer()
static func katana() -> WeaponData: return _make_katana()
static func nail_bat() -> WeaponData: return _make_nail_bat()


static func _make_pistol() -> WeaponData:
	var d := _base(&"pistol_9mm", "Pistola 9mm", SlotType.SECONDARY, FireMode.SEMI, AmmoType.LIGHT)
	d.damage = 22.0; d.fire_rate = 5.0; d.magazine = 12; d.reserve_max = 120
	d.reload_time = 1.3; d.spread_degrees = 1.4; d.range = 50.0
	d.price = 0; d.unlock_wave = 1; d.rarity_id = &"common"
	return d


static func _make_revolver() -> WeaponData:
	var d := _base(&"revolver_357", "Revólver .357", SlotType.SECONDARY, FireMode.SEMI, AmmoType.HEAVY)
	d.damage = 55.0; d.fire_rate = 1.8; d.magazine = 6; d.reserve_max = 60
	d.reload_time = 2.2; d.spread_degrees = 1.0; d.range = 70.0; d.knockback = 7.0
	d.price = 250; d.unlock_wave = 2; d.rarity_id = &"uncommon"
	return d


static func _make_shotgun() -> WeaponData:
	var d := _base(&"shotgun_pump", "Escopeta pump", SlotType.PRIMARY, FireMode.PUMP, AmmoType.SHELLS)
	d.damage = 12.0; d.pellets = 8; d.fire_rate = 1.1; d.magazine = 6
	d.reserve_max = 48; d.reload_time = 2.6; d.spread_degrees = 5.0
	d.damage_falloff_start = 8.0; d.damage_falloff_end = 26.0; d.damage_falloff_min = 0.2
	d.knockback = 9.0; d.price = 400; d.unlock_wave = 3; d.rarity_id = &"uncommon"
	return d


static func _make_assault_rifle() -> WeaponData:
	var d := _base(&"assault_rifle", "Rifle de asalto", SlotType.PRIMARY, FireMode.AUTO, AmmoType.LIGHT)
	d.damage = 26.0; d.fire_rate = 8.0; d.magazine = 30; d.reserve_max = 240
	d.reload_time = 2.0; d.spread_degrees = 2.0; d.range = 90.0
	d.price = 700; d.unlock_wave = 4; d.rarity_id = &"rare"
	return d


static func _make_smg() -> WeaponData:
	var d := _base(&"smg", "SMG", SlotType.PRIMARY, FireMode.AUTO, AmmoType.LIGHT)
	d.damage = 16.0; d.fire_rate = 13.0; d.magazine = 40; d.reserve_max = 320
	d.reload_time = 1.7; d.spread_degrees = 2.8; d.range = 45.0
	d.price = 550; d.unlock_wave = 4; d.rarity_id = &"uncommon"
	return d


static func _make_sniper() -> WeaponData:
	var d := _base(&"sniper_rifle", "Rifle francotirador", SlotType.PRIMARY, FireMode.BOLT, AmmoType.HEAVY)
	d.damage = 120.0; d.fire_rate = 0.8; d.magazine = 5; d.reserve_max = 40
	d.reload_time = 3.0; d.spread_degrees = 0.2; d.ads_spread_degrees = 0.02
	d.range = 200.0; d.headshot_multiplier = 2.5; d.knockback = 8.0
	d.price = 900; d.unlock_wave = 5; d.rarity_id = &"rare"
	return d


static func _make_crossbow() -> WeaponData:
	var d := _base(&"crossbow", "Ballesta", SlotType.PRIMARY, FireMode.PROJECTILE, AmmoType.BOLTS)
	d.damage = 70.0; d.fire_rate = 0.9; d.magazine = 1; d.reserve_max = 24
	d.reload_time = 2.4; d.range = 80.0; d.is_hitscan = false
	d.projectile_scene = "res://10_effects/BoltProjectile.tscn"
	d.projectile_speed = 55.0; d.projectile_gravity = 6.0
	d.price = 600; d.unlock_wave = 6; d.rarity_id = &"rare"
	return d


static func _make_grenade_launcher() -> WeaponData:
	var d := _base(&"grenade_launcher", "Lanzagranadas", SlotType.PRIMARY, FireMode.PROJECTILE, AmmoType.ROCKETS)
	d.damage = 90.0; d.fire_rate = 1.0; d.magazine = 4; d.reserve_max = 24
	d.reload_time = 3.0; d.range = 60.0; d.is_hitscan = false
	d.projectile_scene = "res://10_effects/GrenadeProjectile.tscn"
	d.projectile_speed = 22.0; d.projectile_gravity = 9.0
	d.price = 1200; d.unlock_wave = 7; d.rarity_id = &"epic"
	return d


static func _make_minigun() -> WeaponData:
	var d := _base(&"minigun", "Minigun", SlotType.PRIMARY, FireMode.AUTO, AmmoType.HEAVY)
	d.damage = 14.0; d.fire_rate = 20.0; d.magazine = 200; d.reserve_max = 600
	d.reload_time = 5.0; d.spread_degrees = 4.5; d.range = 70.0
	d.recoil = 0.9; d.price = 2500; d.unlock_wave = 9; d.rarity_id = &"legendary"
	return d


static func _make_experimental() -> WeaponData:
	var d := _base(&"experimental", "Arma experimental", SlotType.PRIMARY, FireMode.CHARGE, AmmoType.EXPERIMENTAL)
	d.damage = 200.0; d.fire_rate = 0.4; d.magazine = 3; d.reserve_max = 12
	d.reload_time = 4.0; d.range = 120.0; d.is_hitscan = false
	d.projectile_scene = "res://10_effects/PlasmaProjectile.tscn"
	d.projectile_speed = 40.0; d.projectile_gravity = 0.0
	d.is_experimental = true; d.price = 5000; d.unlock_wave = 10
	d.rarity_id = &"legendary"
	return d


static func _make_knife() -> WeaponData:
	var d := _base(&"knife", "Cuchillo táctico", SlotType.MELEE, FireMode.SEMI, AmmoType.NONE)
	d.damage = 25.0; d.fire_rate = 3.0; d.melee_range = 1.8
	d.price = 0; d.unlock_wave = 1; d.rarity_id = &"common"
	return d


static func _make_machete() -> WeaponData:
	var d := _base(&"machete", "Machete", SlotType.MELEE, FireMode.SEMI, AmmoType.NONE)
	d.damage = 40.0; d.fire_rate = 2.0; d.melee_range = 2.2; d.knockback = 6.0
	d.price = 150; d.unlock_wave = 1; d.rarity_id = &"common"
	return d


static func _make_fire_axe() -> WeaponData:
	var d := _base(&"fire_axe", "Hacha de bombero", SlotType.MELEE, FireMode.SEMI, AmmoType.NONE)
	d.damage = 65.0; d.fire_rate = 1.2; d.melee_range = 2.4; d.knockback = 10.0
	d.price = 350; d.unlock_wave = 2; d.rarity_id = &"uncommon"
	return d


static func _make_hammer() -> WeaponData:
	var d := _base(&"carpenter_hammer", "Martillo de carpintero", SlotType.MELEE, FireMode.SEMI, AmmoType.NONE)
	d.damage = 50.0; d.fire_rate = 1.5; d.melee_range = 2.0; d.knockback = 14.0
	d.price = 200; d.unlock_wave = 1; d.rarity_id = &"common"
	return d


static func _make_katana() -> WeaponData:
	var d := _base(&"katana", "Katana", SlotType.MELEE, FireMode.AUTO, AmmoType.NONE)
	d.damage = 45.0; d.fire_rate = 4.0; d.melee_range = 2.6; d.knockback = 5.0
	d.price = 800; d.unlock_wave = 6; d.rarity_id = &"rare"
	return d


static func _make_nail_bat() -> WeaponData:
	var d := _base(&"nail_bat", "Bate con clavos", SlotType.MELEE, FireMode.SEMI, AmmoType.NONE)
	d.damage = 35.0; d.fire_rate = 2.2; d.melee_range = 2.2; d.knockback = 12.0
	d.infection = 5.0; d.price = 300; d.unlock_wave = 3; d.rarity_id = &"uncommon"
	return d
