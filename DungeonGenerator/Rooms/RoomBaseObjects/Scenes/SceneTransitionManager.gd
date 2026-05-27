extends Node

var _pending_player: CharacterBody3D = null
var _pending_temp_spawn := false
var _temp_spawn_height := 100.0
var _delay_before_spawn := 3.0 # TEMP wait for terrain generation
var _retry_timer := 0.0
var _retries_left := 40
var _transitioning := false

func _ready() -> void:
	print("SceneTransitionManager loaded at: ", get_path())


func transition_to(target_scene: String, player: CharacterBody3D, temp_spawn_height: float = 100.0) -> void:
	if _transitioning:
		return
	
	if player == null:
		push_warning("SceneTransitionManager: No player passed into transition.")
		return

	_transitioning = true
	_pending_player = player
	_temp_spawn_height = temp_spawn_height

	call_deferred("_deferred_transition_to", target_scene)


func _deferred_transition_to(target_scene: String) -> void:
	var tree := get_tree()

	if _pending_player == null or not is_instance_valid(_pending_player):
		push_warning("SceneTransitionManager: Player was freed before transition.")
		_transitioning = false
		return

	print("Changing scene to: ", target_scene)

	var source_scene_root := _find_scene_root_containing(_pending_player)

	# Preserve the Agent before destroying the current scene.
	_pending_player.reparent(tree.root, true)

	_pending_player.velocity = Vector3.ZERO # TEMP remove after proper spawn handling
	_pending_player.global_position = Vector3(0.0, _temp_spawn_height, 0.0) # TEMP remove after proper spawn point setup

	var err := tree.change_scene_to_file(target_scene)
	if err != OK:
		push_error("SceneTransitionManager: Failed to load scene: " + target_scene)
		_transitioning = false
		return

	# change_scene_to_file only frees get_tree().current_scene. If PCG_World was
	# added manually by the menu, it is not current_scene and must be freed here.
	if source_scene_root != null and source_scene_root != tree.current_scene and is_instance_valid(source_scene_root):
		source_scene_root.queue_free()

	_pending_temp_spawn = true
	_delay_before_spawn = 3.0 # TEMP wait for terrain generation
	_retry_timer = 0.0
	_retries_left = 40


func _process(delta: float) -> void:
	if not _pending_temp_spawn:
		return

	if _pending_player == null or not is_instance_valid(_pending_player):
		_pending_temp_spawn = false
		_transitioning = false
		push_warning("SceneTransitionManager: Preserved player no longer exists.")
		return

	if _delay_before_spawn > 0.0:
		_delay_before_spawn -= delta
		return

	_retry_timer -= delta
	if _retry_timer > 0.0:
		return

	_retry_timer = 0.25
	_retries_left -= 1

	var current := get_tree().current_scene
	if current == null:
		print("TEMP spawn retry: current_scene not ready. Retries left: ", _retries_left)
		return

	var destination_socket := _get_destination_socket(current)
	var spawn_position := Vector3(0.0, _temp_spawn_height, 0.0) # TEMP fallback

	if destination_socket != null:
		destination_socket.suppress_transition_for(_pending_player)
		spawn_position = destination_socket.get_arrival_position(_temp_spawn_height)
	else:
		push_warning("SceneTransitionManager: No destination SceneTransitionSocket found. Using fallback spawn height.")

	if _pending_player.get_parent() != current:
		_pending_player.reparent(current, true)

	_pending_player.velocity = Vector3.ZERO # TEMP remove after proper spawn handling
	_pending_player.global_position = spawn_position

	print("TEMP spawn: reattached player to new scene.")
	print("TEMP spawn position: ", spawn_position)

	_pending_temp_spawn = false
	_transitioning = false


func _get_destination_socket(current_scene: Node) -> SceneTransitionSocket:
	var sockets := get_tree().get_nodes_in_group("scene_transition_socket")

	for socket in sockets:
		if socket is SceneTransitionSocket and current_scene.is_ancestor_of(socket):
			return socket as SceneTransitionSocket

	return null


func _find_scene_root_containing(node: Node) -> Node:
	var tree := get_tree()
	if tree == null or node == null:
		return null

	var current := node
	var scene_root := current

	while current.get_parent() != null and current.get_parent() != tree.root:
		current = current.get_parent()
		scene_root = current

	if scene_root == self:
		return null

	return scene_root
