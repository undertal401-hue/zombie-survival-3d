extends Node

## Informe legible del contrato de calidad r1 (5 sistemas nuevos).
## No instancia Main ni ejecuta la batería: solo inspecciona la API disponible.
## Cada sistema se reporta como OK / PARTIAL / PENDING; nunca como FAIL.
## Uso: godot --headless --path . res://10_review/MechanicsAudit.tscn

const SYSTEMS: Array[String] = [
	"game_state", "crafting", "weapon_condition", "hordes", "vehicle_fuel_damage"
]

func _ready() -> void:
	await get_tree().process_frame
	var audit: Dictionary = _run_audit()
	print("=== MECHANICS AUDIT v1 ===")
	for key in SYSTEMS:
		var detail: String = String(audit.get(key + "_detail", "sin datos"))
		var ok: bool = bool(audit.get(key, false))
		print("[%s] %-22s %s" % ["OK" if ok else "PENDING", key, detail])
	print("AUDIT total=%d/%d" % [int(audit.get("active", 0)), SYSTEMS.size()])
	print("=== AUDIT END ===")
	get_tree().quit(0)

func _has_prop(obj: Object, prop: String) -> bool:
	if obj == null:
		return false
	for entry in obj.get_property_list():
		if String(entry.get("name", "")) == prop:
			return true
	return false

func _method_names(obj: Object, candidates: Array) -> Array[String]:
	var found: Array[String] = []
	if obj == null:
		return found
	for candidate in candidates:
		if obj.has_method(String(candidate)):
			found.append(String(candidate))
	return found

func _run_audit() -> Dictionary:
	var audit: Dictionary = {}

	# 1. GameState autoload — compatible (get_state/load_state) O canónico
	# (phase/stats/rng) según el contrato r1bis de core.
	var gs: Node = get_node_or_null("/root/GameState")
	var gs_methods: Array[String] = _method_names(gs, ["reset", "new_game", "get_state", "load_state",
		"get_wave", "get_difficulty", "phase", "set_phase", "difficulty", "set_difficulty",
		"rng", "stats", "record", "register_actor", "unregister_actor"])
	var gs_compat: bool = gs != null and gs.has_method("get_state") and gs.has_method("load_state")
	var gs_canon: bool = gs != null and gs.has_method("phase") and gs.has_method("stats") and gs.has_method("rng")
	audit["game_state"] = gs_compat or gs_canon
	audit["game_state_detail"] = "autoload=%s compat=%s canon=%s metodos=%s" % [
		str(gs != null), str(gs_compat), str(gs_canon), str(gs_methods)
	]

	# 2. Crafting — Inventory.craft() o /root/Crafting con recetas.
	var inv: Node = get_node_or_null("/root/Inventory")
	var craft_node: Node = get_node_or_null("/root/Crafting")
	var inv_methods: Array[String] = _method_names(inv, ["craft", "craft_item"])
	var craft_methods: Array[String] = _method_names(craft_node, ["craft", "get_recipes"])
	audit["crafting"] = not inv_methods.is_empty() or not craft_methods.is_empty()
	audit["crafting_detail"] = "Inventory=%s Crafting=%s" % [str(inv_methods), str(craft_methods)]

	# 3. Condición de armas — prop y métodos en Weapon.
	var player: Node = get_tree().get_first_node_in_group("player")
	var wc: Node = player.get_node_or_null("WeaponController") if player != null else null
	var props: Array[String] = []
	var methods: Array[String] = []
	if wc != null and wc.has_method("get_weapon_in_slot"):
		for slot in range(5):
			var weapon: Variant = wc.call("get_weapon_in_slot", slot)
			if weapon == null:
				continue
			for prop in ["condition", "durability", "wear"]:
				if _has_prop(weapon, prop) and not props.has(String(prop)):
					props.append(String(prop))
			for method_name in _method_names(weapon, ["is_broken", "repair", "repair_weapon"]):
				if not methods.has(method_name):
					methods.append(method_name)
	audit["weapon_condition"] = not props.is_empty() and not methods.is_empty()
	audit["weapon_condition_detail"] = "props=%s metodos=%s" % [str(props), str(methods)]

	# 4. Hordas — WaveManager | HordeManager | WorldDirector en Main,
	# señal wave_started O horde_started.
	var scene: Node = get_tree().current_scene
	var horde: Node = scene.get_node_or_null("WaveManager") if scene != null else null
	if horde == null and scene != null:
		horde = scene.get_node_or_null("HordeManager")
	if horde == null and scene != null:
		horde = scene.get_node_or_null("WorldDirector")
	var wave_methods: Array[String] = _method_names(horde, ["start_wave", "get_wave", "is_horde_active", "horde_size"])
	var wave_signal: bool = EventBus.has_signal("wave_started") or EventBus.has_signal("horde_started")
	audit["hordes"] = wave_signal and wave_methods.has("start_wave")
	audit["hordes_detail"] = "wave_signal=%s horde_signal=%s manager=%s metodos=%s" % [
		str(EventBus.has_signal("wave_started")), str(EventBus.has_signal("horde_started")),
		str(horde != null), str(wave_methods)
	]

	# 5. Vehículo — combustible (`fuel` o `vehicle_fuel`) y daño.
	var car: Node = scene.get_node_or_null("VehicleNorth") if scene != null else null
	var car_props: Array[String] = []
	if car != null:
		for prop in ["fuel", "vehicle_fuel", "max_fuel", "health", "hp"]:
			if _has_prop(car, String(prop)):
				car_props.append(String(prop))
	var car_methods: Array[String] = _method_names(car, ["consume_fuel", "refuel", "apply_damage", "take_damage", "is_out_of_fuel"])
	audit["vehicle_fuel_damage"] = (car_props.has("fuel") or car_props.has("vehicle_fuel")) and (
		car_methods.has("refuel") or car_methods.has("apply_damage") or car_methods.has("take_damage")
	)
	audit["vehicle_fuel_damage_detail"] = "props=%s metodos=%s" % [str(car_props), str(car_methods)]

	var active: int = 0
	for key in SYSTEMS:
		if bool(audit.get(key, false)):
			active += 1
	audit["active"] = active
	return audit
