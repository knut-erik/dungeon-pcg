# BaseRoom.gd
extends Node3D
class_name BaseRoom

var room_size: Vector3 = Vector3.ZERO

# Dessa tilldelas i barn-klassernas _ready() funktioner
var gateway_in: Marker3D
var gateway_out: Marker3D

# Returns world-space AABBs for all bounding volumes of this room.
#
# IMPORTANT FOR FUTURE ROOM AUTHORS:
# This function transforms each Area3D CollisionShape3D into world space,
# correctly accounting for the room's position, rotation, and scale.
# You do NOT need to override this function — just ensure your bounding
# volume is an Area3D > CollisionShape3D(BoxShape3D) as a direct child
# of the room node. The system handles the rest.
#
# DO NOT manually offset these AABBs by room.position in calling code —
# they are already in world space.
func get_world_aabbs() -> Array[AABB]:
	var aabbs: Array[AABB] = []
	for child in get_children():
		if child is Area3D:
			var col_shape = child.get_node_or_null("CollisionShape3D")
			if col_shape and col_shape.shape is BoxShape3D:
				var box_size: Vector3 = col_shape.shape.size
				
				# Sanity check — a default-sized or zero box means setup_room
				# failed to set the shape size, likely due to a shared resource.
				# Fix: call shape.shape = shape.shape.duplicate() before setting size.
				if box_size.length() < 0.5:
					push_warning("get_world_aabbs: BoxShape3D on '%s' has near-zero size %s. Did you forget to duplicate() the shape resource in setup_room()?" % [name, box_size])
				
				# col_shape may itself have an offset transform inside the Area3D.
				# Use the CollisionShape3D's global_transform to get the true
				# world-space center, then build an axis-aligned bounding box
				# by transforming all 8 corners and re-bounding.
				# This is correct even when the room has been rotated by look_at().
				var center_xform: Transform3D = col_shape.global_transform
				var half := box_size / 2.0
				var corners := [
					center_xform * Vector3(-half.x, -half.y, -half.z),
					center_xform * Vector3( half.x, -half.y, -half.z),
					center_xform * Vector3(-half.x,  half.y, -half.z),
					center_xform * Vector3( half.x,  half.y, -half.z),
					center_xform * Vector3(-half.x, -half.y,  half.z),
					center_xform * Vector3( half.x, -half.y,  half.z),
					center_xform * Vector3(-half.x,  half.y,  half.z),
					center_xform * Vector3( half.x,  half.y,  half.z),
				]
				var mn : Vector3 = corners[0]
				var mx : Vector3 = corners[0]
				for c in corners:
					mn = Vector3(minf(mn.x, c.x), minf(mn.y, c.y), minf(mn.z, c.z))
					mx = Vector3(maxf(mx.x, c.x), maxf(mx.y, c.y), maxf(mx.z, c.z))
				aabbs.append(AABB(mn, mx - mn))
	return aabbs

# Rummen måste kunna svara på vilka gateways de har lediga
func get_gateways() -> Array[Gateway]:
	var result: Array[Gateway] = []
	for child in find_children("*", "Gateway", true, false):
		result.append(child)
	if result.is_empty():
		push_warning("%s has no Gateway nodes. Replace old Marker3D targets with Gateway.tscn." % name)
	return result

func claim_gateway_for_edge(edge: LogicalEdge, as_source: bool) -> Gateway:
	var candidates := get_gateways()

	# Prefer role-compatible gateways.
	for gateway in candidates:
		if gateway and gateway.is_available_for_edge(edge):
			var preferred_role: String = edge.requirements.get(
				"preferred_from_gateway_role" if as_source else "preferred_to_gateway_role",
				""
			)

			if preferred_role != "" and gateway.role == preferred_role:
				gateway.claim(edge)
				return gateway

	# Otherwise allow any compatible gateway.
	for gateway in candidates:
		if gateway and gateway.is_available_for_edge(edge):
			gateway.claim(edge)
			return gateway

	return null

'''func get_available_gateway_in() -> Marker3D:
	if gateway_in and not gateway_in.get_meta("is_connected", false): 
		return gateway_in
	return null

func get_available_gateway_out() -> Marker3D:
	if gateway_out and not gateway_out.get_meta("is_connected", false): 
		return gateway_out
	return null'''

# Denna MÅSTE skrivas över av barn-klasserna
# setup_room MAY contain awaits (e.g. for CSG to settle).
# Callers MUST await this function.
func setup_room(_rng: RandomNumberGenerator, _logic_node: LogicalNode):
	push_warning("setup_room() anropades på BaseRoom. Detta bör göras i barn-klassen!")
