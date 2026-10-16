extends Area2D
class_name Coin


# PROPERTIES

var collected: bool = false#:
	#set(value):
		#collected = value
		#
		## Instead of queue_free upon collection, we simply hide it and prevent
		## detection; it's easier when building levels because you then have to
		## use MultiplayerSpawner which apparently complicates things as we will
		## see...
		#visible = !value
		#
		#set_deferred(
			#&"process_mode",
			#Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
		#)


# FUNCTIONS

func _on_body_entered(body: Node2D) -> void:
	if not is_multiplayer_authority():
		return
	
	if collected:
		return
	
	if body is Player:
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
		if candidate.peer_id == peer_id:
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
