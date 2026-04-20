# DEPRECATED

# GraphRewriter.gd
extends RefCounted
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
	return false
