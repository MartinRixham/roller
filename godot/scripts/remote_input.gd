extends Node
## Remote control over TCP, for driving the exported game from an outside test.
##
##     dice-sim.x86_64 --headless --fixed-fps 60 -- --remote-input=127.0.0.1:9000
##
## Inert unless --remote-input is passed. Connects out to HOST:PORT (so the
## test listens first and there is no port race) and reads one command per
## line, answering each with `ok`, `value <json>` or `error <why>`. The game
## starts paused so nothing happens before the test has set up its watches:
##
##     resume              unpause the game
##     key <name>          press and release, name as in OS.find_keycode_from_string
##     click [x y]         left mouse press and release
##     wait <frames>       answer after that many physics frames
##     get <node> <prop>   property of a node, path relative to the current scene
##     watch <signal>      push `signal <name> <json args>` whenever the scene emits it
##     quit
##
## Knows nothing about dice; a test makes sense of what it reads back.

const FLAG := "--remote-input="

var _peer: StreamPeerTCP
var _inbox := ""
var _outbox := PackedStringArray()
var _commands := PackedStringArray()
var _wait_frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var address := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(FLAG):
			address = arg.trim_prefix(FLAG)
	if address.is_empty():
		set_physics_process(false)
		return

	get_tree().paused = true
	var host := address.get_slice(":", 0)
	var port := address.get_slice(":", 1).to_int()
	_peer = StreamPeerTCP.new()
	var err := _peer.connect_to_host(host, port)
	if err != OK:
		push_error("remote input: cannot connect to %s (%s)" % [address, error_string(err)])
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	_peer.poll()
	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTING:
			return
		StreamPeerTCP.STATUS_CONNECTED:
			pass
		_:
			# The test has gone away, so nobody is driving: stop.
			get_tree().quit()
			return

	var available := _peer.get_available_bytes()
	if available > 0:
		_inbox += _peer.get_utf8_string(available)
	while "\n" in _inbox:
		var line := _inbox.get_slice("\n", 0).strip_edges()
		_inbox = _inbox.substr(_inbox.find("\n") + 1)
		if not line.is_empty():
			_commands.append(line)

	if _wait_frames > 0:
		_wait_frames -= 1
		if _wait_frames == 0:
			_send("ok")
	while _wait_frames == 0 and not _commands.is_empty():
		var command := _commands[0]
		_commands.remove_at(0)
		_run(command)

	# Lines queued before the connection came up (e.g. an early signal) go now.
	for line in _outbox:
		_peer.put_data((line + "\n").to_utf8_buffer())
	_outbox.clear()


func _run(command: String) -> void:
	var words := command.split(" ", false)
	var args := words.slice(1)
	match words[0]:
		"key":
			var keycode := OS.find_keycode_from_string(" ".join(args))
			if keycode == KEY_NONE:
				_send("error unknown key %s" % " ".join(args))
				return
			for pressed in [true, false]:
				var event := InputEventKey.new()
				event.keycode = keycode
				event.physical_keycode = keycode
				event.pressed = pressed
				Input.parse_input_event(event)
			_send("ok")
		"click":
			for pressed in [true, false]:
				var event := InputEventMouseButton.new()
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = pressed
				if args.size() == 2:
					event.position = Vector2(args[0].to_float(), args[1].to_float())
				Input.parse_input_event(event)
			_send("ok")
		"wait":
			_wait_frames = maxi(1, args[0].to_int()) if args.size() == 1 else 1
		"get":
			var scene := get_tree().current_scene
			var node := scene.get_node_or_null(args[0]) if args.size() == 2 else null
			if node == null:
				_send("error no node for: %s" % command)
				return
			_send("value " + JSON.stringify(node.get(args[1])))
		"watch":
			var scene := get_tree().current_scene
			var signal_name := args[0] if args.size() == 1 else ""
			if not scene.has_signal(signal_name):
				_send("error no signal for: %s" % command)
				return
			scene.connect(signal_name, func(...values: Array) -> void:
				_send("signal %s %s" % [signal_name, JSON.stringify(values)]))
			_send("ok")
		"resume":
			get_tree().paused = false
			_send("ok")
		"quit":
			_send("ok")
			get_tree().quit()
		_:
			_send("error unknown command: %s" % command)


func _send(line: String) -> void:
	_outbox.append(line)
