extends Node2D

## Zombies exclusivos del bosque. Se crean solo mientras el jugador está dentro
## del bosque y se liberan al salir o al morir, para no dejar bodies extra en el
## mundo ni contaminar las comprobaciones de QA.

const ZOMBIE_SCENE: PackedScene = preload("res://03_zombies/Zombie.tscn")
const MAX_ZOMBIES: int = 6
const MIN_PLAYER_DISTANCE: float = 700.0
const PUSH_DISTANCE: float = 900.0
const RNG_SEED: int = 20261117
# Reparto fijo: 3 Walker, 1 Runner, 1 Tank, 1 Spitter.
const ZOMBIE_KINDS: Array[int] = [0, 0, 0, 1, 2, 3]

var _forest: Node2D = null
var _spawned: Array[CharacterBody2D] = []
var _in_forest: bool = false
var _notified: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_forest = get_tree().get_first_node_in_group("forest") as Node2D
	_rng.seed = RNG_SEED
	EventBus.forest_entered.connect(_on_forest_entered)
	EventBus.forest_exited.connect(_on_forest_exited)
	EventBus.game_over.connect(_on_game_over)
	EventBus.zombie_died.connect(_on_zombie_died)

func _on_forest_entered() -> void:
	if _in_forest:
		return
	_in_forest = true
	_spawn_zombies()

func _on_forest_exited() -> void:
	_in_forest = false
	_clear_zombies()

func _on_game_over() -> void:
	_in_forest = false
	_clear_zombies()

func _spawn_zombies() -> void:
	if _spawned.size() > 0:
		_clear_zombies()
	if _forest == null or not is_instance_valid(_forest):
		_forest = get_tree().get_first_node_in_group("forest") as Node2D
	if _forest == null or not is_instance_valid(_forest):
		return
	if not _forest.has_method("forest_zombie_spawn_points"):
		return

	var points: Array = _forest.call("forest_zombie_spawn_points")
	var count: int = mini(MAX_ZOMBIES, points.size())
	if count <= 0:
		return

	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	for i in range(count):
		var point: Vector2 = points[i]
		point = _away_from_player(point, player)
		var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody2D
		if zombie == null:
			continue
		zombie.name = "ForestZombie%d" % (i + 1)
		zombie.set_meta("forest_zombie", true)
		zombie.set("kind", ZOMBIE_KINDS[i % ZOMBIE_KINDS.size()])
		# Misma IA que el resto: Zombie.tscn ya trae NavigationAgent2D, FSM,
		# percepcion y alerta en grupo; aqui solo se controla el ciclo de vida.
		# Hijo de este nodo, nunca de Level: asi no entra en "nav_obstacles".
		add_child(zombie)
		zombie.global_position = point
		zombie.tree_exiting.connect(_on_spawned_tree_exiting.bind(zombie))
		_spawned.append(zombie)

	if not _notified and _spawned.size() > 0:
		_notified = true
		EventBus.notification.emit("¡Algo se mueve entre los árboles")

## Aleja deterministamente el punto 900 px si cae a menos de 700 px del jugador.
func _away_from_player(point: Vector2, player: Node2D) -> Vector2:
	if player == null or not is_instance_valid(player):
		return point
	if point.distance_to(player.global_position) >= MIN_PLAYER_DISTANCE:
		return point
	var angle: float = _rng.randf_range(0.0, TAU)
	return point + Vector2.RIGHT.rotated(angle) * PUSH_DISTANCE

## R1-fix: el payload no se tipa y se valida ANTES de tocarlo.
## Con `zombie: Node2D`, una instancia ya liberada hacia que el motor
## rechazase la llamada ("Cannot convert argument 1 from Object to Object")
## y el error nombraba ESTE fichero ("Zombies.gd" en el reporte del usuario).
##
## ORDEN CRÍTICO de los guards (medido en Godot 4.7.2, sonda `r1_sem.gd`):
##   - `libre == null` es TRUE: un guard `== null` se TRAGA la instancia
##     liberada y el resto de la función no llega a ejecutarse.
##   - `typeof(libre)` sigue siendo TYPE_OBJECT (24), así que `typeof` sí
##     distingue null real (TYPE_NIL = 0) de instancia liberada.
##   - `libre is Object` LANZA "previously freed instance": el operador `is`
##     no puede usarse antes de comprobar la vigencia.
func _on_zombie_died(zombie) -> void:
	if typeof(zombie) == TYPE_NIL:
		return
	if typeof(zombie) != TYPE_OBJECT:
		return
	if not is_instance_valid(zombie):
		# El zombi ya está liberado: no hay metadatos que leer, pero sí hay
		# una entrada obsoleta que limpiar de la lista.
		_forget(null)
		return
	if not (zombie is Node):
		return
	if not bool(zombie.get_meta("forest_zombie", false)):
		return
	_forget(zombie)


func _on_spawned_tree_exiting(zombie) -> void:
	if zombie == null or not is_instance_valid(zombie):
		return
	_forget(zombie)


func _forget(zombie) -> void:
	for i in range(_spawned.size() - 1, -1, -1):
		if not is_instance_valid(_spawned[i]):
			_spawned.remove_at(i)
		elif zombie != null and is_instance_valid(zombie) and _spawned[i] == zombie:
			_spawned.remove_at(i)


func _clear_zombies() -> void:
	for zombie in _spawned.duplicate():
		if is_instance_valid(zombie) and not zombie.is_queued_for_deletion():
			zombie.queue_free()
	_spawned.clear()
