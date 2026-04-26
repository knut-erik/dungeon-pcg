extends RefCounted
class_name PhysicalAnchor

enum AnchorKind {
	ROOM_GATEWAY,
	CORRIDOR_POINT,
	SCENE_TRANSITION,
	GENERATED_JUNCTION
}

var kind: int = AnchorKind.ROOM_GATEWAY
var world_position: Vector3 = Vector3.ZERO
var forward: Vector3 = Vector3.FORWARD
var owner_node: LogicalNode
var owner_edge: LogicalEdge
var gateway: Gateway


static func from_gateway(gw: Gateway, edge: LogicalEdge, node: LogicalNode) -> PhysicalAnchor:
	var anchor := PhysicalAnchor.new()
	anchor.kind = AnchorKind.ROOM_GATEWAY
	anchor.world_position = gw.global_position
	anchor.forward = -gw.global_transform.basis.z
	anchor.owner_node = node
	anchor.owner_edge = edge
	anchor.gateway = gw
	return anchor
