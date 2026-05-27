extends GraphRule
class_name Rule_InsertChallenge

# This rule requires that target_node has an outgoing edge we can split.
func can_apply(_graph: LogicalGraph, target_node: LogicalNode) -> bool:
	return target_node.out_edges.size() > 0 and get_blueprint("Alive") != null


func apply(graph: LogicalGraph, target_node: LogicalNode) -> void:
	var edge_to_split: LogicalEdge = _pick_splittable_edge(target_node)

	if edge_to_split == null:
		return

	var next_node: LogicalNode = edge_to_split.to_node

	var challenge_node := LogicalNode.new()
	var challenge_suffix := rng.randi() if rng != null else graph.nodes.size()
	challenge_node.id = "challenge_%d" % challenge_suffix
	challenge_node.assigned_tags.assign(["Alive"])
	challenge_node.blueprint = get_blueprint("Alive")

	graph.insert_node_between(challenge_node, target_node, next_node)
	log_verbose("Regissor: added challenge between %s and %s" % [target_node.id, next_node.id])


func _pick_splittable_edge(target_node: LogicalNode) -> LogicalEdge:
	# Prefer splitting the main path, not loop/return/secret edges.
	for edge in target_node.out_edges:
		if edge == null:
			continue

		if edge.edge_type == "main_path" or edge.tags.has("main"):
			return edge

	# Fallback: any outgoing edge that has a valid destination.
	for edge in target_node.out_edges:
		if edge != null and edge.to_node != null:
			return edge

	return null
