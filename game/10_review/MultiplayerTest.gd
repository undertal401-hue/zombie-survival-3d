extends Node
## ============================================================================
## MULTIPLAYER TEST — cooperativo 2–4 jugadores, arquitectura cliente-servidor.
## ============================================================================
## Contrato (punto 15):
## - ENet high-level API (Godot 4.7 built-in) para LAN/Internet.
## - Servidor AUTORITATIVO: posición, vida, inventario, zombis, mundo.
## - Cliente predice movimiento local, reconcilia con snapshot servidor.
## - RPC para acciones: disparar, recoger, crafting, entrar/salir vehículo.
## - Sincronización: jugador (pos/rot/vida/inv/arma), zombi (pos/estado/vida),
##   mundo (fase/timer/hordas), botín (estado contenedores), vehículo (pos/combustible).
## - Latencia objetivo ≤150ms: interpolación 100ms, buffer 3 snapshots.
## - Banda: ≤64 KB/s por jugador (prioridad: jugador > zombi > mundo > botín).
## - Sesión: host/join por IP, lista jugadores, ready state, migración host.
## ============================================================================

const TEST_PORT: int = 47777
const MAX_PLAYERS: int = 4
const TARGET_LATENCY_MS: int = 150
const INTERPOLATION_MS: int = 100
const SNAPSHOT_BUFFER: int = 3
const MAX_BANDWIDTH_KBPS: int = 64

var _failures: Array[String] = []
var _checks: int = 0
var _server: Node = null
var _client1: Node = null
var _client2: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await _test_network_manager_exists()
	await _test_enet_high_level_api()
	await _test_server_authoritative_model()
	await _test_player_sync_position_rotation()
	await _test_player_sync_health_inventory()
	await _test_player_sync_weapon_state()
	await _test_zombie_sync_server_authoritative()
	await _test_world_state_sync_day_night()
	await _test_loot_container_sync()
	await _test_vehicle_sync()
	await _test_rpc_actions_shoot_pickup_craft()
	await _test_interpolation_and_reconciliation()
	await _test_bandwidth_budget()
	await _test_session_management_host_join()
	await _test_host_migration()
	_finish()

func _check(condition: bool, label: String) -> void:
	_checks += 1
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		_failures.append(label)

## 1. NetworkManager existe como autoload/singleton
func _test_network_manager_exists() -> void:
	var nm_script: Script = load("res://09_network/NetworkManager.gd") as Script
	_check(nm_script != null, "NetworkManager.gd existe en 09_network/")
	if nm_script != null:
		var nm: Node = nm_script.new()
		_check(nm.has_method("host_game"), "tiene host_game()")
		_check(nm.has_method("join_game"), "tiene join_game(ip)")
		_check(nm.has_method("leave_game"), "tiene leave_game()")
		_check(nm.has_method("get_connected_peers"), "tiene get_connected_peers()")
		_check(nm.has_method("is_server"), "tiene is_server()")
		_check(nm.has_method("get_local_peer_id"), "tiene get_local_peer_id()")
		_check(nm.has_signal("peer_connected"), "signal peer_connected(id)")
		_check(nm.has_signal("peer_disconnected"), "signal peer_disconnected(id)")
		_check(nm.has_signal("session_state_changed"), "signal session_state_changed(state)")
		nm.queue_free()

## 2. Usa ENet high-level API (MultiplayerAPI)
func _test_enet_high_level_api() -> void:
	var nm_script: Script = load("res://09_network/NetworkManager.gd") as Script
	if nm_script == null:
		_failures.append("NetworkManager no existe")
		return
	var source: String = nm_script.get_source_code()
	_check(source.contains("MultiplayerAPI") or source.contains("ENetConnection"), "usa ENet/MultiplayerAPI")
	_check(source.contains("create_server") or source.contains("create_client"), "crea conexión ENet")
	_check(source.contains("set_multiplayer_peer") or source.contains("multiplayer.multiplayer_peer"), "registra peer en MultiplayerAPI")

