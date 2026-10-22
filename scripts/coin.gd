extends Area2D
class_name Coin


# PROPERTIES

var collected: bool = false


# FUNCTIONS

func _on_body_entered(body: Node2D) -> void:
	if not is_multiplayer_authority():
		return
	
	if collected:
		return
	
	if body is Player:
		var lobby := get_node_or_null("/root/Lobby") as Lobby
		
		if lobby == null:
			push_error("Coin: Could not find Lobby.")
			return
		
		lobby.register_coin_collected(str(name))
		
		collected = true
		body.collect_coins(1)
		_play_collected_animation.rpc(body.peer_id)

# The MultiplayerSynchronizer replicates the collected state.
# The RPC explicitly triggers the collection animation on every peer.
@rpc("authority", "call_local", "reliable")
func _play_collected_animation(peer_id: int) -> void:
	var start_position := global_position
	var players = get_tree().get_nodes_in_group("player")
	var player: Player
	
	for candidate in players:
		if candidate is Player and candidate.peer_id == peer_id:
			player = candidate
			break
	
	if not is_instance_valid(player):
		push_warning("Coin: player.peer_id ", peer_id, " is invalid.")
		return
	
	var tween_speed: float = 0.5
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	
	tween.tween_method(
		func(progress: float) -> void:
			if not is_instance_valid(player):
				return
			
			global_position = start_position.lerp(
				player.global_position,
				progress
			),
		0.0,
		1.0,
		tween_speed
	)
	
	tween.parallel().tween_property(
		self,
		"scale",
		Vector2(2, 2),
		tween_speed
	)
	
	tween.tween_property(
		self,
		"scale",
		Vector2.ZERO,
		tween_speed / 2
	)
	
	tween.tween_callback(_collected_cleanup)

func _collected_cleanup():
	visible = false
	set_deferred(&"process_mode", Node.PROCESS_MODE_DISABLED)
