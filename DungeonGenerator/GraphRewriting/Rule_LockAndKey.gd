extends GraphRule
class_name Rule_LockAndKey

func can_apply(_graph: LogicalGraph, target_node: LogicalNode) -> bool:
	# 1. Finns blueprints för lås och nyckel?
	if get_blueprint("Locked") == null or get_blueprint("Key") == null:
		return false

	# 2. Har denna nod en utgående edge till Boss?
	return _find_edge_to_boss(target_node) != null


func apply(graph: LogicalGraph, target_node: LogicalNode) -> void:
	var boss_edge: LogicalEdge = _find_edge_to_boss(target_node)
	if boss_edge == null:
		return

	var boss_node: LogicalNode = boss_edge.to_node
	if boss_node == null:
		return

	var key_id := "key_" + str(randi() % 100000)

	# 1. Skapa låst rum.
	var lock_node := LogicalNode.new()
	lock_node.id = "lock_" + str(randi() % 1000)
	lock_node.assigned_tags.assign(["Locked"])
	lock_node.blueprint = get_blueprint("Locked")

	# Skjut in låset mellan Target och Bossen.
	graph.insert_node_between(lock_node, target_node, boss_node)

	# Markera edge från lock room till boss som låst.
	var locked_edge := graph.find_edge(lock_node, boss_node)
	if locked_edge:
		locked_edge.edge_type = "locked"
		if not locked_edge.tags.has("locked"):
			locked_edge.tags.append("locked")

		locked_edge.requirements["key_id"] = key_id
		locked_edge.requirements["lock_id"] = "lock_for_" + key_id
		locked_edge.requirements["preferred_from_gateway_role"] = "locked_exit"
		locked_edge.requirements["preferred_to_gateway_role"] = "entrance"

	# 2. Skapa nyckel-rummet. Detta blir en förgrening / återvändsgränd.
	var key_node := LogicalNode.new()
	key_node.id = key_id
	key_node.assigned_tags.assign(["Key"])
	key_node.blueprint = get_blueprint("Key")
	key_node.custom_data["grants_key_id"] = key_id

	graph.add_node(key_node)

	var key_edge := graph.create_connection(target_node, key_node)
	key_edge.edge_type = "key_branch"

	if not key_edge.tags.has("key_branch"):
		key_edge.tags.append("key_branch")

	key_edge.effects["grants_key_id"] = key_id
	key_edge.requirements["preferred_to_gateway_role"] = "entrance"

	print("Regissör: Lade till Lås framför Boss, och en Nyckel-gren från ", target_node.id)


func _find_edge_to_boss(target_node: LogicalNode) -> LogicalEdge:
	for edge in target_node.out_edges:
		if edge == null:
			continue

		var next_node: LogicalNode = edge.to_node
		if next_node and next_node.assigned_tags.has("Boss"):
			return edge

	return null
