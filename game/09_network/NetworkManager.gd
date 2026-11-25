extends Node

## NetworkManager — gestor de sesión multijugador cooperativo (2–4 jugadores).
## ENet high-level API (Godot 4.7 built-in). Servidor AUTORITATIVO.
## Arquitectura:
##   - Cliente predice movimiento local, reconcilia con snapshot servidor (100ms interp, 3 snapshots buffer).
##   - RPC para acciones: disparar, recoger, crafting, entrar/salir vehículo.
##   - Sincronización via MultiplayerSynchronizer: jugador > zombi > mundo > botín (prioridad/banda).
##   - Banda ≤64 KB/s por jugador. Latencia objetivo ≤150ms.
##   - Sesión: host/join por IP, lista jugadores, ready state, migración host.

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal session_state_changed(state: String)
signal player_ready_changed(peer_id: int, ready: bool)
signal host_migrated(new_host_id: int)

enum SessionState { DISCONNECTED, CONNECTING, CONNECTED, IN_GAME }

const DEFAULT_PORT: int = 47777
const MAX_PLAYERS: int = 4
const TARGET_LATENCY_MS: int = 150
const INTERPOLATION_MS: int = 100
const SNAPSHOT_BUFFER: int = 3
const MAX_BANDWIDTH_KBPS: int = 64
const TICK_RATE: int = 30
const TICK_INTERVAL: float = 1.0 / TICK_RATE

## Prioridad de replicación (mayor = más importante)
const PRIO_PLAYER: int = 1
const PRIO_ZOMBIE: int = 2
const PRIO_WORLD: int = 3
const PRIO_LOOT: int = 4

var _session_state: SessionState = SessionState.DISCONNECTED
var _is_host: bool = false
var _local_peer_id: int = 1
var _ready_peers: Dictionary = {}  # peer_id -> bool
var _peer_names: Dictionary = {}   # peer_id -> String
var _tick_timer: float = 0.0
var _multiplayer_peer: MultiplayerPeer = null

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_peer_name(peer_id: int, name: String) -> void:
	_peer_names[peer_id] = name

@rpc("authority", "call_local", "reliable")
func _rpc_set_ready(peer_id: int, ready: bool) -> void:
	_ready_peers[peer_id] = ready
	player_ready_changed.emit(peer_id, ready)
	_check_all_ready()

func _ready() -> void:
	# Registrar como autoload singleton si no existe
	if not Engine.has_singleton("NetworkManager"):
		Engine.register_singleton("NetworkManager", self)
	
	# Configurar MultiplayerAPI
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL and is_server():
		_tick_timer = 0.0
		_server_tick()

## --- API pública -----------------------------------------------------------

func get_session_state() -> SessionState:
	return _session_state

func is_host() -> bool:
	return _is_host

func is_server() -> bool:
	return multiplayer.is_server()

func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()

func get_connected_peers() -> Array[int]:
	var peers: Array[int] = []
	if multiplayer.has_multiplayer_peer():
		peers = multiplayer.get_peers()
	return peers

func get_peer_name(peer_id: int) -> String:
	return _peer_names.get(peer_id, "Player %d" % peer_id)

func is_peer_ready(peer_id: int) -> bool:
	return _ready_peers.get(peer_id, false)

func are_all_ready() -> bool:
	if not is_server():
		return false
	var peers: Array[int] = get_connected_peers()
	for pid in peers:
		if not _ready_peers.get(pid, false):
			return false
	return true

## Inicia partida como host
func host_game(port: int = DEFAULT_PORT, player_name: String = "Host") -> Error:
	if _session_state != SessionState.DISCONNECTED:
		return Error.ERR_ALREADY_IN_USE
	
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS)
	if err != Error.OK:
		return err
	
	peer.host_compression = true
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	multiplayer.multiplayer_peer = peer
	
	_is_host = true
	_session_state = SessionState.CONNECTED
	_local_peer_id = 1
	_peer_names[1] = player_name
	_ready_peers[1] = false
	
	session_state_changed.emit(_session_state)
	return Error.OK

