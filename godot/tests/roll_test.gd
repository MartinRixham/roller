extends Node3D
## Headless sanity check: roll one die many times and print the tally.
##
##     godot --headless --fixed-fps 60 tests/roll_test.tscn
##
## Fails (exit 1) if any face never comes up or a roll never settles.

const DieScene := preload("res://scenes/die.tscn")
const ROLLS := 120
const TIMEOUT_TICKS := 600   # per roll, at 60 Hz physics

var _tally := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0}
var _done := 0
var _ticks := 0
var _total_ticks := 0
var _die: RigidBody3D


func _ready() -> void:
	seed(12345)
	_build_table()

	_die = DieScene.instantiate()
	_die.settled.connect(_on_settled)
	add_child(_die)
	_throw()


func _build_table() -> void:
	var table := StaticBody3D.new()
	add_child(table)

	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(8, 0.5, 8)
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(8, 8, 0.5)

	var floor_collider := CollisionShape3D.new()
	floor_collider.shape = floor_shape
	floor_collider.position = Vector3(0, -0.25, 0)
	table.add_child(floor_collider)

	for spot in [
		Vector3(0, 4, -3.5), Vector3(0, 4, 3.5),
		Vector3(-3.5, 4, 0), Vector3(3.5, 4, 0),
	]:
		var collider := CollisionShape3D.new()
		collider.shape = wall_shape
		collider.position = spot
		if spot.x != 0.0:
			collider.rotate_y(PI / 2.0)
		table.add_child(collider)


func _throw() -> void:
	_ticks = 0
	_die.roll(Vector3(randf_range(-1, 1), 4.0, randf_range(-1, 1)))


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks > TIMEOUT_TICKS:
		push_error("Roll %d never settled" % (_done + 1))
		quit(1)


func _on_settled(value: int) -> void:
	_tally[value] += 1
	_total_ticks += _ticks
	_done += 1

	if _done < ROLLS:
		_throw()
		return

	var missing: Array[int] = []
	for face in _tally:
		print("  %d: %s (%d)" % [face, "#".repeat(_tally[face]), _tally[face]])
		if _tally[face] == 0:
			missing.append(face)

	var expected := float(ROLLS) / 6.0
	print("%d rolls, expected ~%.1f per face" % [ROLLS, expected])
	print("engine: %s   mean settle: %.2fs" % [
		ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"),
		(float(_total_ticks) / ROLLS) / 60.0])

	if not missing.is_empty():
		push_error("Faces never rolled: %s" % str(missing))
		quit(1)

	print("OK: all six faces rolled")
	quit(0)


func quit(code: int) -> void:
	get_tree().quit(code)
