# LogicalGraph.gd
extends RefCounted
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
		from_node.connections.append(to_node)