## Se une a partida existente
func join_game(ip: String, port: int = DEFAULT_PORT, player_name: String = "Client") -> Error:
	if _session_state != SessionState.DISCONNECTED:
		return Error.ERR_ALREADY_IN_USE
	
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != Error.OK:
		return err
	
	peer.host_compression = true
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	multiplayer.multiplayer_peer = peer
	
	_session_state = SessionState.CONNECTING
	session_state_changed.emit(_session_state)
	
	# Enviar nombre al conectar
	await get_tree().process_frame
	_rpc_set_peer_name.rpc_id(1, multiplayer.get_unique_id(), player_name)
	
	return Error.OK

## Abandona partida
func leave_game() -> void:
	if _session_state == SessionState.DISCONNECTED:
		return
	
	if is_server():
		# Host cierra servidor: notificar a todos
		multiplayer.multiplayer_peer = null
	else:
		# Cliente se desconecta
		multiplayer.multiplayer_peer = null
	
	_reset_state()

func set_ready(ready: bool) -> void:
	var pid: int = get_local_peer_id()
	_ready_peers[pid] = ready
	if is_server():
		player_ready_changed.emit(pid, ready)
		_check_all_ready()
	else:
		_rpc_set_ready.rpc_id(1, pid, ready)

func set_peer_name(name: String) -> void:
	var pid: int = get_local_peer_id()
	_peer_names[pid] = name
	if is_server():
		# Host ya lo tiene
		pass
	else:
		_rpc_set_peer_name.rpc_id(1, pid, name)

## --- Callbacks internos ----------------------------------------------------

