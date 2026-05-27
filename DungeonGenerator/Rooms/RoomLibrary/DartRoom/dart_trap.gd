extends Node3D

@export var shot_delay = 1.5
@export var dart_scene : PackedScene
@export var dart_speed : float
var dart_respawn_point : Vector3

@onready var shooter = $Shooter
@onready var timer = $Timer
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	timer.wait_time = shot_delay


func _on_timer_timeout() -> void:
	var dart = dart_scene.instantiate()
	dart.respawn_point = dart_respawn_point
	dart.rotation = global_rotation
	dart.position = shooter.global_position
	dart.speed = 10
	get_tree().current_scene.add_child(dart)
