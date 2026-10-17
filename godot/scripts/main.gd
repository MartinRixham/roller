extends Node3D
## Spawns the dice, throws them on input and reports the total.

const DieScene := preload("res://scenes/die.tscn")

const MAX_DICE := 5
const DROP_HEIGHT := 4.0
const SPREAD := 1.2

@export var dice_count := 2

var _dice: Array[RigidBody3D] = []
var _pending := 0
var _results: Array[int] = []

@onready var _readout: Label = %Readout
@onready var _hint: Label = %Hint


func _ready() -> void:
	_spawn_dice(dice_count)
	_hint.text = "Space / click: roll    1-%d: dice count    Esc: quit" % MAX_DICE
	roll()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		return

	if event.is_action_pressed("ui_accept"):
		roll()
		return

	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		roll()
		return

	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var n := key.keycode - KEY_0
		if n >= 1 and n <= MAX_DICE:
			_spawn_dice(n)
			roll()


func roll() -> void:
	if _pending > 0:
		return

	_results.clear()
	_pending = _dice.size()
	_readout.text = "rolling..."

	for i in _dice.size():
		var offset := Vector3(
			(float(i) - (_dice.size() - 1) * 0.5) * SPREAD,
			DROP_HEIGHT + i * 0.6,
			randf_range(-0.5, 0.5)
		)
		_dice[i].roll(offset)


func _spawn_dice(count: int) -> void:
	for die in _dice:
		die.queue_free()
	_dice.clear()
	dice_count = count

	for i in count:
		var die: RigidBody3D = DieScene.instantiate()
		die.position = Vector3(i * SPREAD, DROP_HEIGHT, 0.0)
		die.settled.connect(_on_die_settled)
		add_child(die)
		_dice.append(die)

	_pending = 0


func _on_die_settled(value: int) -> void:
	_results.append(value)
	_pending -= 1
	if _pending > 0:
		return

	_results.sort()
	var total := 0
	var parts := PackedStringArray()
	for rolled in _results:
		total += rolled
		parts.append(str(rolled))

	if parts.size() == 1:
		_readout.text = parts[0]
	else:
		_readout.text = "%s  =  %d" % [" + ".join(parts), total]
