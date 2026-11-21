extends Node
## ============================================================================
## PROJECTILE VISUAL TEST — contrato de presentación de los disparos.
## ============================================================================
## Cada bala debe tener un efecto pixel-art real, permanecer visible durante
## todo el vuelo y terminar exactamente en el impacto. La puerta reproduce
## el camino real del jugador, comprueba el abanico de perdigones y verifica
## que el daño hitscan sigue aplicandose exactamente una vez.
## ============================================================================

const PLAYER_SCENE: PackedScene = preload("res://02_player/Player.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://02_player/weapons/Projectile.tscn")
const PISTOL: Weapon = preload("res://02_player/weapons/Pistol9mm.tres")
const SHOTGUN: Weapon = preload("res://02_player/weapons/Shotgun12ga.tres")
const EFFECTS_PATH: String = "res://assets/art/sprites/effects.png"
const BULLET_SPARKS_REGION: Rect2 = Rect2(64.0, 0.0, 32.0, 32.0)

var _failures: Array[String] = []


class DamageTarget:
	extends CharacterBody2D
	var damage_calls: int = 0
	var total_damage: float = 0.0

	func take_damage(amount: float, _source: Node = null) -> void:
		damage_calls += 1
		total_damage += amount


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
	var visual_weapon: Weapon = PISTOL.duplicate() as Weapon
	visual_weapon.range = 503.0
	player.call("_fire_hitscan", visual_weapon, origin, Vector2.RIGHT, false)

	var projectiles: Array[Projectile] = _collect_projectiles(get_tree().current_scene)
	_check(projectiles.size() == 1,
		"El disparo de pistola crea exactamente un proyectil")
	if projectiles.is_empty():
		await _finish()
		return

	var projectile: Projectile = projectiles[0]
	var texture: Texture2D = projectile.texture
	_check(texture != null,
		"El proyectil nace con una textura de sprite/efecto real")
	_check(texture is AtlasTexture,
		"El proyectil usa un recorte AtlasTexture del banco canonico")
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		_check(atlas.atlas != null and atlas.atlas.resource_path == EFFECTS_PATH,
			"El AtlasTexture procede de effects.png")
		_check(atlas.region.is_equal_approx(BULLET_SPARKS_REGION),
			"El proyectil usa la celda canonica bullet_sparks")

	if texture != null:
		var image: Image = texture.get_image()
		var used_rect: Rect2i = image.get_used_rect()
		_check(used_rect.size.x > 0 and used_rect.size.y > 0,
			"La celda bullet_sparks contiene pixeles visibles")
	else:
		_check(false, "La celda bullet_sparks contiene pixeles visibles")

	_check(projectile.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"El proyectil conserva el filtro pixel-art nearest")

	var expected_start: Vector2 = origin + Vector2(visual_weapon.muzzle_flash_offset.x, 0.0)
	var expected_target: Vector2 = origin + Vector2(visual_weapon.range, 0.0)
	_check(projectile.start_pos.is_equal_approx(expected_start),
		"El proyectil emerge de la boca del arma, no del centro del cuerpo")
	_check(projectile.target.is_equal_approx(expected_target),
		"El proyectil conserva el punto de impacto real")

	var impact_state: Dictionary = {"count": 0, "position": Vector2.INF}
	projectile.impacted.connect(func(hit_pos: Vector2, _damage: float, _surface: int) -> void:
		impact_state["count"] = int(impact_state["count"]) + 1
		impact_state["position"] = hit_pos
	)

	var hidden_during_flight: bool = false
	var flight_frames: int = 0
	var flight_positions: Array[Vector2] = []
	var frames: int = 0
	while is_instance_valid(projectile) and frames < 180:
		if not projectile.is_visible_in_tree():
			hidden_during_flight = true
		if int(impact_state["count"]) == 0:
			flight_frames += 1
			flight_positions.append(projectile.global_position)
		await get_tree().process_frame
		frames += 1

	_check(not hidden_during_flight,
		"El proyectil permanece visible durante todo el vuelo")
	_check(flight_frames >= 2,
		"El proyectil permanece en vuelo durante varios frames")
	_check(flight_positions.size() >= 2
			and flight_positions[0].distance_to(flight_positions[-1]) > 0.0,
		"El proyectil avanza de forma observable entre frames")
	_check(int(impact_state["count"]) == 1,
		"El proyectil impacta exactamente una vez")
	var impact_position: Vector2 = impact_state["position"]
	_check(impact_position.distance_to(expected_target) <= 1.0,
		"El proyectil termina exactamente en el punto de impacto")

	# El tope de alcance tambien debe quedar protegido de forma
	# independiente del camino de disparo del jugador. Un proyectil lanzado
	# mas lejos de su travel_range debe terminar exactamente en ese limite.
	var capped_projectile: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	capped_projectile.speed = 300.0
	capped_projectile.global_position = Vector2(2000.0, 2000.0)
	add_child(capped_projectile)
	var capped_impact: Dictionary = {
		"count": 0,
		"position": Vector2.INF,
	}
	capped_projectile.impacted.connect(func(hit_pos: Vector2, _damage: float, _surface: int) -> void:
		capped_impact["count"] = int(capped_impact["count"]) + 1
		capped_impact["position"] = hit_pos
	)
	var capped_start: Vector2 = capped_projectile.global_position
	capped_projectile.launch(capped_start + Vector2(400.0, 0.0), 100.0, 10.0)
	var capped_frames: int = 0
	while is_instance_valid(capped_projectile) \
			and int(capped_impact["count"]) == 0 and capped_frames < 60:
		await get_tree().process_frame
		capped_frames += 1
	await get_tree().process_frame
	_check(capped_frames >= 2,
		"El proyectil limitado por alcance permanece en vuelo varios frames")
	_check(int(capped_impact["count"]) == 1,
		"El proyectil limitado por alcance impacta exactamente una vez")
	var capped_position: Vector2 = capped_impact["position"]
	_check(capped_position.distance_to(capped_start + Vector2(100.0, 0.0)) <= 1.0,
		"El proyectil se detiene exactamente en su alcance maximo")

	# El camino de produccion de la escopeta crea un proyectil por perdigon.
	player.call("_on_fire_requested", SHOTGUN, origin, origin + Vector2(200.0, 0.0))
	var shotgun_projectiles: Array[Projectile] = _collect_projectiles(get_tree().current_scene)
	_check(shotgun_projectiles.size() == SHOTGUN.pellets_per_shot,
		"La escopeta crea un proyectil visible por perdigon")
	var hidden_pellets: int = 0
	for pellet in shotgun_projectiles:
		if not pellet.is_visible_in_tree() or pellet.texture == null:
			hidden_pellets += 1
	_check(hidden_pellets == 0,
		"Todos los perdigones nacen visibles y con textura")
	for pellet in shotgun_projectiles:
		if is_instance_valid(pellet):
			pellet.queue_free()
	await get_tree().process_frame

	# El dano sigue siendo hitscan: el proyectil es solo visual y no debe
	# duplicar ni reemplazar la aplicacion del impacto original.
	var target := DamageTarget.new()
	target.name = "PistolDamageTarget"
	target.position = origin + Vector2(30.0, 0.0)
	target.collision_layer = 1
	target.collision_mask = 0
	target.add_to_group("zombies")
	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32.0, 32.0)
	collision.shape = rect
	target.add_child(collision)
	add_child(target)
	await get_tree().physics_frame

	player.call("_on_fire_requested", PISTOL, origin, origin + Vector2(500.0, 0.0))
	await get_tree().physics_frame
	_check(target.damage_calls == 1,
		"El impacto hitscan aplica dano exactamente una vez")
	_check(is_equal_approx(target.total_damage, PISTOL.base_damage),
		"El impacto conserva el dano original de la pistola")

	# Una instancia sin asset no puede quedarse oculta indefinidamente: debe
	# liberarse en vez de crear un proyectil invisible permanente.
	var blank: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	blank.texture = null
	add_child(blank)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not is_instance_valid(blank) or blank.is_queued_for_deletion(),
		"Un proyectil sin textura se libera y no queda oculto")

	await _finish()


func _collect_projectiles(node: Node) -> Array[Projectile]:
	var result: Array[Projectile] = []
	for child in node.get_children():
		if child is Projectile:
			result.append(child as Projectile)
		result.append_array(_collect_projectiles(child))
	return result


func _finish() -> void:
	print("PROJECTILE_VISUAL_TEST failures=%d" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
