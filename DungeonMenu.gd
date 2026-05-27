extends Node2D

const DEFAULT_MAX_GENERATION_ATTEMPTS := 20
const DEFAULT_NUM_CHALLENGES := 3
const ROOM_BLUEPRINT_ROOT := "res://DungeonGenerator/Rooms/RoomLibrary"

@export var world_scene: PackedScene = preload("res://_PlayableConfiguration/PCG_World.tscn")
@export var start_hidden_after_generate := true

@onready var _generate_button: BaseButton = $Generate
@onready var _seed_input: SpinBox = $Seed
@onready var _max_attempts_input: SpinBox = $MaxGenAttempts
@onready var _num_challenges_input: SpinBox = $NumChallenges
@onready var _room_library_list: ItemList = get_node_or_null("RoomLibrary") as ItemList
@onready var _config_json: TextEdit = get_node_or_null("ConfigJson") as TextEdit
@onready var _build_button: BaseButton = get_node_or_null("BuildDungeon") as BaseButton

var _active_world: Node
var _room_blueprints: Array[RoomBlueprint] = []


func _ready() -> void:
	_generate_button.pressed.connect(_on_generate_pressed)

	if _build_button != null:
		_build_button.pressed.connect(_on_build_pressed)

	var quit_button := _find_optional_button("Quit")
	if quit_button == null:
		quit_button = get_node_or_null("Generate/Generate") as BaseButton

	if quit_button != null:
		quit_button.pressed.connect(_on_quit_pressed)

	_seed_input.min_value = 0
	_seed_input.allow_greater = true
	_seed_input.allow_lesser = false

	_max_attempts_input.min_value = 1
	_max_attempts_input.allow_greater = true
	_max_attempts_input.allow_lesser = false
	if int(_max_attempts_input.value) <= 0:
		_max_attempts_input.value = DEFAULT_MAX_GENERATION_ATTEMPTS

	_num_challenges_input.min_value = 0
	_num_challenges_input.allow_greater = true
	_num_challenges_input.allow_lesser = false
	if int(_num_challenges_input.value) <= 0:
		_num_challenges_input.value = DEFAULT_NUM_CHALLENGES

	_populate_room_library()


func _on_generate_pressed() -> void:
	var config: Dictionary = _create_config_dictionary()
	var json: String = JSON.stringify(config, "\t")

	if _config_json != null:
		_config_json.text = json
	else:
		print(json)


func _on_build_pressed() -> void:
	var json: String = _config_json.text if _config_json != null else JSON.stringify(_create_config_dictionary(), "\t")
	var parsed: Variant = JSON.parse_string(json)

	if not parsed is Dictionary:
		push_error("DungeonMenu: Config JSON must parse to an object.")
		return

	await _build_world_from_config(parsed as Dictionary)


func _build_world_from_config(config: Dictionary) -> void:
	if _active_world != null and is_instance_valid(_active_world):
		_active_world.queue_free()
		_active_world = null
		await get_tree().process_frame

	var world: Node = world_scene.instantiate()
	var generator: DungeonGenerator = _find_dungeon_generator(world)

	if generator == null:
		push_error("DungeonMenu: Could not find DungeonGenerator in world scene.")
		world.queue_free()
		return

	var selected_blueprints: Array[RoomBlueprint] = _get_selected_room_blueprints()
	if not selected_blueprints.is_empty():
		generator.room_library = selected_blueprints

	generator.generation_config = config

	get_tree().root.add_child(world)
	_active_world = world

	if start_hidden_after_generate:
		visible = false


func _create_config_dictionary() -> Dictionary:
<<<<<<< Updated upstream
	var seed: int = int(_seed_input.value)
	if seed == 0:
		seed = Time.get_ticks_usec()
=======
	var config_seed: int = int(_seed_input.value)
	if config_seed == 0:
		config_seed = Time.get_ticks_usec()
>>>>>>> Stashed changes

	var max_attempts: int = maxi(1, int(_max_attempts_input.value))
	var challenge_count: int = maxi(0, int(_num_challenges_input.value))
	var create_loop: bool = _get_create_loop_enabled()
	var selected_blueprints: Array[RoomBlueprint] = _get_selected_room_blueprints()
	if selected_blueprints.is_empty():
		for blueprint in _room_blueprints:
			selected_blueprints.append(blueprint)

	var rng := RandomNumberGenerator.new()
<<<<<<< Updated upstream
	rng.seed = seed
=======
	rng.seed = config_seed
>>>>>>> Stashed changes

	var rewriter := GraphRewriter.new(selected_blueprints, challenge_count, create_loop, rng, false)
	var graph: LogicalGraph = rewriter.generate()

	return {
		"version": 1,
		"generator": {
<<<<<<< Updated upstream
			"seed": seed,
=======
			"seed": config_seed,
>>>>>>> Stashed changes
			"max_generation_attempts": max_attempts,
			"num_challenges": challenge_count,
			"create_loop": create_loop
		},
		"room_library": _serialize_room_library(selected_blueprints),
		"logical_graph": _serialize_logical_graph(graph)
	}


