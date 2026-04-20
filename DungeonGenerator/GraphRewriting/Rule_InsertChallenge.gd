# Rule_InsertChallenge.gd
extends GraphRule
class_name Rule_InsertChallenge

# Denna regel kräver att target_node har en connection vi kan bryta oss in i
func can_apply(_graph: LogicalGraph, _target_node: LogicalNode) -> bool:
	return _target_node.connections.size() > 0 and get_blueprint("Alive") != null

func apply(graph: LogicalGraph, target_node: LogicalNode) -> void:
	# Välj första bästa väg framåt från target_node
	var next_node = target_node.connections[0]
	
	# Skapa utmaningen
	var challenge_node = LogicalNode.new()
	challenge_node.id = "challenge_" + str(randi())
	challenge_node.assigned_tags.assign(["Alive"])
	challenge_node.blueprint = get_blueprint("Alive")
	
	# Säg till grafen att placera ut den
	graph.insert_node_between(challenge_node, target_node, next_node)
	print("Regissör: Lade till utmaning mellan ", target_node.id, " och ", next_node.id)
