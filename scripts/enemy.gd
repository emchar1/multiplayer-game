extends CharacterBody2D
class_name Enemy


# PROPERTIES

const GRAVITY: float = 1024.0
const SPEED: float = 256.0
const ACCEL: float = 512.0
const AIR_DRAG: float = 512.0
const HEIGHT: float = 40.0
const TURN_COOLDOWN_MS: int = 250

var turn_time_ms: int = 0

# Which direction the enemy is facing.
var direction: float = 1.0:
	set(value):
		# Restrict to either exactly 1.0 or -1.0
		direction = 1.0 if value > 0.0 else -1.0
		
		#Flip sprite
		$AnimatedSprite2D.flip_h = direction > 0.0

var destroyed: bool = false


# FUNCTIONS

func _physics_process(delta: float) -> void:
	# Only process if we are the host
	if not is_multiplayer_authority():
		return
	
	# Apply gravity
	velocity.y += GRAVITY * delta
	
	# Walk if on floor, otherwise apply air drag
	if is_on_floor():
		velocity.x = move_toward(velocity.x, SPEED * direction, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, AIR_DRAG * delta)
	
	# Apply physics
	move_and_slide()
	
	# Turn around when a wall is encountered
	if is_on_wall():
		var now_ms: int = Time.get_ticks_msec()
		
		if now_ms - turn_time_ms >= TURN_COOLDOWN_MS:
			turn_time_ms = now_ms
			direction *= -1.0


# PUBLIC HELPER FUNCTIONS

@rpc("any_peer", "call_local", "reliable")
func destroy() -> void:
	destroyed = true
	velocity = Vector2.ZERO
	
	_destroy_animation.rpc()

@rpc("authority", "call_local", "reliable")
func _destroy_animation():
	var tween_speed := 0.3
	var tween = create_tween()
	
	tween.tween_property(
		self,
		"scale",
		Vector2(2, 0),
		tween_speed
	)
	
	tween.parallel().tween_property(
		self,
		"position:y",
		position.y + 30,
		tween_speed
	)
	
	tween.tween_property(
		self,
		"scale",
		Vector2(0, 2),
		tween_speed / 2
	)
	
	tween.parallel().tween_property(
		self,
		"position",
		position - Vector2(30, 30),
		tween_speed / 2
	)
	
	tween.tween_callback(_destroy_cleanup)

func _destroy_cleanup():
	visible = false
	set_deferred(&"process_mode", Node.PROCESS_MODE_DISABLED)

# That's it! enemy/player handling will happen on the player side because it's
# easier than the other way around due to multiplayer properties.
