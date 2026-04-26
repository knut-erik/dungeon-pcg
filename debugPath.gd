@tool
extends Node

@export var noise: FastNoiseLite
@export var size: int = 512
@export var save_path: String = "res://centerline_debug.png"

func _ready() -> void:
	#if not Engine.is_editor_hint():
	#	push_warning("Fuck You")
	#	return
	if noise == null:
		push_warning("Assign a FastNoiseLite resource to 'noise' in the inspector.")
		return

	var img: Image = Image.create(size, size, false, Image.FORMAT_RGB8)
	# No lock/unlock in Godot 4; set_pixel is safe to call directly
	for y in size:
		for x in size:
			var wx := float(x - size / 2)
			var wy := float(y - size / 2)
			var v := noise.get_noise_2d(wx, wy) # [-1,1]
			var c : float = clamp((v + 1.0) * 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(c, c, c))
	var err := img.save_png(save_path)
	if err == OK:
		print("Saved centerline image to ", save_path)
	else:
		push_error("Failed to save image: %s" % err)
