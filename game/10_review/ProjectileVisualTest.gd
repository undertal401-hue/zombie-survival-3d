extends Node
## ============================================================================
## PROJECTILE VISUAL TEST — contrato de presentación de los disparos.
## ============================================================================
## El punto 3 exige que la bala se vea viajando con un sprite/efecto real.
## Esta puerta reproduce el camino real de Player._fire_hitscan(), comprueba
## que el proyectil nace con textura y visible, que conserva su origen y que
## avanza durante el vuelo. No acepta un Sprite2D sin imagen ni un objeto que
## permanezca oculto.
## ============================================================================

const PLAYER_SCENE: PackedScene = preload("res://02_player/Player.tscn")
const PISTOL: Weapon = preload("res://02_player/weapons/Pistol9mm.tres")

var _failures: Array[String] = []


func _check(condition: bool, label: String) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)


func _ready() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	player.position = Vector2(1000.0, 1000.0)
	add_child(player)
	await get_tree().process_frame

	var origin: Vector2 = player.global_position
	player.call("_fire_hitscan", PISTOL, origin, Vector2.RIGHT, false)

	var projectile: Node = _find_projectile(get_tree().current_scene)
	_check(projectile != null, "El disparo crea un proyectil visual")
	if projectile == null:
		await _finish()
		return

	_check(projectile.get("texture") != null,
		"El proyectil nace con una textura de sprite/efecto real")
	var texture: Texture2D = projectile.get("texture") as Texture2D
	if texture != null:
		_check(texture.get_width() > 0 and texture.get_height() > 0,
			"La textura del proyectil tiene dimensiones utilizables")
	else:
		_check(false, "La textura del proyectil tiene dimensiones utilizables")

	_check(bool(projectile.get("visible")),
		"El proyectil permanece visible durante el vuelo")

	var recorded_start: Vector2 = projectile.get("start_pos") as Vector2
	_check(recorded_start.is_equal_approx(origin),
		"El proyectil conserva el origen real del disparo")

	var position_before: Vector2 = projectile.global_position
	await get_tree().process_frame
	await get_tree().process_frame
	var position_after: Vector2 = projectile.global_position
	_check(position_after.x > position_before.x,
		"El proyectil avanza hacia el objetivo mientras es visible")

	await _finish()


func _find_projectile(node: Node) -> Node:
	for child in node.get_children():
		if child is Projectile:
			return child
		var nested: Node = _find_projectile(child)
		if nested != null:
			return nested
	return null


func _finish() -> void:
	print("PROJECTILE_VISUAL_TEST failures=%d" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
