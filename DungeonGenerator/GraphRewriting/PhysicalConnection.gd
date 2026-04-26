class_name PhysicalConnection
extends RefCounted

var logical_edge: LogicalEdge

var from_node: LogicalNode
var to_node: LogicalNode

var from_room: BaseRoom
var to_room: BaseRoom

var from_anchor: PhysicalAnchor
var to_anchor: PhysicalAnchor

func validate_physical_assignments(assignments: Array[PhysicalConnection]) -> bool:
	for connection in assignments:
		if not connection.from_anchor or not connection.to_anchor:
			push_error("Unresolved physical connection for edge %s" % connection.logical_edge.id)
			return false
	return true
