extends CharacterBody2D
class_name Player


# PROPERTIES

const GRAVITY: float = 1024.0
const SPEED: float = 512.0
const JUMP_POWER: float = 512.0
const GROUND_ACCEL: float = 1024.0
const AIR_ACCEL: float = 512.0
const FRICTION: float = 1024.0
const SLIDE_FRICTION: float = 512.0
const AIR_DRAG: float = 512.0
const HIT_COOLDOWN_MS: int = 250

const CHARACTERS: Array[SpriteFrames] = [
	preload("res://resources/player/green_frames.tres"),
	preload("res://resources/player/pink_frames.tres"),
	preload("res://resources/player/yellow_frames.tres"),
	preload("res://resources/player/beige_frames.tres"),
	preload("res://resources/player/purple_frames.tres")
]

const ANIMATIONS: Array[StringName] = [
	&"default",
	&"walk",
	&"jump",
	&"fall",
	&"duck",
	&"hit"
]

enum State {
	IDLE,
	WALK,
	JUMP,
	FALL,
	DUCK,
	HIT
}

# Networking Properties
var peer_id: int = 1 # The peer that controls this player
var local: bool = true # If this player belongs to the local peer
var coins_collected: int = 0
var hit_time_ms: int = 0

# Determines which character to display as.
var character: int = 0:
	set(value):
		# Limit the value to the bounds of the CHARACTERS
		character = clampi(value, 0, CHARACTERS.size() - 1)
		
		# Update sprite to display as the new character
		var sprite: AnimatedSprite2D = $AnimatedSprite2D
		sprite.sprite_frames = CHARACTERS[character]
		sprite.play(ANIMATIONS[state])

# The current state the player is in.
var state: State = State.IDLE:
	set(value):
		# Limit the value to the bounds of the State
		state = clampi(value, 0, State.size() - 1) as State
		
		# Change sprite animation based on state
		$AnimatedSprite2D.play(ANIMATIONS[state])

# Which direction the player is facing.
var direction: float = 1.0:
	set(value):
		# Restrict to either exactly 1.0 or -1.0
		direction = 1.0 if value > 0.0 else -1.0
		
		#Flip sprite
		$AnimatedSprite2D.flip_h = direction < 0.0

var did_bounce: bool = false


# FUNCTIONS

func setup(id: int, character_select: int) -> void:
	name = str(id)
	character = character_select

func _enter_tree() -> void:
	# Set node authority
	peer_id = int(name)
	$ClientSynchronizer.set_multiplayer_authority(peer_id)
	local = peer_id == multiplayer.get_unique_id()

func _ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	# Only process physics if local
	if not local:
		return
	
	# Retrieve inputs as a convenient vector
	var input_v: Vector2 = Input.get_vector(
		&"move_left",
		&"move_right",
		&"move_up",
		&"move_down"
	)
	
	# Apply gravity
	velocity.y += GRAVITY * delta
	
	# Apply friction
	if is_zero_approx(input_v.x) and not is_zero_approx(velocity.x):
		var reduction: float = FRICTION if is_on_floor() else AIR_DRAG
		velocity.x = move_toward(velocity.x, 0.0, reduction * delta)
	
	# State machine
	match state:
		State.IDLE: _state_idle(input_v, delta)
		State.WALK: _state_walk(input_v, delta)
		State.JUMP: _state_jump(input_v, delta)
		State.FALL: _state_fall(input_v, delta)
		State.DUCK: _state_duck(input_v, delta)
		State.HIT: _state_hit(input_v, delta)
	
	# Reset bounce
	if is_on_floor():
		did_bounce = false
	
	# Apply physics
	move_and_slide()


# RPC FUNCTION

@rpc("authority", "call_local", "reliable")
func teleport(new_pos: Vector2) -> void:
	velocity = Vector2.ZERO
	global_position = new_pos
	state = State.IDLE


# PUBLIC HELPER FUNCTIONS

func collect_coins(amount: int) -> void:
	coins_collected += amount

@rpc("any_peer", "call_local", "reliable")
func jump() -> void:
	if state == State.JUMP:
		return
	
	state = State.JUMP
	velocity.y = -JUMP_POWER
	
	var tween_speed := 0.1
	var tween = create_tween()
	tween.tween_property(
		self,
		"scale",
		Vector2(1.25, 0.75),
		tween_speed
	)
	
	tween.tween_property(
		self,
		"scale",
		Vector2(0.85, 1.15),
		tween_speed
	)
	
	tween.tween_property(
		self,
		"scale",
		Vector2.ONE,
		tween_speed
	)

