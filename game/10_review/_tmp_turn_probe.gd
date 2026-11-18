extends Node

func _ready() -> void:
	await get_tree().process_frame
	var main: Node = load("res://07_house/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for _i in range(5):
		await get_tree().physics_frame
	var player: CharacterBody2D = main.get_node("Player") as CharacterBody2D
	var car: DriveableVehicle = main.get_node("VehicleNorth") as DriveableVehicle
	car.enter_vehicle(player)
	await get_tree().physics_frame

	Input.action_press("move_forward")
	var rots: Array[float] = []
	for _i in range(24):
		await get_tree().physics_frame
		rots.append(snappedf(car.rotation, 0.01))
	Input.action_release("move_forward")

	# Cambio brusco de dirección: un solo frame no puede saltar más que la
	# velocidad angular máxima, aunque el input apunte al lado opuesto.
	Input.action_press("move_left")
	var before: float = car.rotation
	await get_tree().physics_frame
	var after: float = car.rotation
	var step: float = absf(wrapf(after - before, -PI, PI))
	var max_step: float = DriveableVehicle.MAX_TURN_RATE / 60.0 + 0.01
	print("TURN rots=", rots, " step=", step,
		" max=", max_step, " ok=", step <= max_step,
		" occupied=", car.occupied, " engine=", car.engine_on,
		" driver_ok=", car.driver != null and is_instance_valid(car.driver),
		" input=", Input.get_vector("move_left", "move_right", "move_back", "move_forward"))
	Input.action_release("move_left")
	car.exit_vehicle()
	await get_tree().physics_frame
	get_tree().quit(0)
