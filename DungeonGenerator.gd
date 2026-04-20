extends Node3D
class_name DungeonGenerator

@export var room_library: Array[RoomBlueprint] = []

@export var num_challenges: int = 3
@export var create_loop: bool = true

const STAIR_THRESHOLD := 0.001

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

func _build_physical_dungeon(logic_nodes: Array[LogicalNode], rng: RandomNumberGenerator) -> void:
	if logic_nodes.is_empty(): return

	var physical_rooms: Array[BaseRoom] = []
	var room_map: Dictionary = {}

	var start_logic = logic_nodes[0]
	var start_room  = _spawn_room(start_logic, rng)
	start_room.position = Vector3.ZERO
	physical_rooms.append(start_room)
	room_map[start_logic] = start_room

	var queue   = [start_logic]
	var visited = {start_logic: true}

	while queue.size() > 0:
		var current_logic = queue.pop_front()
		var current_room  = room_map[current_logic]

		var current_out_y = current_room.global_position.y
		if current_room.gateway_out:
			current_out_y = current_room.gateway_out.global_position.y

		var connections_copy = current_logic.connections.duplicate()

		for child_logic in connections_copy:
			var is_already_visited = visited.has(child_logic)
			var target_gateway_y   = current_out_y
			var delta_y            = 0.0

			if is_already_visited:
				var target_room = room_map[child_logic]
				var target_in_y = target_room.global_position.y
				if target_room.gateway_in:
					target_in_y = target_room.gateway_in.global_position.y
				delta_y = target_in_y - current_out_y
			else:
				if rng.randf() < 0.30 and not child_logic.assigned_tags.has("Stairs"):
					target_gateway_y += rng.randf_range(4.0, 8.0)
				delta_y = target_gateway_y - current_out_y

			if abs(delta_y) > STAIR_THRESHOLD and not child_logic.assigned_tags.has("Stairs"):
				print("Regissör: Höjdskillnad (", delta_y, ") — injicerar trappa")
				var stairs_logic = _create_basic_node("Stairs", "stairs_" + str(randi()))
				stairs_logic.custom_data["delta_y"] = delta_y
				current_logic.connections.erase(child_logic)
				current_logic.connections.append(stairs_logic)
				stairs_logic.connections.append(child_logic)
				child_logic        = stairs_logic
				target_gateway_y   = current_out_y
				is_already_visited = false

			if is_already_visited:
				continue

			visited[child_logic] = true
			queue.append(child_logic)

			var child_room       = _spawn_room(child_logic, rng)
			var child_in_local_y = 0.0
			if child_room.gateway_in:
				child_in_local_y = child_room.gateway_in.global_position.y \
								 - child_room.global_position.y

			var required_room_y = target_gateway_y - child_in_local_y
			var base_pos        = Vector3(current_room.position.x, required_room_y, current_room.position.z)

			var placed        = false
			var test_distance = 15.0
			var test_angle    = rng.randf_range(0.0, PI * 2.0)

			while not placed:
				var offset           = Vector3(cos(test_angle), 0.0, sin(test_angle)) * test_distance
				var current_test_pos = base_pos + offset
				if not _check_aabb_overlap(current_test_pos, child_room, physical_rooms):
					child_room.position = current_test_pos
					physical_rooms.append(child_room)
					room_map[child_logic] = child_room
					placed = true
				else:
					test_angle += PI / 4.0
					if test_angle >= PI * 2.0 + 0.1:
						test_angle     = 0.0
						test_distance += 10.0

	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout

	var pending_connections: Array = []
	for logic_node in room_map.keys():
		var room_a = room_map[logic_node]
		for connected_logic_node in logic_node.connections:
			if not room_map.has(connected_logic_node):
				push_warning("Korridor hoppad: '%s' saknas i room_map." % connected_logic_node.id)
				continue
			var room_b = room_map[connected_logic_node]
			if room_a.gateway_out and room_b.gateway_in:
				var y_diff = abs(room_a.gateway_out.global_position.y \
							   - room_b.gateway_in.global_position.y)
				if y_diff > 0.1:
					push_error("Y-mismatch %.2f: '%s' → '%s'. Trappa ej genererad." \
						% [y_diff, logic_node.id, connected_logic_node.id])
					continue
				pending_connections.append([room_a.gateway_out, room_b.gateway_in])

	var network := CorridorNetwork.new()
	add_child(network)
	network.build(pending_connections)

# ==============================================================================
# DEL 3: KOLLISIONSHJÄLPARE
# ==============================================================================

