class_name LogicalEdge
extends RefCounted

var id: String = ""

var from_node: LogicalNode
var to_node: LogicalNode

# Broad semantic category.
# Examples:
# "normal", "locked", "secret", "loop", "scene_transition", "boss_return"
var edge_type: String = "normal"

# Lightweight rule labels.
var tags: Array[String] = []

# Used later by physical assignment.
var from_gateway_id: String = ""
var to_gateway_id: String = ""

# Optional: this edge may connect to a corridor, not directly to another room gateway.
var connects_to_corridor: bool = false
var corridor_anchor_id: String = ""

# Gameplay metadata from graph rewriting rules.
var requirements: Dictionary = {}
var effects: Dictionary = {}
var custom_data: Dictionary = {}

func validate_graph(graph: LogicalGraph) -> bool:
	var ok := true

	for node in graph.nodes:
		if not node.blueprint:
			push_error("Node %s has no blueprint." % node.id)
			ok = false

	for edge in graph.edges:
		if not edge.from_node or not edge.to_node:
			push_error("Edge %s has missing endpoint." % edge.id)
			ok = false

		if edge.edge_type == "locked":
			if not edge.requirements.has("key_id"):
				push_error("Locked edge %s has no key_id." % edge.id)
				ok = false

	return ok
