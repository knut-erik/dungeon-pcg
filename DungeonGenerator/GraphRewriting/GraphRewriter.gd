# GraphRewriter.gd
extends RefCounted
class_name GraphRewriter

var room_library: Array[RoomBlueprint]
var num_challenges: int = 3
var create_loop: bool = true

func _init(lib: Array[RoomBlueprint], challenge_count: int = 3, should_create_loop: bool = true):
	room_library = lib
	num_challenges = challenge_count
	create_loop = should_create_loop


func generate() -> LogicalGraph:
	var graph := LogicalGraph.new()

	var start_node := _create_basic_node("Entrance", "start_01")
	var boss_node := _create_basic_node("Boss", "boss_01")

	graph.add_node(start_node)
	graph.add_node(boss_node)

	graph._connect(start_node, boss_node, "main_path", ["main"])

	var challenge_rule := Rule_InsertChallenge.new(room_library)
	var applied := 0
	var attempts := 0
	var max_attempts : int = max(20, num_challenges * 20)

	while applied < num_challenges and attempts < max_attempts:
		attempts += 1

		var random_node: LogicalNode = graph.nodes.pick_random()

		if challenge_rule.can_apply(graph, random_node):
			challenge_rule.apply(graph, random_node)
			applied += 1

	if applied < num_challenges:
		push_warning("GraphRewriter: Only applied %d / %d challenge rules." % [applied, num_challenges])

	var lock_rule := Rule_LockAndKey.new(room_library)
	for node in graph.nodes:
		if lock_rule.can_apply(graph, node):
			lock_rule.apply(graph, node)
			break

	if create_loop and graph.nodes.size() > 2:
		var boss_target: LogicalNode = _find_first_node_with_tag(graph, "Boss")

		if boss_target and graph.find_edge(boss_target, start_node) == null:
			var loop_edge := graph._connect(boss_target, start_node, "boss_return", ["loop", "boss_return"])
			loop_edge.requirements["preferred_from_gateway_role"] = "loop_return"
			loop_edge.requirements["preferred_to_gateway_role"] = "entrance"

	return graph


func _create_basic_node(tag: String, id: String) -> LogicalNode:
	var node := LogicalNode.new()
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

func _find_first_node_with_tag(graph: LogicalGraph, tag: String) -> LogicalNode:
	for node in graph.nodes:
		if node.assigned_tags.has(tag):
			return node

	return null

'''extends RefCounted
class_name GraphRewriter

var graph: Array[LogicalNode] = []

# Tar en array av blueprints och returnerar ett matchande rum
func get_blueprint(library: Array[RoomBlueprint], target_tag: String) -> RoomBlueprint:
	var valid = []
	for bp in library:
		if bp.possible_tags.has(target_tag):
			valid.append(bp)
	return valid.pick_random() if valid.size() > 0 else null

# Regel 1: Lägg till en utmaning mellan Start och Boss
func rule_insert_challenge(library: Array[RoomBlueprint]):
	# Leta efter mönstret: [Entrance] -> [Boss]
	for i in range(graph.size() - 1):
		var node_a = graph[i]
		var node_b = graph[i+1]
		
		if node_a.assigned_tags.has("Entrance") and node_b.assigned_tags.has("Boss"):
			var bp = get_blueprint(library, "Alive")
			if bp:
				var new_node = LogicalNode.new()
				new_node.id = "challenge_" + str(randi())
				new_node.assigned_tags.assign(["Alive"])
				new_node.blueprint = bp
				
				# Skjut in noden i arrayen
				graph.insert(i + 1, new_node)
				return true # Regeln applicerades
	return false

# Regel 2: Lägg till Lock & Key innan Boss
func rule_lock_and_key(library: Array[RoomBlueprint]):
	# Leta efter Bossen
	for i in range(1, graph.size()):
		if graph[i].assigned_tags.has("Boss"):
			var bp_lock = get_blueprint(library, "Locked")
			var bp_key = get_blueprint(library, "Key")
			
			if bp_lock and bp_key:
				var lock_node = LogicalNode.new()
				lock_node.id = "lock_" + str(randi())
				lock_node.assigned_tags.assign(["Locked"])
				lock_node.blueprint = bp_lock
				
				var key_node = LogicalNode.new()
				key_node.id = "key_" + str(randi())
				key_node.assigned_tags.assign(["Key"])
				key_node.blueprint = bp_key
				
				# Skjut in låset innan bossen
				graph.insert(i, lock_node)
				
				# Skjut in nyckeln innan låset
				graph.insert(i, key_node)
				return true
	return false'''