func _check_aabb_overlap(test_pos: Vector3, child_room: BaseRoom,
						 placed_rooms: Array[BaseRoom]) -> bool:
	var margin     = 4.0
	var margin_vec = Vector3.ONE * margin
	for placed_room in placed_rooms:
		for c_aabb in child_room.get_local_aabbs():
			var global_c = AABB(c_aabb.position + test_pos - margin_vec * 0.5,
								c_aabb.size + margin_vec)
			for p_aabb in placed_room.get_local_aabbs():
				var global_p = AABB(p_aabb.position + placed_room.position - margin_vec * 0.5,
									p_aabb.size + margin_vec)
				if global_c.intersects(global_p):
					return true
	return false

func _spawn_room(logic_node: LogicalNode, rng: RandomNumberGenerator) -> BaseRoom:
	var room = logic_node.blueprint.room_scene.instantiate() as BaseRoom
	add_child(room)
	room.setup_room(rng, logic_node)
	return room

'''JUST L SHAPED AND U SHAPED CORRIDORS
extends Node3D
class_name DungeonGenerator

@export var room_library: Array[RoomBlueprint] = []
@export var corridor_scene: PackedScene

@export var num_challenges: int = 3
@export var create_loop: bool = true

const STAIR_THRESHOLD  := 0.001
const CORRIDOR_WIDTH   := 3.0
const CORRIDOR_HEIGHT  := 3.4
# Units to travel perpendicular to room wall before any turn.
# Applied at BOTH ends: exit from source, approach to destination.
const MIN_EXIT         := 8.0

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

func _build_physical_dungeon(logic_nodes: Array[LogicalNode], rng: RandomNumberGenerator) -> void:
	if logic_nodes.is_empty(): return

	var physical_rooms: Array[BaseRoom] = []
	var room_map: Dictionary = {}

	var start_logic = logic_nodes[0]
	var start_room  = _spawn_room(start_logic, rng)
	start_room.position = Vector3.ZERO
	physical_rooms.append(start_room)
	room_map[start_logic] = start_room

	var queue   = [start_logic]
	var visited = {start_logic: true}

	while queue.size() > 0:
		var current_logic = queue.pop_front()
		var current_room  = room_map[current_logic]

		var current_out_y = current_room.global_position.y
		if current_room.gateway_out:
			current_out_y = current_room.gateway_out.global_position.y

		var connections_copy = current_logic.connections.duplicate()

		for child_logic in connections_copy:
			var is_already_visited = visited.has(child_logic)
			var target_gateway_y   = current_out_y
			var delta_y            = 0.0

			if is_already_visited:
				var target_room = room_map[child_logic]
				var target_in_y = target_room.global_position.y
				if target_room.gateway_in:
					target_in_y = target_room.gateway_in.global_position.y
				delta_y = target_in_y - current_out_y
			else:
				if rng.randf() < 0.30 and not child_logic.assigned_tags.has("Stairs"):
					target_gateway_y += rng.randf_range(4.0, 8.0)
				delta_y = target_gateway_y - current_out_y

			if abs(delta_y) > STAIR_THRESHOLD and not child_logic.assigned_tags.has("Stairs"):
				print("Regissör: Höjdskillnad (", delta_y, ") — injicerar trappa")
				var stairs_logic = _create_basic_node("Stairs", "stairs_" + str(randi()))
				stairs_logic.custom_data["delta_y"] = delta_y
				current_logic.connections.erase(child_logic)
				current_logic.connections.append(stairs_logic)
				stairs_logic.connections.append(child_logic)
				child_logic        = stairs_logic
				target_gateway_y   = current_out_y
				is_already_visited = false

			if is_already_visited:
				continue

			visited[child_logic] = true
			queue.append(child_logic)

			var child_room       = _spawn_room(child_logic, rng)
			var child_in_local_y = 0.0
			if child_room.gateway_in:
				child_in_local_y = child_room.gateway_in.global_position.y \
								 - child_room.global_position.y

			var required_room_y = target_gateway_y - child_in_local_y
			var base_pos        = Vector3(current_room.position.x, required_room_y, current_room.position.z)

			var placed        = false
			var test_distance = 15.0
			var test_angle    = rng.randf_range(0.0, PI * 2.0)

			while not placed:
				var offset           = Vector3(cos(test_angle), 0.0, sin(test_angle)) * test_distance
				var current_test_pos = base_pos + offset
				if not _check_aabb_overlap(current_test_pos, child_room, physical_rooms):
					child_room.position = current_test_pos
					physical_rooms.append(child_room)
					room_map[child_logic] = child_room
					placed = true
				else:
					test_angle += PI / 4.0
					if test_angle >= PI * 2.0 + 0.1:
						test_angle     = 0.0
						test_distance += 10.0

	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout

	for logic_node in room_map.keys():
		var room_a = room_map[logic_node]
		for connected_logic_node in logic_node.connections:
			if not room_map.has(connected_logic_node):
				push_warning("Korridor hoppad: '%s' saknas i room_map." % connected_logic_node.id)
				continue
			var room_b = room_map[connected_logic_node]
			if room_a.gateway_out and room_b.gateway_in:
				var y_diff = abs(room_a.gateway_out.global_position.y \
							   - room_b.gateway_in.global_position.y)
				if y_diff > 0.1:
					push_error("Y-mismatch %.2f: '%s' → '%s'. Trappa ej genererad." \
						% [y_diff, logic_node.id, connected_logic_node.id])
					continue
				_build_corridor(room_a.gateway_out, room_b.gateway_in,
								physical_rooms, room_a, room_b)

# ==============================================================================
# DEL 3: L/U-KORRIDORER
# ==============================================================================

func _build_corridor(gateway_a: Marker3D, gateway_b: Marker3D,
					 placed_rooms: Array[BaseRoom],
					 source_room: BaseRoom, dest_room: BaseRoom) -> void:
	if not corridor_scene: return

	var pos_a = gateway_a.global_position
	var pos_b = gateway_b.global_position
	var dir_a = -gateway_a.global_transform.basis.z.normalized()
	var dir_b = -gateway_b.global_transform.basis.z.normalized()
	var excluded: Array[BaseRoom] = [source_room, dest_room]

	# Always exit perpendicular to the source wall for MIN_EXIT units.
	# Always approach the destination perpendicular to its wall for MIN_EXIT units.
	# This guarantees the corridor never immediately hugs a wall, and U-shapes
	# emerge naturally when the two rooms face each other.
	var exit_a     = pos_a + dir_a * MIN_EXIT
	var approach_b = pos_b + dir_b * MIN_EXIT

	# Degenerate case: stubs overlap (rooms very close together).
	# Just draw a direct 2-point corridor.
	if exit_a.distance_to(approach_b) < 0.5:
		var corridor = corridor_scene.instantiate() as Corridor
		add_child(corridor)
		corridor.generate(PackedVector3Array([pos_a, pos_b]))
		return

	var waypoints = PackedVector3Array([pos_a, exit_a])

	var elbow = _pick_elbow(exit_a, approach_b, dir_a, placed_rooms, excluded)
	if elbow.distance_to(exit_a) > 0.1 and elbow.distance_to(approach_b) > 0.1:
		waypoints.append(elbow)

	waypoints.append(approach_b)
	waypoints.append(pos_b)

	var corridor = corridor_scene.instantiate() as Corridor
	add_child(corridor)
	corridor.generate(waypoints)

# Returns the best elbow connecting exit_a to approach_b.
# Prefers the option whose first segment aligns with dir_a.
# excluded rooms are skipped in the intersection test.
func _pick_elbow(exit_a: Vector3, approach_b: Vector3, dir_a: Vector3,
				 placed_rooms: Array[BaseRoom], excluded: Array[BaseRoom]) -> Vector3:
	var y: float  = exit_a.y
	var ea        = Vector3(approach_b.x, y, exit_a.z)   # X-then-Z
	var eb        = Vector3(exit_a.x,    y, approach_b.z) # Z-then-X

	var ea_blocked: bool = _l_path_hits_room(exit_a, ea, approach_b, placed_rooms, excluded)
	var eb_blocked: bool = _l_path_hits_room(exit_a, eb, approach_b, placed_rooms, excluded)
	var ea_aligned: bool = (ea - exit_a).dot(dir_a) > 0.0
	var eb_aligned: bool = (eb - exit_a).dot(dir_a) > 0.0

	# Priority: unblocked + aligned > unblocked > aligned > fallback
	if not ea_blocked and ea_aligned: return ea
	if not eb_blocked and eb_aligned: return eb
	if not ea_blocked: return ea
	if not eb_blocked: return eb
	return ea  # Both blocked — fall back; room margin should make this rare

func _l_path_hits_room(a: Vector3, elbow: Vector3, b: Vector3,
					   placed_rooms: Array[BaseRoom],
					   excluded: Array[BaseRoom]) -> bool:
	return _segment_hits_room(a, elbow, placed_rooms, excluded) \
		or _segment_hits_room(elbow, b, placed_rooms, excluded)

# AABB intersection check for a single axis-aligned corridor segment.
# Source and destination rooms are excluded — the corridor legitimately
# starts and ends inside them. No endpoint shrinking needed.
func _segment_hits_room(a: Vector3, b: Vector3,
						placed_rooms: Array[BaseRoom],
						excluded: Array[BaseRoom]) -> bool:
	if a.distance_to(b) < 0.05:
		return false
	var w: float  = CORRIDOR_WIDTH
	var seg: AABB = AABB(
		Vector3(min(a.x, b.x) - w * 0.5, a.y, min(a.z, b.z) - w * 0.5),
		Vector3(abs(b.x - a.x) + w, CORRIDOR_HEIGHT, abs(b.z - a.z) + w)
	)
	for room in placed_rooms:
		if excluded.has(room):
			continue
		for r_aabb in room.get_local_aabbs():
			var global_r = AABB(r_aabb.position + room.position, r_aabb.size)
			if seg.intersects(global_r):
				return true
	return false

# ==============================================================================
# DEL 4: KOLLISIONSHJÄLPARE
# ==============================================================================

func _check_aabb_overlap(test_pos: Vector3, child_room: BaseRoom,
						 placed_rooms: Array[BaseRoom]) -> bool:
	var margin     = 4.0
	var margin_vec = Vector3.ONE * margin
	for placed_room in placed_rooms:
		for c_aabb in child_room.get_local_aabbs():
			var global_c = AABB(c_aabb.position + test_pos - margin_vec * 0.5,
								c_aabb.size + margin_vec)
			for p_aabb in placed_room.get_local_aabbs():
				var global_p = AABB(p_aabb.position + placed_room.position - margin_vec * 0.5,
									p_aabb.size + margin_vec)
				if global_c.intersects(global_p):
					return true
	return false

func _spawn_room(logic_node: LogicalNode, rng: RandomNumberGenerator) -> BaseRoom:
	var room = logic_node.blueprint.room_scene.instantiate() as BaseRoom
	add_child(room)
	room.setup_room(rng, logic_node)
	return room # '''

