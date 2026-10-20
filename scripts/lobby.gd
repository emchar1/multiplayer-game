extends Node2D
class_name Lobby


# PROPERTIES

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const MAX_PLAYERS = 5
const DEFAULT_PORT = 47218 # Port number doesn't matter, just pick something

# Flag to check if server is self-hosted or uses a hosting service.
var headless_mode: bool = DisplayServer.get_name() == "headless"

var level: Level = null
var level_index: int = -1
var available_characters: Array[int] = []


# FUNCTIONS

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Listen to multiplayer signals
	# The following emit on both clients and servers
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	# The rest only emit for clients
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Start server on headless_mode
	if headless_mode:
		start_enet_server()
		#start_websocket_server() # Optionally start as WebSocket server.
	
	# Prepare available_characters indices
	for index: int in Player.CHARACTERS.size():
		available_characters.append(index)


# NETWORK FUNCTIONS

func _start_server_common() -> void:
	if headless_mode:
		return
	
	load_level(0) # start the first level
	spawn_player(1) # server always has ID = 1!

func start_enet_server(port: int = DEFAULT_PORT) -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_server(port, MAX_PLAYERS)
	
	multiplayer.multiplayer_peer = peer
	
	_start_server_common()

func start_enet_client(address: String, port: int = DEFAULT_PORT) -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_client(address, port)
	
	multiplayer.multiplayer_peer = peer

func start_websocket_server(port: int = DEFAULT_PORT) -> void:
	var tls_options: TLSOptions = _create_server_tls_options()
	
	if tls_options == null:
		push_error("Failed to configure Websocket TLS.")
		return
	
	var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
	var error: Error = peer.create_server(port, "*", tls_options)
	print("create_server: ", error_string(error))
	
	if error != OK:
		push_error("Failed to start WebSocket server: " + error_string(error))
		return
	
	multiplayer.multiplayer_peer = peer
	_start_server_common()

func start_websocket_client(url: String) -> void:
	print("Creating WebSocket client: ", url)
	
	var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
	var error := peer.create_client(url)
	
	print("create_client result: ", error, " (", error_string(error), ")")
	
	multiplayer.multiplayer_peer = peer
	print("WebSocket client started; waiting for connection.")

# This is needed to allow encrypted hosting...
func _create_server_tls_options() -> TLSOptions:
	var certificate: X509Certificate = X509Certificate.new()
	var key: CryptoKey = CryptoKey.new()
	var cert_error: Error = certificate.load(
		"res://certs/fullchain.pem"
	)
	
	if cert_error != OK:
		push_error("Failed to load TLS certificate: " \
		+ error_string(cert_error))
		return null
	
	var key_error: Error = key.load(
		"res://certs/privkey.pem"
	)
	
	if key_error != OK:
		push_error("Failed to load TLS private key: " \
		+ error_string(key_error))
		return null
	
	return TLSOptions.server(key, certificate)


# NETWORK EVENT FUNCTIONS

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	# Load the first level if needed. Added this for headless_mode.
	if level == null:
		load_level(0)
	
	# Handle player spawning if hosting
	spawn_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	# Unload the level if this is the last player. Added for headless_mode.
	if get_player_count() <= 1:
		unload_level()
	
	# Handle player de-spawning if hosting
	remove_player(peer_id)

func _on_connected_to_server() -> void:
	print("CONNECTED TO SERVER")
	pass

func _on_connection_failed() -> void:
	print("CONNECTION FAILED")
	pass

func _on_server_disconnected() -> void:
	print("SERVER DISCONNECTED")
	pass


# LEVEL MANAGEMENT FUNCTIONS

func load_level(new_level_index: int) -> void:
	# Get level path
	var level_spawner: MultiplayerSpawner = $LevelSpawner
	
	if new_level_index < 0 \
	or new_level_index >= level_spawner.get_spawnable_scene_count():
		push_error("Level index out of bounds")
		return
	
	var level_path: String = level_spawner.get_spawnable_scene(new_level_index)
	
	# Free previous level
	if level:
		level.queue_free()
	
	# Load new level
	var level_scn: PackedScene = load(level_path)
	level = level_scn.instantiate()
	level_index = new_level_index
	$Level.add_child.call_deferred(level, true)
	
	# Listen to level events
	level.goal_reached.connect(_on_goal_reached, ConnectFlags.CONNECT_ONE_SHOT)
	
	# Teleport players to spawn point
	teleport_players(level.get_spawn_position())

func unload_level() -> void:
	if level:
		level.queue_free()
	
	level = null
	level_index = -1

func next_level() -> void:
	load_level(level_index + 1)

func is_final_level() -> bool:
	var level_spawner: MultiplayerSpawner = $LevelSpawner
	return level_index == level_spawner.get_spawnable_scene_count() - 1


# LEVEL EVENT FUNCTIONS

func _on_goal_reached(_player: Player) -> void:
	# Detect when a player reaches the goal and switch levels
	if is_final_level():
		load_level(1)
		return
	
	next_level()


# PLAYER MANAGEMENT FUNCTIONS

func get_player(peer_id: int) -> Player:
	for child: Node in $Players.get_children():
		if child is Player and child.peer_id == peer_id:
			return child
	
	return null

func get_players() -> Array[Player]:
	var players: Array[Player] = []
	
	for child: Node in $Players.get_children():
		if child is Player:
			players.append(child)
	
	return players

func get_player_count() -> int:
	return get_players().size()

func spawn_player(peer_id: int) -> void:
	if available_characters.size() <= 0:
		return
	
	# Prepare new player
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.character = available_characters.pop_front()
	
	# Add player to level and teleport to spawn position
	$Players.add_child(player)
	
	player.teleport.rpc(level.get_spawn_position())

func remove_player(peer_id: int) -> void:
	# Find player node
	var player = get_player(peer_id)
	
	if player:
		# Return player to available list
		available_characters.append(player.character)
		
		# Free the player
		player.queue_free()

func teleport_players(new_pos: Vector2) -> void:
	for player: Player in get_players():
		player.teleport.rpc(new_pos)
