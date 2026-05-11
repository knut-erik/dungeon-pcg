extends Area3D
class_name SceneTransitionSocket

@export_file("*.tscn") var target_scene: String
@export var temp_spawn_height: float = 100.0 # TEMP fallback height
@export var require_interact: bool = false
@export var arrival_marker_path: NodePath = ^"ArrivalMarker"

var player_in_range: CharacterBody3D = null
var has_triggered := false
var _suppressed_bodies := {}


func _ready() -> void:
	add_to_group("scene_transition_socket")

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if require_interact and player_in_range != null:
		if Input.is_action_just_pressed("interact"):
			transition(player_in_range)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if _suppressed_bodies.has(body.get_instance_id()):
		return

	var player := body as CharacterBody3D
	if player == null:
		push_warning("SceneTransitionSocket: Player group body is not a CharacterBody3D.")
		return

	player_in_range = player

	if not require_interact:
		transition(player)


func _on_body_exited(body: Node) -> void:
	if body == player_in_range:
		player_in_range = null

	# Player must leave before this socket can trigger them again.
	_suppressed_bodies.erase(body.get_instance_id())


func transition(player: CharacterBody3D) -> void:
	if has_triggered:
		return

	has_triggered = true

	if target_scene.is_empty():
		push_warning("SceneTransitionSocket: No target_scene assigned.")
		has_triggered = false
		return

	SceneTransitionManager.transition_to(target_scene, player, temp_spawn_height)


func suppress_transition_for(player: CharacterBody3D) -> void:
	if player == null:
		return

	_suppressed_bodies[player.get_instance_id()] = true


func get_arrival_position(fallback_height: float) -> Vector3:
	var marker := get_node_or_null(arrival_marker_path) as Marker3D

	if marker != null:
		return marker.global_position

	# TEMP fallback if no ArrivalMarker exists.
	return global_position + Vector3(0.0, fallback_height, 0.0)