''' GAMMAL _build_corridor
func _build_corridor(gateway_a: Marker3D, gateway_b: Marker3D) -> void:
	if corridor_scene:
		var corridor = corridor_scene.instantiate() as Corridor
		add_child(corridor)
		corridor.generate_spline(gateway_a, gateway_b)'''

'''extends Node3D
class_name DungeonGenerator

# 1. Ett bibliotek av tillgängliga rum (Blueprints) istället för bara en.
@export var room_library: Array[RoomBlueprint] = []
@export var corridor_scene: PackedScene

func _ready() -> void:
	# Säkerhetskontroll
	if room_library.is_empty():
		push_error("DungeonGenerator saknar RoomBlueprints! Lägg till dem i editorn.")
		return

	var rng = RandomNumberGenerator.new()
	rng.randomize()

	# 2. Generera den Logiska Grafen (Detta blir hjärnan)
	# Just nu gör vi en hårdkodad lista, men snart kommer algoritmen bygga denna!
	var logical_sequence: Array[LogicalNode] = _generate_logical_graph()

	# 3. Bygg den fysiska världen baserat på grafen
	_build_physical_dungeon(logical_sequence, rng)


# ==============================================================================
# DEL 1: LOGIK & GRAPH REWRITING
# ==============================================================================

# Denna funktion kommer vi att bygga ut för att hantera lås, nycklar etc.
func _generate_logical_graph() -> Array[LogicalNode]:
	var graph: Array[LogicalNode] = []

	# Skapa en simpel kedja: Start -> Enemy -> Enemy -> Boss
	var sequence_tags = ["Entrance", "Alive", "Alive", "Boss"]

	for i in range(sequence_tags.size()):
		var tag = sequence_tags[i]

		# Hitta en blueprint som stöder denna tagg
		var chosen_blueprint = _find_blueprint_by_tag(tag)

		if chosen_blueprint == null:
			push_warning("Hittade inget rum med taggen: " + tag + ". Skippar.")
			continue

		# Skapa noden
		var node = LogicalNode.new()
		node.id = "room_" + str(i)
		node.assigned_tags.assign([tag])
		node.blueprint = chosen_blueprint

		# Länka ihop noderna (Node A pekar på Node B)
		if i > 0 and graph.size() > 0:
			var prev_node = graph[-1]
			prev_node.connections.append(node)

		graph.append(node)

	return graph

# En hjälpreda för att söka i biblioteket (Väldigt användbar för Graph Rewriting)
func _find_blueprint_by_tag(target_tag: String) -> RoomBlueprint:
	var valid_blueprints: Array[RoomBlueprint] = []

	for blueprint in room_library:
		# Förutsätter att du har lagt till "possible_tags" i RoomBlueprint.gd
		if blueprint.possible_tags.has(target_tag):
			valid_blueprints.append(blueprint)

	if valid_blueprints.size() > 0:
		# Returnera ett slumpmässigt rum som matchar taggen
		return valid_blueprints.pick_random()

	return null

# ==============================================================================
# DEL 2: FYSISK GENERERING
# ==============================================================================

func _build_physical_dungeon(logic_nodes: Array[LogicalNode], rng: RandomNumberGenerator) -> void:
	if logic_nodes.is_empty():
		return

	var physical_rooms: Array[BaseRoom] = []
	var current_z_offset = 0.0

	# 1. Spawna alla rum
	for node in logic_nodes:
		var room_instance = _spawn_room(node, rng)
		room_instance.position = Vector3(0, 0, current_z_offset)
		current_z_offset -= 30.0
		physical_rooms.append(room_instance)

	# 2. Vänta ordentligt på att trädet är redo
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout # En liten extra säkerhetsmarginal

	# 3. Rita korridorer
	for i in range(physical_rooms.size() - 1):
		var room_a = physical_rooms[i]
		var room_b = physical_rooms[i + 1]

		if room_a.gateway_out and room_b.gateway_in:
			_build_corridor(room_a.gateway_out, room_b.gateway_in)

			# Tvinga Godot att rita klart denna korridor innan vi börjar med nästa!
			await get_tree().process_frame
		else:
			push_error("Kunde inte hitta gateways för korridor mellan " + room_a.name + " och " + room_b.name)


func _spawn_room(logic_node: LogicalNode, rng: RandomNumberGenerator) -> BaseRoom:
	var room_instance = logic_node.blueprint.room_scene.instantiate() as BaseRoom
	add_child(room_instance)
	room_instance.setup_room(rng, logic_node)
	return room_instance


func _build_corridor(gateway_a: Marker3D, gateway_b: Marker3D) -> void:
	if corridor_scene:
		var corridor = corridor_scene.instantiate() as Corridor
		add_child(corridor)
		corridor.generate_spline(gateway_a, gateway_b)'''

