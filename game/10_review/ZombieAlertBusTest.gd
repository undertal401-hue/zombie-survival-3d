extends Node
## ============================================================================
## ZOMBIE ALERT BUS TEST (R1-hotfix) — la ruta vehículo -> zombi.
## ============================================================================
## Al abrir el juego de verdad (no el arnés) apareció este error EN VIVO,
## una vez por frame mientras se conduce un vehículo cerca de los zombis:
##
##   SCRIPT ERROR: Invalid operands 'Vector2' and 'Object' in operator '=='.
##          at: _on_bus_alert_2 (res://03_zombies/Zombie.gd:451)
##   GDScript backtrace (most recent call last):
##       [0] _on_bus_alert_2 (res://03_zombies/Zombie.gd:451)
##       [1] _emit_alert (res://12_vehicles/DriveableVehicle.gd:353)
##       [2] _physics_process (res://12_vehicles/DriveableVehicle.gd:204)
##
## CAUSA: `EventBus.zombie_alerted` se declara como `zombie_alerted(zombie,
## source)`, pero `DriveableVehicle._emit_alert()` inspecciona la firma y
## emite `(posicion: Vector2, radio: float)`. El receptor del zombi hacía
## `if a == self` con `a` = Vector2: en GDScript 4 comparar un Vector2 con un
## Object es un ERROR EN TIEMPO DE EJECUCIÓN (no devuelve false, aborta la
## llamada). El zombie nunca llegaba a oír el ruido y el juego escupía el
## error en cada frame de conducción.
##
## El guard correcto tiene que ser CONSERVADOR DE TIPO: "esto soy yo" solo
## puede ser cierto si el valor es un Node vivo. Además el bus admite dos
## convenciones (nodo o posición), así que el arnés cubre las dos.
##
## La AUSENCIA del error en runtime la verifica el grep del CI
## (`SCRIPT ERROR|Parse Error|...`): GDScript no permite interceptar un
## SCRIPT ERROR. Este arnés aporta la mitad positiva y determinista: si el
## handler aborta, el zombi NO se alerta y el check falla.
## ============================================================================

const ZOMBIE_SCENE: String = "res://03_zombies/Zombie.tscn"
const ZOMBIE_SCRIPT: String = "res://03_zombies/Zombie.gd"
const VEHICLE_SCENE: String = "res://12_vehicles/DriveableVehicle.tscn"

