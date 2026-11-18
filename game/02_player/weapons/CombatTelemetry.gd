extends RefCounted
class_name CombatTelemetry

## =============================================================================
## COMBAT TELEMETRY - Puente defensivo hacia GameState
## =============================================================================
## GameState es opcional: puede no existir (partidas antiguas, escenas de prueba)
## o puede no exponer todos los métodos. Ningún sistema de combate debe fallar
## por su ausencia, por eso toda consulta pasa por estos helpers.
## =============================================================================

## Devuelve el singleton solo si está vivo y accesible desde /root.
static func state_from(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	var gs: Node = node.get_node_or_null("/root/GameState")
	if gs == null or not is_instance_valid(gs):
		return null
	return gs

## record(clave, cantidad): contadores de disparos y daño. Se adaptan a firmas
## con uno o dos argumentos para no romper implementaciones parciales.
static func record(node: Node, key: String, amount: float = 1.0) -> void:
	var gs: Node = state_from(node)
	if gs == null or not gs.has_method("record"):
		return
	var argc: int = gs.get_method_argument_count("record")
	if argc >= 2:
		gs.call("record", key, amount)
	elif argc == 1:
		gs.call("record", key)

## rng('combat'): fuente de aleatoriedad sembrable. Si no está disponible se
## mantiene el comportamiento histórico (randf) para no alterar el QA actual.
static func random(node: Node, stream: String = "combat") -> float:
	var gs: Node = state_from(node)
	if gs == null or not gs.has_method("rng"):
		return randf()
	if gs.get_method_argument_count("rng") < 1:
		return randf()
	var value: Variant = gs.call("rng", stream)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	# Algunos GameState devuelven el RandomNumberGenerator (como hace 'loot').
	if value is Object and (value as Object).has_method("randf"):
		return clampf(float((value as Object).call("randf")), 0.0, 1.0)
	return randf()