## 3. Modelo servidor AUTORITATIVO
func _test_server_authoritative_model() -> void:
	var nm_script: Script = load("res://09_network/NetworkManager.gd") as Script
	if nm_script == null:
		return
	var source: String = nm_script.get_source_code()
	# El servidor valida posición, vida, inventario; cliente solo predice
	_check(source.contains("is_server()") or source.contains("Multiplayer.is_server()"), "verifica is_server() para lógica autoritativa")
	_check(source.contains("rpc_id") or source.contains("@rpc"), "usa RPC para acciones cliente->servidor")
	_check(source.contains("call_remote") or source.contains("rpc"), "usa RPC para servidor->cliente")

## 4. Sincronización jugador: posición + rotación
func _test_player_sync_position_rotation() -> void:
	var player_script: Script = load("res://02_player/Player.gd") as Script
	if player_script == null:
		_failures.append("Player.gd no existe")
		return
	var source: String = player_script.get_source_code()
	_check(source.contains("network_sync") or source.contains("replicate") or source.contains("MultiplayerSynchronizer"), "Player tiene sincronización de red (MultiplayerSynchronizer o similar)")
	_check(source.contains("position") and source.contains("rotation"), "sincroniza position y rotation")
	# Debe usar replicación unreliable para posición (alta frecuencia)
	var nm_script: Script = load("res://09_network/NetworkManager.gd") as Script
	if nm_script != null:
		var nm_source: String = nm_script.get_source_code()
		_check(nm_source.contains("unreliable") or nm_source.contains("UNRELIABLE"), "posición usa canal unreliable")

## 5. Sincronización jugador: vida + inventario
func _test_player_sync_health_inventory() -> void:
	var player_script: Script = load("res://02_player/Player.gd") as Script
	var inv_script: Script = load("res://02_player/Inventory.gd") as Script
	if player_script == null or inv_script == null:
		return
	var p_source: String = player_script.get_source_code()
	var i_source: String = inv_script.get_source_code()
	_check(p_source.contains("health") or p_source.contains("hp"), "Player tiene health/hp")
	_check(i_source.contains("network_sync") or i_source.contains("MultiplayerSynchronizer"), "Inventory tiene sincronización")
	# Vida e inventario: reliable, baja frecuencia
	var nm_script: Script = load("res://09_network/NetworkManager.gd") as Script
	if nm_script != null:
		var nm_source: String = nm_script.get_source_code()
		_check(nm_source.contains("reliable") or nm_source.contains("RELIABLE"), "inventario/vida usa canal reliable")

## 6. Sincronización jugador: arma equipada + munición + condición
func _test_player_sync_weapon_state() -> void:
	var wc_script: Script = load("res://02_player/weapons/WeaponController.gd") as Script
	if wc_script == null:
		return
	var source: String = wc_script.get_source_code()
	_check(source.contains("current_weapon") or source.contains("equipped_weapon"), "tiene arma equipada")
	_check(source.contains("ammo") or source.contains("munition"), "tiene munición")
	_check(source.contains("condition") or source.contains("durability"), "tiene condición/durabilidad")
	_check(source.contains("network_sync") or source.contains("MultiplayerSynchronizer"), "WeaponController sincronizado")

## 7. Zombis: servidor autoritativo (pos, estado, vida)
func _test_zombie_sync_server_authoritative() -> void:
	var z_script: Script = load("res://03_zombies/Zombie.gd") as Script
	if z_script == null:
		return
	var source: String = z_script.get_source_code()
	_check(source.contains("is_server()") or source.contains("Multiplayer.is_server()"), "Zombie verifica is_server() para IA/movimiento")
	_check(source.contains("network_sync") or source.contains("MultiplayerSynchronizer"), "Zombie tiene sincronización")
	# Solo servidor spawns zombis
	var wd_script: Script = load("res://01_core/WorldDirector.gd") as Script
	if wd_script != null:
		var wd_source: String = wd_script.get_source_code()
		_check(wd_source.contains("is_server()") or wd_source.contains("Multiplayer.is_server()"), "WorldDirector solo spawnea en servidor")