'''
BASIC CORRIDOR TEST
extends Node3D

@export var test_blueprint: RoomBlueprint
@export var corridor_scene: PackedScene # Dra in din Corridor.tscn här!

func _ready() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	# 1. Skapa Rum 1 (Start)
	var room_1 = _spawn_room("room_1", rng)

	# 2. Skapa Rum 2 (Mål) och flytta det en bit bort
	var room_2 = _spawn_room("room_2", rng)
	room_2.position = Vector3(15, 0, -20)

	# Tvinga uppdatering av globala transform-matriser (Viktigt innan vi bygger splines!)
	# Detta säger åt Godot att räkna ut exakt var portarna är i 3D-rymden just nu.
	get_tree().process_frame.connect(_build_corridor.bind(room_1.gateway_out, room_2.gateway_in), CONNECT_ONE_SHOT)


# Hjälpfunktion för att spawna rum (för att hålla koden ren)
func _spawn_room(id: String, rng: RandomNumberGenerator) -> BaseRoom:
	var mock_node = LogicalNode.new()
	mock_node.id = id
	mock_node.blueprint = test_blueprint

	var room_instance = test_blueprint.room_scene.instantiate() as BaseRoom
	add_child(room_instance)
	room_instance.setup_room(rng, mock_node)

	return room_instance


# Kallas en frame efter _ready för att säkerställa att global_position är korrekt
func _build_corridor(gateway_a: Marker3D, gateway_b: Marker3D):
	if corridor_scene:
		var corridor = corridor_scene.instantiate() as Corridor
		add_child(corridor)
		corridor.generate_spline(gateway_a, gateway_b)'''


'''
BASIC ROOM GENERATION TEST
extends Node3D

@export var test_blueprint: RoomBlueprint

func _ready() -> void:
	# 1. Skapa en RNG
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	# 2. Skapa vår fejkade Logiska Nod
	var mock_node = LogicalNode.new()
	mock_node.id = "room_01"
	mock_node.assigned_tags.assign(["Dead"])
	mock_node.blueprint = test_blueprint

	# 3. Instansiera den fysiska scenen från blueprinten
	if test_blueprint and test_blueprint.room_scene:
		var room_instance = test_blueprint.room_scene.instantiate() as BaseRoom

		# Lägg till rummet i världen INNAN vi sätter upp det (viktigt för vissa physics/CSG grejer)
		add_child(room_instance)

		# 4. Bygg rummet!
		room_instance.setup_room(rng, mock_node)
	else:
		print("Fel: Glöm inte att dra in Blueprint_DefaultRoom.tres i inspektorn för TestScript!")'''
