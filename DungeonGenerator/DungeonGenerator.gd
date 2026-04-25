extends Node3D
class_name DungeonGenerator

@export var room_library: Array[RoomBlueprint] = []

@export var num_challenges: int = 3
@export var create_loop: bool = true

# The grid size must match CorridorNetwork.GRID_SIZE
const GRID_SIZE := 2.0 

func _ready() -> void:
	if room_library.is_empty():
		push_error("DungeonGenerator saknar RoomBlueprints! Lägg till dem i editorn.")
		return
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var logical_sequence: Array[LogicalNode] = _generate_logical_graph()
	_build_physical_dungeon(logical_sequence, rng)

# ==============================================================================
# DEL 1: LOGIK & GRAPH REWRITING
# ==============================================================================

func _generate_logical_graph() -> Array[LogicalNode]:
	var graph = LogicalGraph.new()

	var start_node = _create_basic_node("Entrance", "start_01")
	var boss_node  = _create_basic_node("Boss",     "boss_01")
	start_node.connections.append(boss_node)
	graph.add_node(start_node)
	graph.add_node(boss_node)

	var challenge_rule = Rule_InsertChallenge.new(room_library)
	var applied = 0
	while applied < num_challenges:
		var random_node = graph.nodes.pick_random()
		if challenge_rule.can_apply(graph, random_node):
			challenge_rule.apply(graph, random_node)
			applied += 1

	var lock_rule = Rule_LockAndKey.new(room_library)
	for node in graph.nodes:
		if lock_rule.can_apply(graph, node):
			lock_rule.apply(graph, node)
			break

	if create_loop and graph.nodes.size() > 2:
		var boss_target: LogicalNode = null
		for node in graph.nodes:
			if node.assigned_tags.has("Boss"):
				boss_target = node
				break
		if boss_target:
			print("Regissör: Skapar Return Path (Loop) från Boss till Entrance")
			graph.create_connection(boss_target, graph.nodes[0])

	return graph.nodes

func _create_basic_node(tag: String, id: String) -> LogicalNode:
	var node = LogicalNode.new()
	node.id = id
	node.assigned_tags.assign([tag])
	node.blueprint = _find_blueprint_by_tag(tag)
	return node

func _find_blueprint_by_tag(target_tag: String) -> RoomBlueprint:
	var valid: Array[RoomBlueprint] = []
	for blueprint in room_library:
		if blueprint.possible_tags.has(target_tag):
			valid.append(blueprint)
	return valid.pick_random() if valid.size() > 0 else null

# ==============================================================================
# DEL 2: FYSISK GENERERING
# ==============================================================================