func _serialize_room_library(blueprints: Array[RoomBlueprint]) -> Array:
	var result: Array = []

	for blueprint in blueprints:
		if blueprint == null:
			continue

		result.append({
			"path": blueprint.resource_path,
			"possible_tags": blueprint.possible_tags,
			"parameters": {
				"width": _serialize_room_parameter(blueprint.width_param),
				"length": _serialize_room_parameter(blueprint.length_param),
				"enemy_density": _serialize_room_parameter(blueprint.enemy_density_param)
			}
		})

	return result


func _serialize_room_parameter(parameter: RoomParameter) -> Dictionary:
	if parameter == null:
		return {}

	return {
		"min_value": parameter.min_value,
		"max_value": parameter.max_value,
		"has_probability_curve": parameter.probability_curve != null
	}


func _serialize_logical_graph(graph: LogicalGraph) -> Dictionary:
	var nodes: Array = []
	var edges: Array = []

	for node in graph.nodes:
		nodes.append({
			"id": node.id,
			"assigned_tags": node.assigned_tags,
			"blueprint_path": node.blueprint.resource_path if node.blueprint != null else "",
			"custom_data": node.custom_data
		})

	for edge in graph.edges:
		edges.append({
			"id": edge.id,
			"from": edge.from_node.id if edge.from_node != null else "",
			"to": edge.to_node.id if edge.to_node != null else "",
			"edge_type": edge.edge_type,
			"tags": edge.tags,
			"requirements": edge.requirements,
			"effects": edge.effects,
			"custom_data": edge.custom_data
		})

	return {
		"nodes": nodes,
		"edges": edges
	}


func _find_dungeon_generator(root: Node) -> DungeonGenerator:
	if root is DungeonGenerator:
		return root

	for child in root.find_children("*", "DungeonGenerator", true, false):
		return child as DungeonGenerator

	for child in root.find_children("*", "Node", true, false):
		if child is DungeonGenerator:
			return child as DungeonGenerator

	return null


func _populate_room_library() -> void:
	if _room_library_list == null:
		return

	_room_library_list.clear()
	_room_blueprints.clear()

	var blueprint_paths: Array[String] = []
	_collect_room_blueprint_paths(ROOM_BLUEPRINT_ROOT, blueprint_paths)
	blueprint_paths.sort()

	for path in blueprint_paths:
		var resource: Resource = load(path)
		if not resource is RoomBlueprint:
			continue

		var blueprint: RoomBlueprint = resource as RoomBlueprint
		var item_index: int = _room_library_list.add_item(_get_blueprint_label(blueprint, path))
		_room_library_list.set_item_metadata(item_index, _room_blueprints.size())
		_room_library_list.select(item_index, false)
		_room_blueprints.append(blueprint)


func _collect_room_blueprint_paths(path: String, result: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_warning("DungeonMenu: Could not open room blueprint directory %s" % path)
		return

	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry.is_empty():
			break

		if entry.begins_with("."):
			continue

		var entry_path: String = path.path_join(entry)
		if dir.current_is_dir():
			_collect_room_blueprint_paths(entry_path, result)
		elif entry_path.get_extension().to_lower() == "tres":
			result.append(entry_path)

	dir.list_dir_end()


func _get_blueprint_label(blueprint: RoomBlueprint, path: String) -> String:
	var tags: String = ", ".join(blueprint.possible_tags)
	var file_name: String = path.get_file().get_basename()
	if tags.is_empty():
		return file_name
	return "%s [%s]" % [file_name, tags]


func _get_selected_room_blueprints() -> Array[RoomBlueprint]:
	var selected: Array[RoomBlueprint] = []

	if _room_library_list == null:
		return selected

	for item_index in _room_library_list.get_selected_items():
		var blueprint_index: int = int(_room_library_list.get_item_metadata(item_index))
		if blueprint_index >= 0 and blueprint_index < _room_blueprints.size():
			selected.append(_room_blueprints[blueprint_index])

	return selected


func _get_create_loop_enabled() -> bool:
	var create_loop: Node = get_node_or_null("CreateLoop")

	if create_loop == null:
		return true

	if create_loop is BaseButton:
		return (create_loop as BaseButton).button_pressed

	return true


func _find_optional_button(node_name: String) -> BaseButton:
	var direct: Node = get_node_or_null(node_name)
	if direct is BaseButton:
		return direct as BaseButton

	for node in find_children(node_name, "BaseButton", true, false):
		return node as BaseButton

	return null


func _on_quit_pressed() -> void:
	get_tree().quit()
