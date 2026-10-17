extends Node
# Dev-only: run the sim briefly and save a frame, to eyeball the model.
#   godot --display-driver x11 tests/shot.tscn -- /path/out.png
func _ready() -> void:
	add_child(load("res://scenes/main.tscn").instantiate())
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "shot.png"
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	get_tree().quit()
