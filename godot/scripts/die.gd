extends RigidBody3D
## A single d6. Rolls itself, then reports the face pointing up.

signal settled(value: int)

## Local axis -> the number printed on that face, as authored in Blender.
## The glTF export is Y-up, so the Blender +Z face (1) becomes +Y here.
const FACE_VALUES := {
	Vector3.UP: 1,
	Vector3.FORWARD: 2,
	Vector3.RIGHT: 3,
	Vector3.LEFT: 4,
	Vector3.BACK: 5,
	Vector3.DOWN: 6,
}

const THROW_SPEED := Vector2(1.5, 3.5)   ## min/max horizontal launch speed
const THROW_LIFT := Vector2(2.0, 4.5)    ## min/max upward launch speed
const SPIN := 14.0                       ## max random angular velocity
const REST_SPEED := 0.05                 ## below this the die counts as still
const REST_SPIN := 0.1
const REST_FRAMES := 8                   ## consecutive still frames before settling

var _still_frames := 0
var _rolling := false


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4


## Teleport to `from`, scramble the orientation and throw.
func roll(from: Vector3) -> void:
	var angle := randf() * TAU
	var speed := randf_range(THROW_SPEED.x, THROW_SPEED.y)

	var orientation := Basis.from_euler(
		Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	)
	# Set the body state directly so the die does not streak in from its old spot.
	var target := Transform3D(orientation, from)
	PhysicsServer3D.body_set_state(
		get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, target
	)
	global_transform = target

	linear_velocity = Vector3(
		cos(angle) * speed,
		randf_range(THROW_LIFT.x, THROW_LIFT.y),
		sin(angle) * speed
	)
	angular_velocity = Vector3(
		randf_range(-SPIN, SPIN),
		randf_range(-SPIN, SPIN),
		randf_range(-SPIN, SPIN)
	)

	sleeping = false
	_still_frames = 0
	_rolling = true


## The face value currently pointing up, 0 if the die is badly tilted
## (cocked on an edge), which _physics_process never settles on.
func top_face() -> int:
	var best_value := 0
	var best_dot := 0.7   # ~45 degrees of tilt tolerance

	for axis: Vector3 in FACE_VALUES:
		var dot := (global_transform.basis * axis).dot(Vector3.UP)
		if dot > best_dot:
			best_dot = dot
			best_value = FACE_VALUES[axis]

	return best_value


func _physics_process(_delta: float) -> void:
	if not _rolling:
		return

	if linear_velocity.length() < REST_SPEED and angular_velocity.length() < REST_SPIN:
		_still_frames += 1
	else:
		_still_frames = 0

	if _still_frames < REST_FRAMES:
		return

	var value := top_face()
	if value == 0:
		# Cocked die: nudge it and let it fall flat.
		apply_torque_impulse(Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
		apply_central_impulse(Vector3.UP * 1.5)
		_still_frames = 0
		return

	_rolling = false
	settled.emit(value)
