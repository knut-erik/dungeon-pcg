# Test camera that automatically deletes itself if not part of the root scene - great for debugging individual scenes that will later be instantiated!
extends Node3D

@export var mouse_sensitivity := 0.002
@export var max_look_angle := 90.0

var rotation_x := 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# 'owner' refers to the root node of the packed scene this camera was saved in (the Dungeon).
	# If the Dungeon is not the main active scene, delete this camera.
	if owner != get_tree().current_scene:
		queue_free()

func _input(event):
	if event is InputEventMouseMotion:
		# Horizontal (Y axis rotation)
		rotate_y(-event.relative.x * mouse_sensitivity)

		# Vertical (X axis rotation)
		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_x = clamp(rotation_x, deg_to_rad(-max_look_angle), deg_to_rad(max_look_angle))

		rotation.x = rotation_x
		
func _physics_process(_delta: float) -> void:

	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	position += direction * 0.45