## Radio y posición con los que el vehículo avisa al bus.
const ALERT_POS: Vector2 = Vector2(60.0, 0.0)
const ALERT_RADIUS: float = 400.0

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _read(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	return ""


func _ready() -> void:
	await get_tree().process_frame
	_guard_is_type_aware()
	await _runtime_vehicle_alert()
	await _runtime_node_convention()
	await _runtime_self_alert()
	await _runtime_freed_payload()
	await _runtime_real_vehicle()
	await _runtime_direct_handlers()
	print("ZOMBIE_ALERT_BUS_TEST failures=%d" % _failures.size())
	for f in _failures:
		print("  - " + f)
	get_tree().quit(1 if not _failures.is_empty() else 0)
	_asserts()


## ---------------------------------------------------------------------------
## 1. Introspección mínima: los handlers NO comparan un Variant crudo con self.
##
## Se mantiene solo el contrato que esta clase de bug rompió ("a == self").
## El resto se demuestra con COMPORTAMIENTO en runtime: nombrar el helper
## es un detalle de implementacion que un test no deberia fijar.
## ---------------------------------------------------------------------------
func _guard_is_type_aware() -> void:
	var src: String = _read(ZOMBIE_SCRIPT)
	for header in ["func _on_bus_alert_1(", "func _on_bus_alert_2(", "func _on_bus_alert_3("]:
		var body: String = _func_body(src, header, 12)
		_check(not body.contains("== self"),
			"Zombie.gd:%s no compara el Variant crudo con self" % header)


func _func_body(src: String, header: String, span: int = 30) -> String:
	var start: int = src.find(header)
	if start == -1:
		return ""
	var lines: PackedStringArray = src.substr(start, span * 80).split("\n")
	return "\n".join(lines.slice(0, span))


## ---------------------------------------------------------------------------
## 2. Runtime: la convención real del vehículo (Vector2, float).
## ---------------------------------------------------------------------------
func _runtime_vehicle_alert() -> void:
	var zombie: Node = await _fresh_zombie(Vector2.ZERO)
	if zombie == null:
		_check(false, "Runtime: se pudo instanciar un zombi")
		return

	# EXACTAMENTE lo que emite DriveableVehicle._emit_alert().
	EventBus.zombie_alerted.emit(ALERT_POS, ALERT_RADIUS)
	await get_tree().process_frame

	_check(_is_alerted(zombie),
		"Runtime: el zombi OYE el ruido del vehiculo (estado=%d)" % int(zombie.get("state")))
	var last: Vector2 = zombie.get("_last_known")
	_check(last.distance_to(ALERT_POS) < 0.5,
		"Runtime: el zombi recuerda el punto del ruido (%s)" % str(last))
	zombie.queue_free()


## ---------------------------------------------------------------------------
## 3. Runtime: la convención declarada del bus (nodo, nodo).
## ---------------------------------------------------------------------------
func _runtime_node_convention() -> void:
	var zombie: Node = await _fresh_zombie(Vector2.ZERO)
	var other: Node = await _fresh_zombie(Vector2(100.0, 0.0))
	if zombie == null or other == null:
		_check(false, "Runtime: se pudieron instanciar dos zombis")
		return

	# Con la convencion (zombie, source) el punto del ruido es la posicion
	# del zombi que avisa y el radio es el de propagacion (420 px).
	EventBus.zombie_alerted.emit(other, null)
	await get_tree().process_frame

	_check(_is_alerted(zombie),
		"Runtime: el zombi oye la alerta de otro zombi (estado=%d)" % int(zombie.get("state")))
	zombie.queue_free()
	other.queue_free()


## ---------------------------------------------------------------------------
## 4. Runtime: un zombi NO oye su propia alerta.
## ---------------------------------------------------------------------------
func _runtime_self_alert() -> void:
	var zombie: Node = await _fresh_zombie(Vector2.ZERO)
	if zombie == null:
		_check(false, "Runtime: se pudo instanciar un zombi (self-alert)")
		return

	EventBus.zombie_alerted.emit(zombie, zombie)
	await get_tree().process_frame

	_check(not _is_alerted(zombie),
		"Runtime: un zombi ignora SU propia alerta (estado=%d)" % int(zombie.get("state")))
	zombie.queue_free()


## ---------------------------------------------------------------------------
## 5. Runtime: un payload LIBERADO no debe abortar el handler NI inventar un
##    punto de ruido.
##
## Es el mismo patron que motivo el R1-fix del payload de `zombie_died`: en
## Godot 4.7.2, `instancia_liberada is Node` LANZA "Left operand of 'is' is a
## previously freed instance" (medido: `is_instance_valid()` devuelve false,
## pero el `is` aborta). Por eso el orden de guards es
## `typeof` -> `is_instance_valid` -> `is` (ADR-004 §9).
##
## CASO A (deteccion COMPORTAMENTAL, sin depender del grep del CI): el
## payload liberado va en el PRIMER argumento. Con el codigo roto,
## `_alert_point()` abortaba y devolvia (0,0) en vez de INF, asi que el zombi
## perseguia un punto INVENTADO. El zombi esta a 100 px del origen, dentro
## del radio de propagacion (420): con el bug se alerta, con el arreglo no.
##
## CASO B: payload liberado en el SEGUNDO argumento con un punto valido en el
## primero: el punto valido debe respetarse y el handler no debe lanzar
## ningun SCRIPT ERROR (eso lo comprueba el grep del CI).
## ---------------------------------------------------------------------------
func _runtime_freed_payload() -> void:
	var zombie: Node = await _fresh_zombie(Vector2(100.0, 0.0))
	if zombie == null:
		_check(false, "Runtime: se pudo instanciar un zombi (payload liberado)")
		return

	# Nodo real liberado: sigue siendo un Variant que apunta a un objeto
	# liberado (typeof == TYPE_OBJECT, is_instance_valid == false).
	var ghost: Node = Node.new()
	add_child(ghost)
	ghost.free()
	var freed: Variant = ghost

	# --- CASO A: punto desconocido -> el zombi NO debe perseguir nada ---
	EventBus.zombie_alerted.emit(freed, ALERT_RADIUS)
	await get_tree().process_frame

	_check(not _is_alerted(zombie),
		"Runtime: un payload LIBERADO no inventa un punto de ruido (estado=%d)" % int(zombie.get("state")))
	var last_a: Vector2 = zombie.get("_last_known")
	_check(last_a.distance_to(Vector2(100.0, 0.0)) < 0.5,
		"Runtime: el zombi no se mueve a un punto inexistente (%s)" % str(last_a))

	# --- CASO B: punto valido + payload liberado en el segundo argumento ---
	_arm(zombie, Vector2.ZERO)
	EventBus.zombie_alerted.emit(ALERT_POS, freed)
	await get_tree().process_frame

	_check(_is_alerted(zombie),
		"Runtime: un payload liberado en el 2o argumento no rompe el resto (estado=%d)" % int(zombie.get("state")))
	var last_b: Vector2 = zombie.get("_last_known")
	_check(last_b.distance_to(ALERT_POS) < 0.5,
		"Runtime: tras el payload liberado el zombi oye el punto valido (%s)" % str(last_b))
	zombie.queue_free()


## ---------------------------------------------------------------------------
## 6. Runtime: la ruta REAL del vehiculo (no una emision a mano).
##
## El bug nacio de `DriveableVehicle._emit_alert()`, que inspecciona la firma
## del bus y emite `(posicion, radio)`. Si el vehiculo dejara de emitir o
## cambiara el orden de sus argumentos, este arnes debe notarlo.
## ---------------------------------------------------------------------------
func _runtime_real_vehicle() -> void:
	var zombie: Node = await _fresh_zombie(Vector2.ZERO)
	var vehicle: Node = load(VEHICLE_SCENE).instantiate()
	add_child(vehicle)
	for i in range(4):
		await get_tree().process_frame
	if zombie == null or vehicle == null:
		_check(false, "Runtime: se pudieron instanciar zombi y vehiculo")
		return
	zombie.global_position = Vector2.ZERO

	# El metodo REAL del vehiculo: inspecciona la firma del bus y emite.
	if not vehicle.has_method("_emit_alert"):
		_check(false, "Runtime: el vehiculo expone _emit_alert(...)")
		return
	vehicle.call("_emit_alert", ALERT_POS, ALERT_RADIUS)
	await get_tree().process_frame

	_check(_is_alerted(zombie),
		"Runtime: el zombi oye el ruido del VEHICULO REAL (estado=%d)" % int(zombie.get("state")))
	var last: Vector2 = zombie.get("_last_known")
	_check(last.distance_to(ALERT_POS) < 0.5,
		"Runtime: el vehiculo real entrega el punto correcto (%s)" % str(last))
	zombie.queue_free()
	vehicle.queue_free()


## ---------------------------------------------------------------------------
## 7. Runtime: las variantes de 1 y 3 argumentos del handler.
##
## El bus actual tiene 2 argumentos, asi que `_on_bus_alert_1` y
## `_on_bus_alert_3` no reciben nada: el cambio del guard tambien las toca,
## asi que se ejercitan directamente para que no se pudran romper en silencio.
## ---------------------------------------------------------------------------
func _runtime_direct_handlers() -> void:
	var zombie: Node = await _fresh_zombie(Vector2.ZERO)
	if zombie == null:
		_check(false, "Runtime: se pudo instanciar un zombi (handlers directos)")
		return

	# Variante de 1 argumento: (posicion).
	zombie.call("_on_bus_alert_1", ALERT_POS)
	await get_tree().process_frame
	_check(_is_alerted(zombie),
		"Runtime: _on_bus_alert_1(posicion) alerta al zombi (estado=%d)" % int(zombie.get("state")))

	# Variante de 3 argumentos: (zombie, radio, source).
	var other: Node = await _fresh_zombie(Vector2(100.0, 0.0))
	_arm(zombie, Vector2.ZERO)
	zombie.call("_on_bus_alert_3", other, ALERT_RADIUS, null)
	await get_tree().process_frame
	_check(_is_alerted(zombie),
		"Runtime: _on_bus_alert_3(zombie, radio, source) alerta al zombi (estado=%d)" % int(zombie.get("state")))

	zombie.queue_free()
	if other != null:
		other.queue_free()


## Instancia un zombi NUEVO y lo deja en vigilancia limpia.
## Cada caso usa su propio zombi: si comparten instancia, el estado que deja
## un caso (alerta, cooldowns, `_last_known`) contamina al siguiente y la
## prueba miente.
func _fresh_zombie(position: Vector2) -> Node:
	var zombie: Node = load(ZOMBIE_SCENE).instantiate()
	add_child(zombie)
	for i in range(4):
		await get_tree().process_frame
	_arm(zombie, position)
	return zombie


## Deja al zombi en un estado limpio y VIGILANTE antes de cada prueba.
func _arm(zombie: Node, position: Vector2) -> void:
	zombie.global_position = position
	zombie.set("state", 0)  # State.PATROL
	zombie.set("_noise_cooldown", 0.0)
	zombie.set("_alert_timer", 0.0)
	zombie.set("_last_known", position)
	zombie.set("_spawn_position", position)


## Un zombi alertado deja de estar en PATROL: pasa a CHASE y, si no hay
## jugador a la vista, cae a INVESTIGATE persiguiendo el ultimo punto Known.
## Lo que NO puede es seguir en PATROL.
func _is_alerted(zombie: Node) -> bool:
	return int(zombie.get("state")) != 0


func _asserts() -> void:
	if not ("--strict-assert" in OS.get_cmdline_user_args()):
		return
	assert(_failures.is_empty(), "ZOMBIE_ALERT_BUS_TEST: hay fallos")