func duck() -> void:
	if state == State.DUCK:
		return
	
	if did_bounce:
		return
	
	if not is_on_floor():
		velocity.x = 0
	
	state = State.DUCK
	velocity.y += JUMP_POWER

# FIXME: - hit_by(Node2D) not Vector2, had to change to fit hit_direction below.
func hit_by(other: Vector2) -> void:
	if state == State.HIT:
		return
	
	hit_time_ms = Time.get_ticks_msec()
	state = State.HIT
	velocity = global_position.direction_to(other) * -GRAVITY
	direction = roundf(velocity.x)


# INTERNAL HELPER FUNCTIONS

func _check_fall() -> bool:
	if not is_on_floor() and velocity.y > 0.0:
		state = State.FALL
		return true
	
	return false

func _check_jump(input_v: Vector2) -> bool:
	if input_v.y < 0.0 and is_on_floor():
		jump.rpc()
		return true
	
	return false

func _check_duck(input_v: Vector2) -> bool:
	if input_v.y > 0.0:
		duck()
		return true
	
	return false

func _check_walk(input_v: Vector2) -> bool:
	if not is_zero_approx(input_v.x):
		state = State.WALK
		return true
	
	return false

func _check_idle(input_v: Vector2) -> bool:
	if is_zero_approx(input_v.x):
		state = State.IDLE
		return true
	
	return false

func _ground_controls(input_v: Vector2, delta: float) -> void:
	# Face input direction
	if not is_zero_approx(input_v.x):
		direction = roundf(input_v.x)
	
	# Accelerate
	velocity.x = move_toward(
		velocity.x,
		SPEED * input_v.x,
		GROUND_ACCEL * delta
	)

func _air_controls(input_v: Vector2, delta: float) -> void:
	if not is_zero_approx(input_v.x):
		direction = roundf(input_v.x)
	
	velocity.x = move_toward(
		velocity.x,
		SPEED * input_v.x,
		AIR_ACCEL * delta
	)

func _hit_stop(pause: float = 0.0) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(pause, true, false, true).timeout
	Engine.time_scale = 1


# STATE FUNCTIONS

func _state_idle(input_v: Vector2, delta: float) -> void:
	if _check_fall() \
	or _check_walk(input_v) \
	or _check_jump(input_v) \
	or _check_duck(input_v):
		return
	
	_ground_controls(input_v, delta)

func _state_walk(input_v: Vector2, delta: float) -> void:
	if _check_fall() \
	or _check_jump(input_v) \
	or _check_duck(input_v) \
	or _check_idle(input_v):
		return
	
	_ground_controls(input_v, delta)


func _state_jump(input_v: Vector2, delta: float) -> void:
	if _check_fall() \
	or _check_duck(input_v):
		return
	
	_air_controls(input_v, delta)

func _state_fall(input_v: Vector2, delta: float) -> void:
	if _check_duck(input_v):
		return
	
	# Control in air
	if not is_on_floor():
		_air_controls(input_v, delta)
		return
	
	# Revert to IDLE on the ground
	state = State.IDLE

func _state_duck(input_v: Vector2, delta: float) -> void:
	# Slide
	velocity.x = move_toward(velocity.x, 0.0, SLIDE_FRICTION * delta)
	
	if not is_on_floor() \
	or _check_duck(input_v):
		return
	
	state = State.IDLE

func _state_hit(_input_v: Vector2, _delta: float) -> void:
	# Wait for cooldown
	var now_ms: int = Time.get_ticks_msec()
	
	if now_ms - hit_time_ms < HIT_COOLDOWN_MS:
		return
	
	state = State.IDLE


# SIGNAL FUNCTIONS

func _on_hit_detector_body_entered(body: Node2D) -> void:
	# Only process hits if local
	if not local:
		return
	
	# Detect enemies
	if body is Enemy:
		# Skip if HIT state
		if state == State.HIT:
			return
		
		# Determine if above or below the enemy
		if global_position.y < body.global_position.y - Enemy.HEIGHT:
			# Above, bounce and destroy
			did_bounce = true
			jump.rpc()
			_hit_stop()
			
			if multiplayer.is_server():
				body.destroy()
			else:
				body.destroy.rpc_id(1)
		else:
			# Below, hurt the player
			var hit_direction := global_position.direction_to(
				body.global_position
			)
			
			# FIXME: - hit_by(Node2D) not Vector2, changed above to fit this.
			hit_by(hit_direction)