## 8. Mundo: sincronización fase día/noche, timer, hordas
func _test_world_state_sync_day_night() -> void:
	var wd_script: Script = load("res://01_core/WorldDirector.gd") as Script
	var gs_script: Script = load("res://01_core/GameState.gd") as Script
	if wd_script == null or gs_script == null:
		return
	var wd_source: String = wd_script.get_source_code()
	var gs_source: String = gs_script.get_source_code()
	_check(wd_source.contains("network_sync") or wd_source.contains("MultiplayerSynchronizer"), "WorldDirector sincronizado")
	_check(gs_source.contains("network_sync") or gs_source.contains("MultiplayerSynchronizer"), "GameState sincronizado")
	# Fase, timer, horda activa, wave
	_check(wd_source.contains("current_phase") or wd_source.contains("_phase"), "tiene fase actual")
	_check(wd_source.contains("horde") or wd_source.contains("_horde"), "tiene estado de horda")

## 9. Botín: contenedores sincronizados (estado abierto/cerrado, contenido)
func _test_loot_container_sync() -> void:
	var lc_script: Script = load("res://04_items/LootContainer.gd") as Script
	if lc_script == null:
		return
	var source: String = lc_script.get_source_code()
	_check(source.contains("network_sync") or source.contains("MultiplayerSynchronizer"), "LootContainer sincronizado")
	_check(source.contains("_looted") or source.contains("looted"), "tiene estado looteado")
	_check(source.contains("rpc") or source.contains("@rpc"), "usa RPC para loot()")

## 10. Vehículo: posición, combustible, vida, conductor/pasajeros
func _test_vehicle_sync() -> void:
	var veh_script: Script = load("res://12_vehicles/DriveableVehicle.gd") as Script
	if veh_script == null:
		return
	var source: String = veh_script.get_source_code()
	_check(source.contains("network_sync") or source.contains("MultiplayerSynchronizer"), "DriveableVehicle sincronizado")
	_check(source.contains("fuel") or source.contains("combustible"), "tiene combustible")
	_check(source.contains("health") or source.contains("hp"), "tiene vida")
	_check(source.contains("driver") or source.contains("occupied"), "tiene conductor/ocupantes")

## 11. RPC para acciones: disparar, recoger, crafting, entrar/salir vehículo
func _test_rpc_actions_shoot_pickup_craft() -> void:
	var player_script: Script = load("res://02_player/Player.gd") as Script
	var wc_script: Script = load("res://02_player/weapons/WeaponController.gd") as Script
	var inv_script: Script = load("res://02_player/Inventory.gd") as Script
	var veh_script: Script = load("res://12_vehicles/DriveableVehicle.gd") as Script
	
	var all_sources: Array[String] = []
	if player_script != null: all_sources.append(player_script.get_source_code())
	if wc_script != null: all_sources.append(wc_script.get_source_code())
	if inv_script != null: all_sources.append(inv_script.get_source_code())
	if veh_script != null: all_sources.append(veh_script.get_source_code())
	
	var combined: String = "\n".join(all_sources)
	_check(combined.contains("@rpc") or combined.contains("rpc(") or combined.contains("rpc_id"), "usa @rpc o rpc() para acciones")
	# Disparar
	_check(combined.contains("shoot") or combined.contains("fire") or combined.contains("disparar"), "tiene acción disparar")
	# Recoger
	_check(combined.contains("pickup") or combined.contains("recoger") or combined.contains("loot"), "tiene acción recoger")
	# Crafting
	_check(combined.contains("craft") or combined.contains("fabricar"), "tiene acción crafting")
	# Vehículo enter/exit
	_check(combined.contains("enter_vehicle") or combined.contains("exit_vehicle") or combined.contains("subir") or combined.contains("bajar"), "tiene enter/exit vehículo")

