# LogicalNode.gd
class_name LogicalNode
extends RefCounted

var id: String
var assigned_tags: Array[String] = []
var blueprint: RoomBlueprint
var custom_data: Dictionary = {}

var in_edges: Array[LogicalEdge] = []
var out_edges: Array[LogicalEdge] = []


func degree() -> int:
	return in_edges.size() + out_edges.size()


func get_connected_nodes() -> Array[LogicalNode]:
	var result: Array[LogicalNode] = []

	for edge in out_edges:
		if edge.to_node:
			result.append(edge.to_node)

	for edge in in_edges:
		if edge.from_node:
			result.append(edge.from_node)

	return result

'''class_name LogicalNode
extends RefCounted

var id: String
var assigned_tags: Array[String] = []
var connections: Array[LogicalNode] = []
var blueprint: RoomBlueprint # Referens till vilken typ av rum som ska byggas
var custom_data: Dictionary = {} # Används för att skicka unika parametrar, t.ex. delta_y för gateways'''