func _build_physical_dungeon(logic_nodes: Array, rng: RandomNumberGenerator) -> void:
	var physical_rooms: Array[BaseRoom] = []
	var room_map: Dictionary = {}

	# 1. Place Start Room
	var start_logic = logic_nodes[0]
	var start_room = await _spawn_room(start_logic)  # ← await
	start_room.position = Vector3.ZERO
	physical_rooms.append(start_room)
	room_map[start_logic] = start_room

	var queue = [start_logic]
	var visited = {start_logic: true}

	# 2. Place all other rooms
	while queue.size() > 0:
		var curr_logic = queue.pop_front()
		var curr_room: BaseRoom = room_map[curr_logic]
		var current_out_y = curr_room.gateway_out.global_position.y if curr_room.gateway_out else curr_room.global_position.y

		var connections = curr_logic.connections.duplicate()
		for child_logic in connections:
			
			var is_already_visited = visited.has(child_logic)
			var target_gateway_y = current_out_y

			# Introduce Y-height variations organically. 
			# The CorridorNetwork will intercept these deltas and build stairs automatically.
			if not is_already_visited and rng.randf() < 0.30:
				var direction = 1.0 if rng.randf() > 0.5 else -1.0
				target_gateway_y += rng.randf_range(4.0, 8.0) * direction

			if is_already_visited:
				continue

			visited[child_logic] = true
			queue.append(child_logic)

			var child_room = await _spawn_room(child_logic)  
			
			var child_in_offset_y = 0.0
			if child_room.gateway_in:
				child_in_offset_y = child_room.gateway_in.global_position.y - child_room.global_position.y
				
			var required_y = target_gateway_y - child_in_offset_y
			var base_pos = Vector3(curr_room.position.x, required_y, curr_room.position.z)
			
			var test_radius = 20.0 # Start a bit wider to give A* room
			var placed = false
			
			while not placed:
				var angle = rng.randf_range(0, TAU)
				var raw_pos = base_pos + Vector3(cos(angle), 0, sin(angle)) * test_radius
				
				# Strict Grid Snapping. 
				# Forces gateways to land on perfect integer coordinates for A* integration.
				var test_pos = Vector3(
					snappedf(raw_pos.x, GRID_SIZE),
					raw_pos.y,
					snappedf(raw_pos.z, GRID_SIZE)
				)
				
				if not _check_aabb_overlap(test_pos, child_room, physical_rooms):
					child_room.position = test_pos
					physical_rooms.append(child_room)
					room_map[child_logic] = child_room
					placed = true
				else:
					test_radius += 5.0 

	# Give Godot's CSG system time to settle transforms and booleans; awaits are very important in general to make sure everything happens in the right order.
	await get_tree().create_timer(0.1).timeout

	# 3. Collect AABBs and Gateway Pairs for Network
	var room_aabbs: Array[AABB] = []
	for room in physical_rooms:
		for world_aabb in room.get_world_aabbs():
			room_aabbs.append(world_aabb)

	var pending_connections = []
	for node in room_map:
		for connected_node in node.connections:
			if not room_map.has(connected_node): continue
			var room_a = room_map[node]
			var room_b = room_map[connected_node]
			if room_a.gateway_out and room_b.gateway_in:
				pending_connections.append([room_a.gateway_out, room_b.gateway_in])

	# 4. Build Corridors
	var network = CorridorNetwork.new()
	add_child(network)
	await network.build(pending_connections, room_aabbs, room_library)

	# Debug — remove before shipping
	var debug = DungeonDebugDraw.new()
	add_child(debug)
	# Ensures DungeonDebugDraw._ready() has initialized its ImmediateMesh.
	await get_tree().process_frame
	debug.draw_debug(network, physical_rooms, network.get_stair_rooms())

# ==============================================================================
# DEL 3: KOLLISIONSHJÄLPARE
# ==============================================================================

func _check_aabb_overlap(test_pos: Vector3, child_room: BaseRoom, placed_rooms: Array[BaseRoom]) -> bool:
	# Breathing margin guarantees A* always has routing lanes between rooms.
	# Do not reduce below corridor_width (3.0) + some clearance.
	var margin := Vector3.ONE * 7.0

	# child_room is not yet placed — get_world_aabbs() reflects its current
	# position (likely zero). We offset each AABB by (test_pos - current_pos)
	# to simulate where it would sit if placed at test_pos. Change this?
	var placement_offset := test_pos - child_room.global_position

	for placed_room in placed_rooms:
		for c_aabb in child_room.get_world_aabbs():
			# Shift the candidate AABB to the test position, then grow by margin
			var shifted_c := AABB(c_aabb.position + placement_offset, c_aabb.size).grow(margin.x * 0.5)
			for p_aabb in placed_room.get_world_aabbs():
				var grown_p := p_aabb.grow(margin.x * 0.5)
				if shifted_c.intersects(grown_p):
					return true
	return false

func _spawn_room(logic_node) -> BaseRoom:
	var room = logic_node.blueprint.room_scene.instantiate() as BaseRoom
	add_child(room)
	if room.has_method("setup_room"):
		await room.setup_room(RandomNumberGenerator.new(), logic_node)
	return room