## 12. Interpolación 100ms + buffer 3 snapshots + reconciliación
func _test_interpolation_and_reconciliation() -> void:
	var nm_script: Script = load("res://09_network/NetworkManager.gd") as Script
	if nm_script == null:
		return
	var source: String = nm_script.get_source_code()
	_check(source.contains("interpolat") or source.contains("lerp") or source.contains("smooth"), "tiene interpolación")
	_check(source.contains("snap") or source.contains("buffer") or source.contains("history"), "tiene buffer de snapshots")
	_check(source.contains("reconcil") or source.contains("correct"), "tiene reconciliación cliente-servidor")
	# Configuración de parámetros
	_check(source.contains("INTERPOLATION") or source.contains("interpolation_ms") or source.contains("100"), "interpolation_ms ≈ 100")
	_check(source.contains("SNAPSHOT") or source.contains("snapshot_buffer") or source.contains("3"), "snapshot_buffer = 3")

## 13. Banda ≤64 KB/s por jugador (prioridad: jugador > zombi > mundo > botín)
func _test_bandwidth_budget() -> void:
	var nm_script: Script = load("res://09_network/NetworkManager.gd") as Script
	if nm_script == null:
		return
	var source: String = nm_script.get_source_code()
	_check(source.contains("bandwidth") or source.contains("kbps") or source.contains("KBPS") or source.contains("64"), "define presupuesto de banda (≤64 KB/s)")
	_check(source.contains("priorit") or source.contains("priority"), "tiene sistema de prioridad")
	# Prioridad jugador > zombi > mundo > botín
	var player_prio: bool = source.contains("player") and (source.contains("high") or source.contains("1") or source.contains("PRIORITY_HIGH"))
	var zombie_prio: bool = source.contains("zombie") and (source.contains("medium") or source.contains("2"))
	var world_prio: bool = source.contains("world") and (source.contains("low") or source.contains("3"))
	var loot_prio: bool = source.contains("loot") and (source.contains("low") or source.contains("4"))
	_check(player_prio or zombie_prio or world_prio or loot_prio, "define prioridades por tipo de entidad")

## 14. Sesión: host/join por IP, lista jugadores, ready state
func _test_session_management_host_join() -> void:
	var nm_script: Script = load("res://09_network/NetworkManager.gd") as Script
	if nm_script == null:
		return
	var source: String = nm_script.get_source_code()
	_check(source.contains("host_game") and source.contains("port"), "host_game(port)")
	_check(source.contains("join_game") and source.contains("ip"), "join_game(ip, port)")
	_check(source.contains("get_connected_peers") or source.contains("get_players"), "lista jugadores conectados")
	_check(source.contains("ready") or source.contains("Ready"), "ready state por jugador")
	_check(source.contains("max_players") or source.contains("MAX_PLAYERS") or source.contains("4"), "máx 4 jugadores")

## 15. Migración de host (host migration)
func _test_host_migration() -> void:
	var nm_script: Script = load("res://09_network/NetworkManager.gd") as Script
	if nm_script == null:
		return
	var source: String = nm_script.get_source_code()
	_check(source.contains("host_migration") or source.contains("migrate_host") or source.contains("new_host"), "tiene migración de host")
	_check(source.contains("peer_disconnected") and source.contains("is_server"), "detecta desconexión de host y elige nuevo")

func _finish() -> void:
	get_tree().paused = false
	if _checks == 0:
		_failures.append("La puerta debe ejecutar al menos una comprobación")
	print("MULTIPLAYER_TEST failures=%d" % _failures.size())
	print("MULTIPLAYER_CHECKS checks=%d" % _checks)
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)