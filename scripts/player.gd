extends KinematicBody

#########
# Based on https://github.com/Zinglish/quake3-movement-unity3d/blob/master/CPMPlayer.cs
#########

var CMD = {
    "forwardMove" : 0,
    "rightMove" : 0,
    "upMove" : 0,
}

var playerView     # Camera
var playerViewYOffset = 0.6 # The height at which the camera is bound to
var xMouseSensitivity = 0.25
var yMouseSensitivity = 0.25

# Frame occuring factors
var gravity = 10.0
var friction = 6 #Ground friction

# Movement stuff
var moveSpeed = 7.0              # Ground move speed
var runAcceleration = 14.0         # Ground accel
var runDeacceleration = 10.0       # Deacceleration that occurs when running on the ground
var airAcceleration = 2.0          # Air accel
var airDecceleration = 2.0         # Deacceleration experienced when ooposite strafing
var airControl = 0.3               # How precise air control is
var sideStrafeAcceleration = 50.0  # How fast acceleration occurs to get up to sideStrafeSpeed when
var sideStrafeSpeed = 1.0          # What the max speed to generate when side strafing
var jumpSpeed = 20   #was 10             # The speed at which the character's up axis gains when hitting jump
var moveScale = 1.0

# Camera rotations
var yaw = 0.0
var pitch = 0.0

var moveDirectionNorm = Vector3()
var playerVelocity = Vector3()
var playerTopVelocity = 0.0

# Q3: players can queue the next jump just before he hits the ground
var wishJump = false

# Used to display real time fricton values
var playerFriction = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_process_input(true)
	set_fixed_process(true)

func _input(event):
	if event.type == InputEvent.MOUSE_MOTION:
		yaw = fmod(yaw - event.relative_x * xMouseSensitivity, 360)
		pitch = max(min(pitch - event.relative_y * yMouseSensitivity, 85), -85)
		set_rotation(Vector3(0, deg2rad(yaw), 0))
		get_node("Camera").set_rotation(Vector3(deg2rad(pitch), 0, 0))

	if event.is_action_pressed("jump"):
		wishJump = true
	if event.is_action_released("jump"):
		wishJump = false

func _fixed_process(delta):
	# Movement, here's the important part
	set_movement_dir()
	if isGrounded():
		GroundMove(delta)
	elif not isGrounded():
		AirMove(delta)

	move(playerVelocity * delta)

	# Calculate top velocity
	var udp = playerVelocity
	udp.y = 0.0
	if playerVelocity.length() > playerTopVelocity:
		playerTopVelocity = playerVelocity.length()

func isGrounded():
	if get_node("mid_ray").is_colliding():
		return true
	return false

func set_movement_dir():
	CMD.forwardMove = 0
	CMD.rightMove = 0
	var aim = get_global_transform().basis
	var direction = Vector3()
	if Input.is_action_pressed("move_forwards"):
		direction -= aim[2]
	if Input.is_action_pressed("move_backwards"):
		direction += aim[2]
	if Input.is_action_pressed("move_left"):
		direction -= aim[0]
	if Input.is_action_pressed("move_right"):
		direction += aim[0]
	CMD.forwardMove = direction.z
	CMD.rightMove = direction.x

func GroundMove(delta):
	var wishdir = Vector3()
	var wishvel = Vector3()

	# Do not apply friction if the player is queueing up the next jump
	if not wishJump:
	    ApplyFriction(1.0, delta)
	else:
	    ApplyFriction(0, delta)

	wishdir = Vector3(CMD.rightMove, 0, CMD.forwardMove)
	wishdir.normalized()
	moveDirectionNorm = wishdir

	var wishspeed = wishdir.length()
	wishspeed *= moveSpeed

	Accelerate(wishdir, wishspeed, runAcceleration, delta)

	# Reset the gravity velocity
	playerVelocity.y = 0

	if wishJump:
		playerVelocity.y = jumpSpeed
		wishJump = false

# Execs when the player is in the air
func AirMove(delta):
	var wishdir
	var wishvel = airAcceleration
	var accel

	wishdir =  Vector3(CMD.rightMove, 0, CMD.forwardMove)
	var wishspeed = wishdir.length()
	wishspeed *= moveSpeed

	wishdir.normalized()
	moveDirectionNorm = wishdir

	# CPM: Aircontrol
	var wishspeed2 = wishspeed
	if playerVelocity.dot(wishdir) < 0:
		accel = airDecceleration
	else:
		accel = airAcceleration
	# If the player is ONLY strafing left or right
	if CMD.forwardMove == 0 and CMD.rightMove != 0:
		if wishspeed > sideStrafeSpeed:
			wishspeed = sideStrafeSpeed
		accel = sideStrafeAcceleration

	Accelerate(wishdir, wishspeed, accel, delta)
	if airControl > 0:
		AirControl(wishdir, wishspeed2, delta)
	# !CPM: Aircontrol

	# Apply gravity
	playerVelocity.y -= gravity * delta


# Air control occurs when the player is in the air, it allows
# players to move side to side much faster rather than being
# 'sluggish' when it comes to cornering.
func AirControl(wishdir, wishspeed, delta):
	var zspeed
	var speed
	var dot
	var k
	var i

	# Can't control movement if not moving forward or backward
	if abs(CMD.forwardMove) < 0.001 or abs(wishspeed) < 0.001:
		return
	zspeed = playerVelocity.y
	playerVelocity.y = 0
	# Next two lines are equivalent to idTech's VectorNormalize()
	speed = playerVelocity.length()
	playerVelocity.normalized()

	dot = playerVelocity.dot(wishdir)
	k = 32
	k *= airControl * dot * dot * delta

	# Change direction while slowing down
	if dot > 0:
		playerVelocity.x = playerVelocity.x * speed + wishdir.x * k
		playerVelocity.y = playerVelocity.y * speed + wishdir.y * k
		playerVelocity.z = playerVelocity.z * speed + wishdir.z * k

		playerVelocity.normalized()
		moveDirectionNorm = playerVelocity

	playerVelocity.x *= speed
	playerVelocity.y = zspeed # Note this line
	playerVelocity.z *= speed
	printt("playerVelocity:", playerVelocity)

#Applies friction to the player, called in both the air and on the ground
func ApplyFriction(t, delta):
	var vec = playerVelocity # Equivalent to: VectorCopy()
	var vel
	var speed
	var newspeed
	var control
	var drop

	vec.y = 0.0
	speed = vec.length()
	drop = 0.0

	# Only if the player is on the ground then apply friction
	if isGrounded():
		if speed < runDeacceleration:
			control = runDeacceleration
		else:
			control = speed
		drop = control * friction * delta * t

	newspeed = speed - drop
	playerFriction = newspeed
	if newspeed < 0:
	    newspeed = 0
	if speed > 0:
	    newspeed /= speed

	playerVelocity.x *= newspeed
	playerVelocity.y *= newspeed
	playerVelocity.z *= newspeed

func Accelerate(wishdir, wishspeed, accel, delta):
	var addspeed
	var accelspeed
	var currentspeed

	currentspeed = playerVelocity.dot(wishdir)
	addspeed = wishspeed - currentspeed
	if addspeed <= 0:
		return
	accelspeed = accel * delta * wishspeed
	if accelspeed > addspeed:
		accelspeed = addspeed

	playerVelocity.x += accelspeed * wishdir.x
	playerVelocity.z += accelspeed * wishdir.z
