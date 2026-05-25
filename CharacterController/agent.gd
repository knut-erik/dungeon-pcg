extends CharacterBody3D
class_name PlayerController3D

enum GameState {
	PLAYING,
	DEAD,
	PAUSED,
	WON,
	LOST
}

@export_category("Movement")
@export var move_speed: float = 5.5
@export var ground_acceleration: float = 28.0
@export var air_acceleration: float = 8.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.0025

@export_category("Stats")
@export var max_health: int = 100
@export var health: int = 100
@export var money: int = 0
@export var game_state: GameState = GameState.PLAYING

@export_category("Interaction")
@export var interact_distance: float = 3.0
@export var debug_raycast_metadata := true # To stop spam - potentially only update when object changes?
var _last_debug_looked_object: Node = null
var _last_debug_looked_tags: Array[String] = []

@onready var head: Node3D = $Head
@onready var interact_ray: RayCast3D = $Head/InteractRay

@onready var agent_controller: AIController3D = $AIController3D
var sync_node : Sync

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var use_agent_control: bool = false

var agent_action := {
	"move_x": 0.0,
	"move_z": 0.0,
	"jump": false,
	"interact": false,
	"look_yaw": 0.0,
	"look_pitch": 0.0
}

var looked_object: Node = null
var looked_tags: Array[String] = []


func _ready() -> void:
	sync_node = get_node_or_null("/root/PcgWorld/Sync")
	if not sync_node:
		push_warning("Sync node not found - training toggle disabled")
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if interact_ray:
		interact_ray.enabled = true
		interact_ray.target_position = Vector3(0.0, 0.0, -interact_distance)


func _input(event: InputEvent) -> void:
	if use_agent_control:
		
		return

	if event is InputEventMouseMotion and game_state == GameState.PLAYING:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if sync_node and sync_node.control_mode == Sync.ControlModes.TRAINING:
		if Input.is_action_just_pressed("toggle_control"):
			if agent_controller.heuristic == "human":
				agent_controller.heuristic = "model"
			else:
				agent_controller.heuristic = "human"

	use_agent_control = agent_controller.heuristic != "human"
	set_agent_action(agent_controller.input_actions)
	
	_update_looked_object()

	if game_state != GameState.PLAYING:
		velocity.x = move_toward(velocity.x, 0.0, ground_acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_acceleration * delta)
		_apply_gravity(delta)
		move_and_slide()
		return

	var action := agent_action if use_agent_control else _read_human_action()

	_apply_look_action(action)
	_apply_movement_action(action, delta)

	if action.get("interact", false):
		_try_interact()


func _read_human_action() -> Dictionary:
	var move_input := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	return {
		"move_x": move_input.x,
		"move_z": move_input.y,
		"jump": Input.is_action_just_pressed("jump"),
		"interact": Input.is_action_just_pressed("interact"),
		"look_yaw": 0.0,
		"look_pitch": 0.0
	}


func set_agent_action(action: Dictionary) -> void:
	agent_action = action


func _apply_look_action(action: Dictionary) -> void:
	if not use_agent_control:
		return

	var yaw := float(action.get("look_yaw", 0.0))
	var pitch := float(action.get("look_pitch", 0.0))

	rotate_y(-yaw * 0.05)
	head.rotate_x(-pitch * 0.05)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))


func _apply_movement_action(action: Dictionary, delta: float) -> void:
	_apply_gravity(delta)

	if bool(action.get("jump", false)) and is_on_floor():
		velocity.y = jump_velocity

	var local_input := Vector3(
		float(action.get("move_x", 0.0)),
		0.0,
		float(action.get("move_z", 0.0))
	)

	local_input = local_input.limit_length(1.0)

	var world_direction := (global_transform.basis * local_input)
	world_direction.y = 0.0
	world_direction = world_direction.normalized() if world_direction.length() > 0.001 else Vector3.ZERO

	var target_velocity := world_direction * move_speed
	var accel := ground_acceleration if is_on_floor() else air_acceleration

	velocity.x = move_toward(velocity.x, target_velocity.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, accel * delta)

	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


