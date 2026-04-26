extends Marker3D
class_name Gateway

@export var gateway_id: String = ""
@export var role: String = "any"
@export var max_connections: int = 1

@export var allows_scene_transition: bool = false
@export var allows_lock: bool = true
@export var allows_secret: bool = true
@export var allows_loop: bool = true

var connected_edges: Array[LogicalEdge] = []

func is_available_for_edge(edge: LogicalEdge) -> bool:
	if connected_edges.size() >= max_connections:
		return false

	if edge.edge_type == "scene_transition" and not allows_scene_transition:
		return false

	if edge.edge_type == "locked" and not allows_lock:
		return false

	if edge.edge_type == "secret" and not allows_secret:
		return false

	if edge.edge_type == "boss_return" and not allows_loop:
		return false

	if role != "any":
		var preferred : String = edge.requirements.get("preferred_gateway_role", "")
		if preferred != "" and preferred != role:
			return false

	return true

func claim(edge: LogicalEdge) -> void:
	connected_edges.append(edge)
	set_meta("is_connected", true)
