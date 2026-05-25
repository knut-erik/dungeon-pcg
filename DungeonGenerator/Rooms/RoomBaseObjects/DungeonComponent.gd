class_name DungeonComponent
extends Node3D

@export var component_id: String
@export var component_type: String

var logical_node: LogicalNode
var logical_edge: LogicalEdge

func bind_to_logic(_node: LogicalNode, _edge: LogicalEdge = null) -> void:
	logical_node = _node
	logical_edge = _edge
