extends Node

func _ready() -> void:
	await get_tree().process_frame
	var main: Node = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for i in range(10):
		await get_tree().process_frame
	for i in range(5):
		await get_tree().physics_frame

	var player: CharacterBody2D = main.get_node("Player")
	var car: Node = main.get_node_or_null("VehicleNorth")
	var wc: Node = player.get_node_or_null("WeaponController")
	print("PROBE main=", main != null, " player=", player != null,
		" car=", car != null, " weapon=", (wc != null and wc.current_weapon != null))
	if player == null or car == null or wc == null or wc.current_weapon == null:
		print("PROBE ABORT:缺少 nodos")
		return

	var names: Array = ImpactParticles.SurfaceType.keys()
	var surface: int = int(player.call("_get_surface_type", car))
	var surface_name: String = names[surface] if surface >= 0 and surface < names.size() else "?"
	print("PROBE surface_type=", surface, " (", surface_name, ")")

	player.global_position = (car as Node2D).global_position + Vector2(-100.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp_before: float = float(car.get("hp"))
	var from: Vector2 = player.global_position
	var to: Vector2 = (car as Node2D).global_position
	player.call("_on_fire_requested", wc.current_weapon, from, to)
	await get_tree().physics_frame
	var hp_after: float = float(car.get("hp"))
	print("PROBE shoot_from=", from, " to=", to, " hp=", hp_before, "->", hp_after,
		" damage=", snappedf(hp_before - hp_after, 3))

	# Autoimpacto al disparar desde el coche: la camioneta no debe bloquear ni
	# recibir daño propio. Capturamos notificaciones para ver qué impactó.
	var notes: Array[String] = []
	EventBus.notification.connect(func(text: String): notes.append(text))
	car.call("enter_vehicle", player)
	await get_tree().physics_frame
	var driving: bool = bool(player.get("is_driving"))
	var hp_drive_before: float = float(car.get("hp"))
	var drive_from: Vector2 = player.global_position
	player.call("_on_fire_requested", wc.current_weapon, drive_from,
		drive_from + Vector2(400.0, 0.0))
	await get_tree().physics_frame
	var hp_drive_after: float = float(car.get("hp"))
	print("PROBE driving=", driving, " from=", drive_from,
		" hp=", hp_drive_before, "->", hp_drive_after,
		" notificaciones=", notes)
	car.call("exit_vehicle")
	await get_tree().physics_frame
	var metal_ok: bool = surface == ImpactParticles.SurfaceType.METAL
	var damage_ok: bool = hp_after < hp_before - 1.0
	var no_self_ok: bool = absf(hp_drive_after - hp_drive_before) < 0.01
	print("PROBE RESULT metal=", metal_ok, " damage=", damage_ok,
		" no_self_damage=", no_self_ok,
		" PASS=", metal_ok and damage_ok and no_self_ok)
	get_tree().quit(0)
