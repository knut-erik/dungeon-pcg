# LogicalGraph.gd
extends RefCounted
class_name LogicalGraph

var nodes: Array[LogicalNode] = []
var edges: Array[LogicalEdge] = []


func add_node(node: LogicalNode) -> void:
	if not nodes.has(node):
		nodes.append(node)


func add_edge(edge: LogicalEdge) -> void:
	if not edges.has(edge):
		edges.append(edge)

	if edge.from_node and not edge.from_node.out_edges.has(edge):
		edge.from_node.out_edges.append(edge)

	if edge.to_node and not edge.to_node.in_edges.has(edge):
		edge.to_node.in_edges.append(edge)


func _connect(
		from_node: LogicalNode,
		to_node: LogicalNode,
		edge_type: String = "normal",
		tags: Array[String] = []
	) -> LogicalEdge:

	var edge := LogicalEdge.new()
	edge.id = "%s_to_%s_%d" % [from_node.id, to_node.id, edges.size()]
	edge.from_node = from_node
	edge.to_node = to_node
	edge.edge_type = edge_type
	edge.tags.assign(tags)

	add_edge(edge)

	return edge


func insert_node_between(new_node: LogicalNode, node_a: LogicalNode, node_b: LogicalNode) -> void:
	add_node(new_node)

	var old_edge: LogicalEdge = null

	for edge in edges:
		if edge.from_node == node_a and edge.to_node == node_b:
			old_edge = edge
			break

	if old_edge == null:
		push_warning("insert_node_between: No edge found between %s and %s" % [node_a.id, node_b.id])
		_connect(node_a, new_node, "normal", [])
		_connect(new_node, node_b, "normal", [])
		return

	edges.erase(old_edge)
	node_a.out_edges.erase(old_edge)
	node_b.in_edges.erase(old_edge)

	var edge_a := _connect(node_a, new_node, old_edge.edge_type, old_edge.tags)
	var edge_b := _connect(new_node, node_b, old_edge.edge_type, old_edge.tags)

	# Preserve useful semantic data on both replacement edges.
	edge_a.requirements = old_edge.requirements.duplicate(true)
	edge_a.effects = old_edge.effects.duplicate(true)
	edge_a.custom_data = old_edge.custom_data.duplicate(true)

	edge_b.requirements = old_edge.requirements.duplicate(true)
	edge_b.effects = old_edge.effects.duplicate(true)
	edge_b.custom_data = old_edge.custom_data.duplicate(true)


func create_connection(from_node: LogicalNode, to_node: LogicalNode) -> LogicalEdge:
	return _connect(from_node, to_node, "normal", [])

func find_edge(from_node: LogicalNode, to_node: LogicalNode) -> LogicalEdge:
	for edge in edges:
		if edge.from_node == from_node and edge.to_node == to_node:
			return edge

	return null

'''extends RefCounted
class_name LogicalGraph

var nodes: Array[LogicalNode] = []

func add_node(node: LogicalNode):
	nodes.append(node)

# En säker metod för en regel (eller UI) att skjuta in en nod mellan två existerande
func insert_node_between(new_node: LogicalNode, node_a: LogicalNode, node_b: LogicalNode):
	# Hitta index för att hålla listan i någon form av ordning
	var index_a = nodes.find(node_a)
	if index_a != -1:
		nodes.insert(index_a + 1, new_node)
	else:
		nodes.append(new_node)
		
	# Fixa referenserna: A -> New -> B
	node_a.connections.erase(node_b)
	if not node_a.connections.has(new_node):
		node_a.connections.append(new_node)
	if not new_node.connections.has(node_b):
		new_node.connections.append(node_b)

# För Loop-generering (ditt requirement)
func create_connection(from_node: LogicalNode, to_node: LogicalNode):
	if not from_node.connections.has(to_node):
		from_node.connections.append(to_node)'''
