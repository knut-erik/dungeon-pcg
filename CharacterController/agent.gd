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

@onready var head: Node3D = $Head
@onready var interact_ray: RayCast3D = $Head/InteractRay

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
		"move_forward",
		"move_back"
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
	agent_action["move_x"] = clamp(float(action.get("move_x", 0.0)), -1.0, 1.0)
	agent_action["move_z"] = clamp(float(action.get("move_z", 0.0)), -1.0, 1.0)
	agent_action["jump"] = bool(action.get("jump", false))
	agent_action["interact"] = bool(action.get("interact", false))
	agent_action["look_yaw"] = clamp(float(action.get("look_yaw", 0.0)), -1.0, 1.0)
	agent_action["look_pitch"] = clamp(float(action.get("look_pitch", 0.0)), -1.0, 1.0)


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
		looked_object = collider
		looked_tags = _get_rl_tags(collider)


func _get_rl_tags(node: Node) -> Array[String]:
	var tags: Array[String] = []

	if node.has_method("get_rl_tags"):
		for tag in node.get_rl_tags():
			tags.append(str(tag))

	for group_name in node.get_groups():
		var group_string := str(group_name)
		if group_string.begins_with("tag_"):
			tags.append(group_string.trim_prefix("tag_"))

	return tags


func _try_interact() -> void:
	if looked_object == null:
		return

	if looked_object.has_method("interact"):
		looked_object.interact(self)
		return

	var parent := looked_object.get_parent()
	if parent and parent.has_method("interact"):
		parent.interact(self)


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