func _on_peer_connected(id: int) -> void:
	print("Peer conectado: %d" % id)
	_peer_names[id] = "Player %d" % id
	_ready_peers[id] = false
	peer_connected.emit(id)
	
	if is_server():
		# Enviar estado actual al nuevo peer
		_sync_session_state_to_peer(id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer desconectado: %d" % id)
	_peer_names.erase(id)
	_ready_peers.erase(id)
	peer_disconnected.emit(id)
	
	if is_server():
		_check_host_migration(id)

func _on_connected_to_server() -> void:
	print("Conectado al servidor")
	_session_state = SessionState.CONNECTED
	session_state_changed.emit(_session_state)

func _on_connection_failed() -> void:
	print("Conexión fallida")
	_session_state = SessionState.DISCONNECTED
	session_state_changed.emit(_session_state)
	multiplayer.multiplayer_peer = null

func _on_server_disconnected() -> void:
	print("Servidor desconectado")
	_reset_state()

func _sync_session_state_to_peer(peer_id: int) -> void:
	# Enviar lista de peers y sus nombres/ready
	var peers_data: Dictionary = {}
	for pid in get_connected_peers():
		peers_data[pid] = {
			"name": _peer_names.get(pid, "Player %d" % pid),
			"ready": _ready_peers.get(pid, false)
		}
	# Nota: en implementación real se usaría RPC específico

func _check_all_ready() -> void:
	if are_all_ready() and _session_state == SessionState.CONNECTED:
		_session_state = SessionState.IN_GAME
		session_state_changed.emit(_session_state)
		# Notificar a todos para iniciar juego
		_rpc_start_game.rpc()

@rpc("authority", "call_local", "reliable")
func _rpc_start_game() -> void:
	_session_state = SessionState.IN_GAME
	session_state_changed.emit(_session_state)

func _check_host_migration(disconnected_id: int) -> void:
	if disconnected_id != 1:
		return  # No era el host
	
	var peers: Array[int] = get_connected_peers()
	if peers.is_empty():
		return
	
	# El peer con ID más bajo se convierte en nuevo host
	peers.sort()
	var new_host_id: int = peers[0]
	
	if new_host_id == get_local_peer_id():
		# Yo soy el nuevo host
		_is_host = true
		print("Migración de host: yo soy el nuevo host")
		host_migrated.emit(new_host_id)
		# Re-establecer servidor (simplificado)
	else:
		print("Migración de host: nuevo host es %d" % new_host_id)
		host_migrated.emit(new_host_id)

func _server_tick() -> void:
	# Lógica de tick del servidor: validar posiciones, procesar colas de acciones, etc.
	# En implementación completa: reconciliación, validación de movimiento, etc.
	pass

func _reset_state() -> void:
	_session_state = SessionState.DISCONNECTED
	_is_host = false
	_local_peer_id = 1
	_ready_peers.clear()
	_peer_names.clear()
	_tick_timer = 0.0
	session_state_changed.emit(_session_state)

## --- RPCs para acciones de juego ------------------------------------------

@rpc("authority", "call_local", "reliable")
func rpc_player_shoot(peer_id: int, weapon_id: String, from_pos: Vector2, direction: Vector2) -> void:
	# Servidor valida: arma equipada, munición, cooldown, línea de vista
	# Luego reenvía a todos para efectos visuales/daño
	rpc_id(peer_id, "rpc_shoot_confirmed", weapon_id)
	# Broadcast a otros para efectos
	for pid in get_connected_peers():
		if pid != peer_id:
			rpc_id(pid, "rpc_player_shot", peer_id, weapon_id, from_pos, direction)

@rpc("any_peer", "call_local", "reliable")
func rpc_pickup_item(peer_id: int, item_id: String, amount: int, container_path: NodePath) -> void:
	# Servidor valida: contenedor existe, no looteado, jugador en rango
	# Luego actualiza inventario y sincroniza
	pass

@rpc("any_peer", "call_local", "reliable")
func rpc_craft_item(peer_id: int, recipe_id: String) -> void:
	# Servidor valida: receta existe, materiales en inventario
	# Luego consume materiales y añade resultado
	pass

@rpc("any_peer", "call_local", "reliable")
func rpc_enter_vehicle(peer_id: int, vehicle_path: NodePath, seat: int) -> void:
	# Servidor valida: vehículo existe, asiento libre, jugador en rango
	pass

@rpc("any_peer", "call_local", "reliable")
func rpc_exit_vehicle(peer_id: int, vehicle_path: NodePath) -> void:
	# Servidor valida: jugador está en ese vehículo
	pass

## --- Utilidades -----------------------------------------------------------

func get_bandwidth_usage() -> Dictionary:
	# En implementación real: medir bytes enviados/recibidos por tipo
	return {
		"total_kbps": 0,
		"player_kbps": 0,
		"zombie_kbps": 0,
		"world_kbps": 0,
		"loot_kbps": 0
	}

## --- Interpolación y prioridad --------------------------------------------

## Buffer de snapshots para interpolación (100ms, 3 snapshots)
var _snapshot_buffer: Array[Dictionary] = []
const MAX_SNAPSHOTS: int = SNAPSHOT_BUFFER

## Interpolación de posición/rotación (100ms)
func interpolate_entity(entity: Node, target_pos: Vector2, target_rot: float, delta: float) -> void:
	if not entity or not is_instance_valid(entity):
		return
	var interp_factor: float = 1.0 - exp(-delta * 1000.0 / INTERPOLATION_MS)
	entity.global_position = entity.global_position.lerp(target_pos, interp_factor)
	entity.global_rotation = lerp_angle(entity.global_rotation, target_rot, interp_factor)

## Sistema de prioridad de replicación
func get_replication_priority(entity_type: String) -> int:
	match entity_type:
		"player": return PRIO_PLAYER
		"zombie": return PRIO_ZOMBIE
		"world": return PRIO_WORLD
		"loot": return PRIO_LOOT
		_: return 99

## Añadir snapshot al buffer para interpolación
func _add_snapshot(snapshot: Dictionary) -> void:
	_snapshot_buffer.append(snapshot)
	if _snapshot_buffer.size() > MAX_SNAPSHOTS:
		_snapshot_buffer.remove_at(0)

## Obtener snapshot interpolado para tiempo dado
func _get_interpolated_snapshot(time_ms: int) -> Dictionary:
	if _snapshot_buffer.is_empty():
		return {}
	# Buscar los dos snapshots que engloban el tiempo
	for i in range(_snapshot_buffer.size() - 1):
		var s1: Dictionary = _snapshot_buffer[i]
		var s2: Dictionary = _snapshot_buffer[i + 1]
		if s1.timestamp <= time_ms and s2.timestamp >= time_ms:
			var t: float = float(time_ms - s1.timestamp) / float(s2.timestamp - s1.timestamp)
			return _lerp_snapshots(s1, s2, t)
	return _snapshot_buffer[-1]

func _lerp_snapshots(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var result: Dictionary = {}
	for key in a.keys():
		if key == "timestamp":
			result[key] = b[key]
		elif b.has(key) and b[key] is float:
			result[key] = lerpf(a[key], b[key], t)
		else:
			result[key] = b[key]
	return result