func _update_looked_object() -> void:
	looked_object = null
	looked_tags.clear()

	if not interact_ray:
		return

	interact_ray.force_raycast_update()

	if not interact_ray.is_colliding():
		return

	var collider := interact_ray.get_collider()

	if collider is Node:
		var node := collider as Node
		looked_object = _find_agent_object(node)
		looked_tags = _get_rl_tags_from_hierarchy(node)

		if looked_object != null and debug_raycast_metadata:
				var object_changed := looked_object != _last_debug_looked_object
				var tags_changed := looked_tags != _last_debug_looked_tags

				if object_changed or tags_changed:
					_last_debug_looked_object = looked_object
					_last_debug_looked_tags = looked_tags.duplicate()

					print(
						"Player raycast hit: ",
						looked_object.name if looked_object else "null",
						" tags=",
						looked_tags,
						" component_type=",
						str(looked_object.get_meta("component_type", "")) if looked_object else "",
						" lock_id=",
						str(looked_object.get_meta("lock_id", "")) if looked_object else ""
					)


func _find_agent_object(start_node: Node) -> Node:
	var node: Node = start_node

	while node != null:
		if node.has_method("get_rl_tags"):
			return node

		if node.has_meta("agent_tags"):
			return node

		if node.has_meta("semantic_tag"):
			return node

		if node.has_method("interact"):
			return node

		node = node.get_parent()

	return start_node


func _get_rl_tags_from_hierarchy(start_node: Node) -> Array[String]:
	var tags: Array[String] = []
	var node: Node = start_node

	while node != null:
		for tag in _get_rl_tags(node):
			if not tags.has(tag):
				tags.append(tag)

		if node.has_method("get_rl_tags") or node.has_meta("agent_tags") or node.has_meta("semantic_tag"):
			break

		node = node.get_parent()

	return tags


func _get_rl_tags(node: Node) -> Array[String]:
	var tags: Array[String] = []

	if node.has_method("get_rl_tags"):
		for tag in node.get_rl_tags():
			var tag_string := str(tag)
			if not tags.has(tag_string):
				tags.append(tag_string)

	if node.has_meta("agent_tags"):
		var metadata_tags = node.get_meta("agent_tags")
		if metadata_tags is Array:
			for tag in metadata_tags:
				var tag_string := str(tag)
				if not tags.has(tag_string):
					tags.append(tag_string)

	if node.has_meta("semantic_tag"):
		var semantic_tag := str(node.get_meta("semantic_tag"))
		if not semantic_tag.is_empty() and not tags.has(semantic_tag):
			tags.append(semantic_tag)

	for group_name in node.get_groups():
		var group_string := str(group_name)
		if group_string.begins_with("tag_"):
			var group_tag := group_string.trim_prefix("tag_")
			if not tags.has(group_tag):
				tags.append(group_tag)

	return tags


func _try_interact() -> void:
	if looked_object == null:
		return

	var interactable := _find_interactable(looked_object)

	if interactable == null:
		print("Player interact: looked object has no interact method: ", looked_object.name)
		return

	print(
		"Player interact: ",
		interactable.name,
		" tags=",
		_get_rl_tags_from_hierarchy(interactable)
	)

	interactable.interact(self)


func _find_interactable(start_node: Node) -> Node:
	var node: Node = start_node

	while node != null:
		if node.has_method("interact"):
			return node

		node = node.get_parent()

	return null


func damage(amount: int) -> void:
	health = max(health - amount, 0)

	if health <= 0:
		game_state = GameState.DEAD


func heal(amount: int) -> void:
	health = min(health + amount, max_health)


func add_money(amount: int) -> void:
	money = max(money + amount, 0)


func get_agent_observation() -> Dictionary:
	return {
		"health_normalized": float(health) / float(max_health),
		"money": money,
		"game_state": int(game_state),
		"position": [
			global_position.x,
			global_position.y,
			global_position.z
		],
		"velocity": [
			velocity.x,
			velocity.y,
			velocity.z
		],
		"looked_object_present": looked_object != null,
		"looked_tags": looked_tags,
		"looked_tag_id": _first_tag_id(looked_tags)
	}


func _first_tag_id(tags: Array[String]) -> int:
	if tags.is_empty():
		return 0

	match tags[0]:
		"door":
			return 1
		"enemy":
			return 2
		"npc":
			return 3
		"chest":
			return 4
		"key":
			return 5
		"coin":
			return 6
		"lever":
			return 7
		"exit":
			return 8
		_:
			return 99
